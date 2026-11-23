# ADR-0009: PostgreSQL com banco por serviço

- **Status:** Proposto
- **Data:** 2026-11-23
- **Decisores:** time FIAP X
- **Requisitos relacionados:** RNF-01 (persistir dados)

## Contexto

Os dados do sistema são relacionais e pequenos (usuários, metadados de vídeo, notificações). Os bytes ficam no S3.
Na fase 4 adotamos banco por serviço (ADR-012 do Torque-OS) e PostgreSQL no RDS.

## Decisão

- **PostgreSQL 17** (Amazon RDS na nuvem e container no ambiente local).
- **Um banco lógico por serviço**, com usuário próprio e sem permissão cruzada, numa única instância RDS para controlar custo:
  `identity_db`, `video_db`, `notification_db`. O `video-processor` não tem banco.
- Schema versionado com **migrations do EF Core**. O script SQL equivalente fica em `db/schema.sql` de cada serviço, e o script que cria os bancos e usuários fica no `fiapx-infra-db`. Cópias de referência estão em [05-dados](../architecture/05-dados.md).
- Chaves primárias `uuid` (v7, ordenável por tempo), geradas na aplicação. Timestamps em `timestamptz` UTC.

## Alternativas consideradas

| Alternativa | Por que não |
|---|---|
| Uma instância RDS por serviço | Isolamento total, mas triplica o custo do hackathon. A separação lógica com usuários distintos basta. |
| DynamoDB | A listagem por usuário com ordenação e filtros é natural em SQL; o time conhece EF + Postgres. |
| MongoDB (usado na fase 4 para payloads brutos) | Não há documento bruto a guardar neste domínio. |

## Consequências

**Positivas**
- Cada serviço evolui o schema sem coordenar com os outros.
- A instância única simplifica backup e custo.

**Negativas / riscos**
- A instância compartilhada é um único ponto de falha e de "vizinho barulhento". Multi-AZ fica como evolução.
- Joins entre serviços são proibidos. O `notification-service` guarda sua própria projeção de e-mails ([ADR-0012](0012-notificacao-por-email.md)).
