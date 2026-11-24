# Architecture Decision Records (ADRs)

Cada decisão de arquitetura relevante do FIAP X é registrada aqui, em um arquivo numerado e imutável.
Se uma decisão mudar, cria-se um ADR novo que **substitui** o anterior (e o anterior passa a `Substituído por ADR-XXXX`).

## Status possíveis

| Status | Significado |
|---|---|
| **Proposto** | Escrito e aberto para revisão do grupo (comentar no PR ou na issue). |
| **Aceito** | Aprovado pelo grupo — vale para a implementação. |
| **Substituído** | Trocado por um ADR mais novo (link no topo). |
| **Rejeitado** | Discutido e descartado; mantido para histórico. |

## Índice

| # | Decisão | Status |
|---|---|---|
| [0001](0001-registrar-decisoes-com-adrs.md) | Registrar decisões de arquitetura com ADRs | Aceito |
| [0002](0002-decomposicao-em-microsservicos.md) | Decomposição em quatro microsserviços | Proposto |
| [0003](0003-linguagens-dotnet-e-go.md) | .NET 10 nas APIs e Go no processador de vídeo | Aceito |
| [0004](0004-repositorios-por-responsabilidade.md) | Um repositório por responsabilidade (polyrepo) | Aceito |
| [0005](0005-processamento-assincrono-rabbitmq.md) | Processamento assíncrono com RabbitMQ | Aceito |
| [0006](0006-contratos-de-mensagem-cloudevents.md) | Contratos de mensagem em CloudEvents + AsyncAPI, sem MassTransit | Proposto |
| [0007](0007-entrega-confiavel-outbox-inbox.md) | Entrega confiável: outbox, inbox, publisher confirms e idempotência | Proposto |
| [0008](0008-armazenamento-s3-presigned-urls.md) | Vídeos e zips no S3 com URLs pré-assinadas | Proposto |
| [0009](0009-postgresql-banco-por-servico.md) | PostgreSQL com banco por serviço | Proposto |
| [0010](0010-redis-cache-e-rate-limit.md) | Redis para cache de status e rate limiting | Proposto |
| [0011](0011-autenticacao-jwt-rs256.md) | Autenticação por usuário e senha com JWT RS256 + JWKS | Proposto |
| [0012](0012-notificacao-por-email.md) | Notificação por e-mail em serviço dedicado | Proposto |
| [0013](0013-infraestrutura-aws-eks-compose.md) | AWS EKS + Terraform na nuvem, Docker Compose local | Aceito |
| [0014](0014-escalabilidade-hpa-keda.md) | Escalabilidade: HPA nas APIs, KEDA no worker | Proposto |
| [0015](0015-observabilidade-opentelemetry.md) | Observabilidade com OpenTelemetry + Prometheus/Grafana | Proposto |
| [0016](0016-estrategia-de-testes-e-sonarcloud.md) | Estratégia de testes e quality gate no SonarCloud | Aceito |
| [0017](0017-ci-cd-github-actions.md) | CI/CD com GitHub Actions | Proposto |
| [0018](0018-regras-de-processamento-de-video.md) | Regras e limites do processamento de vídeo | Proposto |

## Template

Copie [`template.md`](template.md) para `NNNN-titulo-em-kebab-case.md`.
