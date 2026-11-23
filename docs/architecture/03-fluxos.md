# 3. Fluxos

## 3.1 Visão geral (fluxo feliz)

```mermaid
flowchart LR
    A[Cadastro] --> B[Login → JWT] --> C[POST /videos<br/>URL pré-assinada] --> D[PUT no S3] --> E[POST upload-complete<br/>status UPLOADED] --> F[(fila)] --> G[Worker extrai frames<br/>e gera o zip] --> H[status COMPLETED] --> I[GET download<br/>URL pré-assinada]
    G -- erro --> J[status FAILED] --> K[E-mail ao usuário]
```

## 3.2 Cadastro e login

```mermaid
sequenceDiagram
    autonumber
    actor U as Usuário
    participant GW as API Gateway
    participant ID as identity-service
    participant DB as identity_db
    participant MQ as RabbitMQ
    participant NS as notification-service

    U->>GW: POST /auth/register {name, email, password}
    GW->>ID: (rota pública)
    ID->>ID: valida e calcula o hash PBKDF2
    ID->>DB: transação: INSERT users + INSERT outbox(user.registered)
    ID-->>U: 201 Created
    ID--)MQ: (outbox relay) user.registered
    MQ--)NS: user.registered
    NS->>NS: upsert user_contacts

    U->>GW: POST /auth/login {email, password}
    GW->>ID: (rota pública, rate limit 5/min)
    ID->>DB: SELECT user by email
    ID->>ID: verifica o hash e assina o JWT RS256 (kid)
    ID-->>U: 200 {accessToken, expiresIn: 3600}
```

## 3.3 Upload do vídeo

```mermaid
sequenceDiagram
    autonumber
    actor U as Usuário
    participant GW as API Gateway
    participant API as video-api
    participant DB as video_db
    participant S3 as S3
    participant MQ as RabbitMQ

    U->>GW: POST /videos {fileName, contentType, sizeBytes} + Bearer
    GW->>GW: JWT authorizer (JWKS em cache)
    GW->>API: request + claims
    API->>API: valida extensão e tamanho (≤ 500 MB)
    API->>DB: INSERT video (PENDING_UPLOAD)
    API->>S3: presign PUT uploads/{userId}/{videoId}/original.mp4 (15 min)
    API-->>U: 201 {videoId, uploadUrl, expiresAt}

    U->>S3: PUT uploadUrl (bytes do vídeo — não passa pela API)
    S3-->>U: 200

    U->>GW: POST /videos/{id}/upload-complete
    GW->>API: request
    API->>S3: HEAD object (existe? tamanho?)
    API->>DB: transação: UPDATE status=UPLOADED + INSERT outbox(video.uploaded)
    API->>API: invalida o cache videos:user:{userId}
    API-->>U: 202 Accepted {status: UPLOADED}
    API--)MQ: (outbox relay, publisher confirm) video.uploaded
```

## 3.4 Processamento — sucesso

```mermaid
sequenceDiagram
    autonumber
    participant MQ as RabbitMQ
    participant W as video-processor
    participant S3 as S3
    participant API as video-api
    participant NS as notification-service

    MQ->>W: video.uploaded (prefetch 1 por slot)
    W->>S3: HEAD results/.../frames.zip
    alt zip já existe (reentrega)
        W--)MQ: video.processed (republica)
        W->>MQ: ack
    else primeira vez
        W--)MQ: video.processing-started
        MQ--)API: processing-started → status PROCESSING
        W->>S3: GET original → /work/{videoId}
        W->>W: ffprobe (formato, duração ≤ 10 min)
        W->>W: ffmpeg -vf fps=1 → frame_0001.png…
        W->>S3: multipart PUT frames.zip (streaming)
        W--)MQ: video.processed {frameCount, resultKey} (confirm)
        W->>MQ: ack video.uploaded
        W->>W: rm -rf /work/{videoId}
    end
    MQ--)API: video.processed
    API->>API: inbox + transição PROCESSING→COMPLETED + invalida o cache
    MQ--)NS: video.processed
    NS->>NS: (opcional) e-mail "seu zip está pronto"
```

## 3.5 Processamento — falha, retry e DLQ

```mermaid
sequenceDiagram
    autonumber
    participant MQ as RabbitMQ
    participant W as video-processor
    participant DLQ as video-uploaded.dlq
    participant API as video-api
    participant NS as notification-service
    participant SMTP as SES / Mailpit
    actor U as Usuário

    MQ->>W: video.uploaded
    alt erro permanente (INVALID_VIDEO, VIDEO_TOO_LONG, NO_FRAMES)
        W--)MQ: video.processing-failed {errorCode}
        W->>MQ: ack (não reprocessa)
    else erro transitório (S3 ou broker fora)
        W->>W: retry em processo 1 s, 4 s, 16 s
        W->>MQ: nack(requeue) → delivery-count++
        Note over MQ: na 3ª entrega (x-delivery-limit) → DLX
        MQ->>DLQ: dead-letter
        DLQ->>W: consumidor da DLQ
        W--)MQ: video.processing-failed {MAX_ATTEMPTS_EXCEEDED}
    end
    MQ--)API: video.processing-failed → status FAILED (+errorCode)
    MQ--)NS: video.processing-failed
    NS->>NS: inbox, busca o e-mail em user_contacts
    NS->>SMTP: envia "Não conseguimos processar seu vídeo"
    SMTP-->>U: e-mail
```

## 3.6 Listagem de status e download

```mermaid
sequenceDiagram
    autonumber
    actor U as Usuário
    participant API as video-api
    participant R as Redis
    participant DB as video_db
    participant S3 as S3

    U->>API: GET /videos?page=1&status=… (Bearer)
    API->>R: GET videos:user:{sub}:page:1
    alt hit
        R-->>API: json
    else miss
        API->>DB: SELECT … WHERE user_id = sub ORDER BY created_at DESC
        API->>R: SET … EX 30
    end
    API-->>U: 200 [{id, fileName, status, frameCount, errorCode, createdAt, completedAt}]

    U->>API: GET /videos/{id}/download
    API->>DB: SELECT WHERE id = ? AND user_id = sub
    alt não é do usuário ou não existe
        API-->>U: 404
    else status != COMPLETED
        API-->>U: 409 {status}
    else
        API->>S3: presign GET results/.../frames.zip (5 min)
        API-->>U: 302 Location: URL pré-assinada
    end
```

## 3.7 Reconciliação (rede de segurança)

```mermaid
sequenceDiagram
    participant J as video-api (job a cada 5 min)
    participant DB as video_db
    participant MQ as RabbitMQ
    J->>DB: PENDING_UPLOAD há > 1 h
    J->>DB: → EXPIRED
    J->>DB: UPLOADED ou PROCESSING há > 30 min
    J->>DB: → FAILED (PROCESSING_TIMEOUT) + outbox video.processing-failed
    DB--)MQ: relay → notification-service envia e-mail
```

## 3.8 Pico de requisições

```mermaid
sequenceDiagram
    participant C as 100 clientes
    participant API as video-api (2 pods)
    participant MQ as fila video-uploaded
    participant K as KEDA
    participant W as workers

    C->>API: 100× upload-complete em 1 min
    API-->>C: 100× 202 (só INSERT + outbox, ms)
    API--)MQ: 100 mensagens
    K->>MQ: lê queueLength = 100
    K->>W: escala 1 → 10 pods (queueLength alvo 2/pod, até o máximo)
    W->>MQ: consomem em paralelo
    Note over MQ,W: fila drena em ~3–5 min, nenhuma requisição recusada
    K->>W: cooldown 120 s → volta a 1
```
