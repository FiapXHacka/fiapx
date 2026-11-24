# 5. Dados

Decisões: [ADR-0009](../adr/0009-postgresql-banco-por-servico.md), [ADR-0008](../adr/0008-armazenamento-s3-presigned-urls.md), [ADR-0010](../adr/0010-redis-cache-e-rate-limit.md).
Os scripts oficiais ficam em `db/schema.sql` de cada serviço e são aplicados pelas migrations do EF Core. O script
que cria bancos e usuários fica no `fiapx-infra-db`. A versão de referência completa está em [`../database/`](../database/).

## 5.1 Máquina de estados do vídeo

```mermaid
stateDiagram-v2
    [*] --> PENDING_UPLOAD: POST /videos
    PENDING_UPLOAD --> UPLOADED: POST upload-complete (HEAD ok)
    PENDING_UPLOAD --> EXPIRED: reconciliador (> 1 h)
    UPLOADED --> PROCESSING: video.processing-started
    UPLOADED --> COMPLETED: video.processed (started perdido/atrasado)
    UPLOADED --> FAILED: video.processing-failed / timeout
    PROCESSING --> COMPLETED: video.processed
    PROCESSING --> FAILED: video.processing-failed / timeout
    COMPLETED --> [*]
    FAILED --> [*]
    EXPIRED --> [*]
```

Regras:
- Transições não listadas são **ignoradas** (log `info`), nunca lançam erro ao consumidor. É isso que garante a idempotência e a tolerância a eventos fora de ordem.
- `COMPLETED`, `FAILED` e `EXPIRED` são terminais. Reprocessar é uma evolução (um novo vídeo com o mesmo arquivo).

## 5.2 Modelo relacional

```mermaid
erDiagram
    USERS {
        uuid id PK
        text email UK "lower(email) único"
        text name
        text password_hash
        timestamptz created_at
    }
    VIDEOS {
        uuid id PK
        uuid user_id "sem FK: outro serviço"
        text original_file_name
        text content_type
        bigint size_bytes
        text storage_key
        text status
        int frame_count
        text result_key
        bigint result_size_bytes
        text error_code
        text error_message
        timestamptz created_at
        timestamptz uploaded_at
        timestamptz processing_started_at
        timestamptz finished_at
        timestamptz updated_at
        int version "concorrência otimista"
    }
    USER_CONTACTS {
        uuid user_id PK
        text email
        text name
        timestamptz updated_at
    }
    NOTIFICATIONS {
        uuid id PK
        uuid user_id
        uuid video_id
        text type "VIDEO_FAILED | VIDEO_COMPLETED"
        text status "PENDING | SENT | FAILED"
        int attempts
        text last_error
        timestamptz created_at
        timestamptz sent_at
    }
    OUTBOX_MESSAGES {
        uuid id PK
        text type
        jsonb payload "CloudEvent completo"
        timestamptz occurred_at
        timestamptz published_at
        int attempts
    }
    INBOX_MESSAGES {
        uuid message_id PK
        text consumer PK
        timestamptz processed_at
    }
    USER_CONTACTS ||--o{ NOTIFICATIONS : "recebe"
```

| Banco | Tabelas | Dono |
|---|---|---|
| `identity_db` | `users`, `outbox_messages` | identity-service |
| `video_db` | `videos`, `outbox_messages`, `inbox_messages` | video-api |
| `notification_db` | `user_contacts`, `notifications`, `inbox_messages` | notification-service |

## 5.3 Armazenamento de objetos

| Prefixo | Conteúdo | Escrito por | Lido por | Lifecycle |
|---|---|---|---|---|
| `uploads/{userId}/{videoId}/original.{ext}` | Vídeo enviado | cliente (URL pré-assinada) | video-processor | 7 dias |
| `results/{userId}/{videoId}/frames.zip` | Zip dos frames | video-processor | cliente (URL pré-assinada) | 30 dias |

Uploads multipart incompletos são abortados após 1 dia (regra de lifecycle).

## 5.4 Redis

| Chave | Valor | TTL | Invalidação |
|---|---|---|---|
| `videos:user:{userId}:page:{n}:{statusFilter}` | JSON da página | 30 s | mudança de status de qualquer vídeo do usuário |
| `videos:user:{userId}:keys` | set com as chaves acima | 30 s | junto com as chaves |
| `rl:login:{ip}:{emailHash}` | contador | 60 s | — |
| `rl:videos:{userId}` | contador | 60 s | — |
