# FIAP X — Plataforma de processamento de vídeos

Hackathon da Fase 5 da POS Tech FIAP (Software Architecture). Usuários autenticados enviam vídeos, a plataforma extrai
1 frame por segundo e disponibiliza um `.zip` com as imagens, de forma **assíncrona, escalável e sem perder requisições**.

Este repositório é o **hub da plataforma**: arquitetura, decisões (ADRs), contratos de mensagem, scripts de banco
e o ambiente local completo. O código de cada serviço fica no repositório dele.

## Repositórios

| Repositório | Responsabilidade | Stack |
|---|---|---|
| **`fiapx`** (este) | Arquitetura, ADRs, contratos, docker-compose da plataforma, E2E | Markdown, Mermaid, AsyncAPI |
| [`fiapx-identity-service`](https://github.com/FiapXHacka/fiapx-identity-service) | Cadastro, login, JWT RS256 / JWKS | .NET 10 |
| [`fiapx-video-api`](https://github.com/FiapXHacka/fiapx-video-api) | Ciclo de vida do vídeo, URLs pré-assinadas, status | .NET 10 |
| [`fiapx-video-processor`](https://github.com/FiapXHacka/fiapx-video-processor) | Extração de frames (ffmpeg) e zip | Go |
| [`fiapx-notification-service`](https://github.com/FiapXHacka/fiapx-notification-service) | E-mail em falha/sucesso | .NET 10 |
| [`fiapx-infra-k8s`](https://github.com/FiapXHacka/fiapx-infra-k8s) | VPC, EKS, ECR, API Gateway, RabbitMQ, Redis, KEDA, observabilidade | Terraform, Helm |
| [`fiapx-infra-db`](https://github.com/FiapXHacka/fiapx-infra-db) | RDS PostgreSQL, S3 | Terraform |

## Visão geral

```mermaid
flowchart LR
    U((Usuário)) --> GW[API Gateway<br/>JWT]
    U -. "PUT/GET pré-assinado" .-> S3[(S3)]
    GW --> ID[identity-service]
    GW --> API[video-api]
    API -- video.uploaded --> MQ{{RabbitMQ}}
    MQ --> W[video-processor ×N]
    W --> S3
    W -- processed / failed --> MQ
    MQ --> API
    MQ --> NS[notification-service] --> M[E-mail]
    ID & API & NS --> PG[(PostgreSQL)]
    API --> R[(Redis)]
```

## Documentação

| Documento | Conteúdo |
|---|---|
| [1. Contexto e requisitos](docs/architecture/01-contexto-e-requisitos.md) | Diagnóstico do protótipo, RF/RNF e como cada um é atendido |
| [2. System design](docs/architecture/02-system-design.md) | C4 (contexto, containers, componentes), implantação AWS, capacidade, modos de falha, segurança |
| [3. Fluxos](docs/architecture/03-fluxos.md) | Sequências: cadastro/login, upload, processamento, falha/DLQ, status/download, reconciliação, pico |
| [4. Mensageria](docs/architecture/04-mensageria.md) | Topologia RabbitMQ, catálogo de eventos, regras de consumo |
| [5. Dados](docs/architecture/05-dados.md) | Máquina de estados, modelo relacional, S3, Redis |
| [ADRs](docs/adr/README.md) | 18 decisões de arquitetura |
| [Contratos (AsyncAPI)](docs/contracts/asyncapi.yaml) | Fonte da verdade dos eventos |
| [Scripts de banco](docs/database/) | Criação dos bancos, usuários e tabelas |
| [SonarCloud](docs/sonarcloud.md) | Configuração da análise e quality gate |

## Ambiente local

O `docker-compose.yml` deste repositório sobe a plataforma inteira na sua máquina (ADR-0013).

### 1. Clonar os repositórios lado a lado

Os serviços são construídos a partir dos repositórios irmãos, então todos precisam estar no mesmo diretório:

```bash
mkdir fiapx-hacka && cd fiapx-hacka
for r in fiapx fiapx-identity-service fiapx-video-api fiapx-video-processor fiapx-notification-service; do
  gh repo clone FiapXHacka/$r
done
cd fiapx && cp .env.example .env   # credenciais fictícias, só para uso local
```

### 2. Subir

```bash
docker compose up -d --wait                  # só a infraestrutura
docker compose --profile apps up -d --build  # infraestrutura + os 4 serviços
docker compose down -v                       # derruba e apaga os volumes
```

Na primeira subida, o Postgres cria só os bancos e um usuário por serviço (`docs/database/00-create-databases.sql`).
Cada usuário é dono do seu banco. As tabelas são criadas pelos próprios serviços, que aplicam as migrations do EF Core
ao iniciar (`Database__MigrateOnStartup=true`). As migrations são a única fonte do schema.
O RabbitMQ importa a topologia de [`local/rabbitmq/definitions.json`](local/rabbitmq/definitions.json), igual à de [04-mensageria](docs/architecture/04-mensageria.md).
O job `s3-init` cria o bucket com CORS e lifecycle.

### 3. Endereços

| O quê | URL | Acesso |
|---|---|---|
| API (gateway Traefik) | http://localhost:8080 | `/auth/*`, `/.well-known/*` → identity · `/videos/*` → video-api |
| Painel do Traefik | http://localhost:8088/dashboard/ | — |
| RabbitMQ Management | http://localhost:15672 | `fiapx` / `fiapx-local` |
| S3 (RustFS): API / console | http://localhost:9000 / http://localhost:9001 | `S3_ACCESS_KEY` / `S3_SECRET_KEY` do `.env` |
| Mailpit (e-mails enviados) | http://localhost:8025 | — |
| Grafana (traces, métricas, logs) | http://localhost:3000 | `admin` / `admin` |
| Postgres | `localhost:15432` | `postgres` / `POSTGRES_PASSWORD` do `.env` |
| Redis | `localhost:6379` | — |
| Serviços direto (sem gateway) | identity :8091 · video-api :8092 · notification :8093 | — |

As portas podem ser trocadas no `.env` se alguma já estiver ocupada na sua máquina.

> **S3 local:** a MinIO deixou de publicar imagens da edição comunitária, por isso o ambiente local usa o
> [RustFS](https://github.com/rustfs/rustfs), que é compatível com a API do S3. Para os serviços, a diferença é só o endpoint.

## Como o time trabalha

- Backlog no [GitHub Project da organização](https://github.com/orgs/FiapXHacka/projects). As issues ficam no repositório onde o código muda.
- Branch `feat/<nº-issue>-descricao` → PR com `Closes FiapXHacka/<repo>#<nº>` → 1 aprovação + CI + quality gate.
- Decisão nova ou alterada → ADR em PR neste repositório ([como escrever](docs/adr/README.md)).

## Entregáveis do hackathon

- [ ] Documentação da arquitetura (este repositório)
- [ ] Scripts de criação do banco e dos demais recursos (`docs/database/`, `fiapx-infra-*`)
- [ ] Links dos repositórios no GitHub
- [ ] Vídeo de até 10 minutos: documentação, arquitetura e projeto funcionando
