# ADR-0008: Vídeos e zips no S3 com URLs pré-assinadas

- **Status:** Proposto
- **Data:** 2026-11-23
- **Decisores:** time FIAP X
- **Requisitos relacionados:** RF-01, RF-02, RNF-01 (persistir dados), RNF-02

## Contexto

- O projeto base grava os arquivos em `./uploads` e `./outputs`, ou seja, no disco do container. Com mais de uma réplica, ou depois de um restart, os arquivos somem.
- O **API Gateway HTTP API limita o payload a 10 MB**. Um vídeo não passa por ele.
- Fazer streaming de centenas de MB pelos pods da API consome memória, conexões e banda sem necessidade.

## Decisão

1. **Amazon S3** (MinIO no ambiente local) como armazenamento de objetos, num bucket privado:
   ```
   s3://fiapx-videos-<env>/
     uploads/{userId}/{videoId}/original.{ext}     # lifecycle: apagar após 7 dias
     results/{userId}/{videoId}/frames.zip         # lifecycle: apagar após 30 dias
   ```
2. **Upload direto do cliente para o S3:**
   - `POST /videos` cria o registro `PENDING_UPLOAD` e devolve uma **URL pré-assinada de PUT** (15 min, `Content-Type` e tamanho declarados assinados).
   - O cliente faz o `PUT` no S3.
   - `POST /videos/{id}/upload-complete`: a API faz `HEAD` no objeto, valida o tamanho (≤ limite do [ADR-0018](0018-regras-de-processamento-de-video.md)) e passa o vídeo para `UPLOADED` + outbox `video.uploaded`.
3. **Download:** `GET /videos/{id}/download` confere o dono e responde `302` para uma **URL pré-assinada de GET** (5 min).
4. O worker faz streaming do zip para o S3 com *multipart upload* (`io.Pipe`), sem materializar o zip inteiro no disco.
5. Segurança: *Block Public Access*, SSE-S3, política de bucket permitindo apenas os papéis IRSA da `video-api` e do `video-processor`, e CORS restrito à origem do front.

## Alternativas consideradas

| Alternativa | Por que não |
|---|---|
| Upload multipart passando pela API | Esbarra no limite de 10 MB do API Gateway e prende os pods em I/O. |
| EFS/PVC compartilhado | Caro, lento para muitos arquivos pequenos e sem URL de download. |
| Guardar o vídeo no Postgres (bytea) | Não escala; backup e réplica inviáveis. |
| S3 Event Notification → SQS para confirmar o upload | Mais confiável que o callback do cliente, mas adiciona SQS só para isso. Fica registrado como evolução. O reconciliador expira uploads não confirmados. |

## Consequências

**Positivas**
- A API não vê os bytes do vídeo: requisições pequenas e rápidas, e o pico de uploads não pesa nos pods.
- O download do zip também não passa pela API.

**Negativas / riscos**
- O cliente precisa de 3 chamadas (criar, PUT, confirmar). O front/Postman da demo deve encapsular isso.
- PUT pré-assinado não garante o tamanho no S3 (a garantia vem do `HEAD` na confirmação). Uma alternativa é *presigned POST* com `content-length-range`.
- Uploads abandonados: o reconciliador marca `EXPIRED` depois de 1 h, e o lifecycle limpa o objeto.
