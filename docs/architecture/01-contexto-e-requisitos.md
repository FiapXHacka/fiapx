# 1. Contexto e requisitos

## Problema

A FIAP X apresentou aos investidores um protótipo (Go + Gin, um único `main.go`) que recebe um vídeo, extrai
1 frame por segundo com ffmpeg e devolve um `.zip` com as imagens. Os investidores querem uma versão em que possam
**enviar vídeos e baixar o zip** com segurança e em escala.

### Diagnóstico do protótipo

| Problema no protótipo | Consequência | Onde resolvemos |
|---|---|---|
| ffmpeg roda dentro da requisição HTTP | Conexões presas por minutos, timeout no gateway, pico derruba o processo | [ADR-0005](../adr/0005-processamento-assincrono-rabbitmq.md) |
| Arquivos no disco local do container | Não escala horizontalmente e perde arquivos em restart | [ADR-0008](../adr/0008-armazenamento-s3-presigned-urls.md) |
| Sem banco: status = listar pasta | Não há histórico nem status por usuário | [ADR-0009](../adr/0009-postgresql-banco-por-servico.md) |
| Sem autenticação, CORS `*`, `/uploads` e `/outputs` públicos | Qualquer pessoa baixa os vídeos de qualquer usuário | [ADR-0011](../adr/0011-autenticacao-jwt-rs256.md) |
| Nome do arquivo = timestamp em segundos | Colisão com uploads simultâneos | IDs `uuid` v7 |
| Sem limites de tamanho/duração | Um vídeo grande esgota o disco | [ADR-0018](../adr/0018-regras-de-processamento-de-video.md) |
| Erro só no JSON da resposta | Usuário não fica sabendo de falhas | [ADR-0012](../adr/0012-notificacao-por-email.md) |
| Dockerfile com `go run`, sem testes nem CI | Imagem grande, sem garantia de qualidade | [ADR-0016](../adr/0016-estrategia-de-testes-e-sonarcloud.md), [ADR-0017](../adr/0017-ci-cd-github-actions.md) |

## Requisitos funcionais

| ID | Requisito (PDF) | Como atendemos |
|---|---|---|
| RF-01 | Processar mais de um vídeo ao mesmo tempo | Fila + N workers × M goroutines, com KEDA escalando pela fila |
| RF-02 | Em picos, não perder nenhuma requisição | Upload direto no S3, outbox transacional, filas quorum duráveis, ack manual, DLQ, reconciliador |
| RF-03 | Sistema protegido por usuário e senha | `identity-service` (PBKDF2 + JWT RS256), JWT authorizer no API Gateway e validação em cada serviço |
| RF-04 | Listar o status dos vídeos do usuário | `GET /videos` paginado, filtrado pelo `sub` do token, com cache Redis |
| RF-05 | Notificar o usuário em caso de erro | `notification-service` consome `video.processing-failed` e envia e-mail |
| RF-06 | Baixar o zip (implícito na introdução) | `GET /videos/{id}/download` → URL pré-assinada |

## Requisitos não funcionais

| ID | Requisito | Como atendemos |
|---|---|---|
| RNF-01 | Persistir os dados | PostgreSQL (metadados) + S3 (arquivos) |
| RNF-02 | Arquitetura escalável | Microsserviços stateless, HPA nas APIs, KEDA no worker, cluster autoscaler |
| RNF-03 | Testes que garantam qualidade | Pirâmide de testes, Testcontainers, quality gate no SonarCloud (≥ 80% em código novo) |
| RNF-04 | Versionado no GitHub | Organização `FiapXHacka`, um repositório por responsabilidade |
| RNF-05 | CI/CD | GitHub Actions: CI + Sonar em PR, deploy no EKS na `main`, Terraform com plan/apply |
| RNF-06 | Observabilidade (stack recomendada) | OpenTelemetry → Prometheus, Tempo, Loki e Grafana |
| RNF-07 | Segurança | Senhas com hash, JWT assimétrico, bucket privado, URLs pré-assinadas curtas, IRSA, secrets fora do código |

## Fora de escopo (evoluções registradas)

Front-end elaborado (a demo usa Postman/Swagger e uma página simples), refresh token, vídeos acima dos limites
(processamento segmentado), notificação push/WebSocket, multi-região.

## Glossário

| Termo | Significado |
|---|---|
| Vídeo | Pedido de processamento de um arquivo enviado por um usuário (agregado da `video-api`) |
| Frame | Imagem PNG extraída a cada 1 s do vídeo |
| Resultado | `frames.zip` com todos os frames, no S3 |
| Evento | Mensagem CloudEvents publicada no RabbitMQ ([04-mensageria](04-mensageria.md)) |
