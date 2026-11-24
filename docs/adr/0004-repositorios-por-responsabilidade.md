# ADR-0004: Um repositório por responsabilidade (polyrepo)

- **Status:** Aceito
- **Data:** 2026-11-23
- **Decisores:** time FIAP X
- **Requisitos relacionados:** RNF-04 (versionado no GitHub), RNF-05 (CI/CD)

## Contexto

Na fase 4, o Torque-OS separou aplicação, serviços, Lambda e cada pedaço de infraestrutura em repositórios próprios.
O time já conhece esse modelo: pipelines simples, permissões e deploy independentes, e um projeto Sonar por repositório
sem configuração de monorepo.

## Decisão

Repositórios na organização `FiapXHacka`, um por unidade de deploy:

| Repositório | Conteúdo | Pipeline |
|---|---|---|
| `fiapx` | **Hub da plataforma:** arquitetura, ADRs, fluxos, contratos (`asyncapi.yaml`), `docker-compose.yml` que sobe a plataforma inteira, coleção Postman e testes E2E | E2E (compose) |
| `fiapx-identity-service` | .NET: cadastro, login, JWT/JWKS. Script SQL do `identity_db` | CI + Sonar + imagem + deploy |
| `fiapx-video-api` | .NET: ciclo de vida do vídeo, URLs pré-assinadas, listagem. Script SQL do `video_db` | CI + Sonar + imagem + deploy |
| `fiapx-notification-service` | .NET: projeção de usuários e envio de e-mail. Script SQL do `notification_db` | CI + Sonar + imagem + deploy |
| `fiapx-video-processor` | Go: extração de frames e zip | CI + Sonar + imagem + deploy |
| `fiapx-infra-k8s` | Terraform: VPC, EKS, ECR, API Gateway, IAM/IRSA. Add-ons do cluster: RabbitMQ, Redis, KEDA, observabilidade | plan/apply |
| `fiapx-infra-db` | Terraform: RDS PostgreSQL e bucket S3. Script que cria os bancos e usuários por serviço | plan/apply |

Regras:
- Cada serviço é dono do seu Dockerfile, dos seus manifests (`k8s/`) e do seu script de banco.
- **Os contratos de mensagem vivem no `fiapx`** (fonte da verdade). Uma mudança de contrato começa por um PR no `fiapx`,
  seguido de PRs nos produtores e consumidores, todos ligados à mesma issue.
- **Sem biblioteca compartilhada** entre os serviços .NET. A infraestrutura de mensageria (outbox, inbox, publisher)
  é pequena e fica em cada serviço. Duplicação consciente em troca de deploys realmente independentes.
- Todos os README seguem o mesmo esqueleto e apontam para o `fiapx` (seção *Platform Overview*, como no Torque-OS).

## Alternativas consideradas

| Alternativa | Por que não |
|---|---|
| Monorepo | Contrato e consumidores mudariam num único PR, mas exige filtros de path no CI e configuração de monorepo no Sonar; o time prefere o modelo já conhecido. |
| Pacote NuGet compartilhado (GitHub Packages) | Versionar e publicar pacote custa mais que duplicar ~300 linhas. Pode ser extraído depois se a duplicação incomodar. |

## Consequências

**Positivas**
- Um projeto SonarCloud por repositório, importado direto, sem configuração de monorepo.
- Cada integrante pode ser dono de um repositório, e o GitHub Project da organização agrega as issues de todos.

**Negativas / riscos**
- Mudança de contrato exige PRs coordenados: a issue no Project lista todos os PRs.
- Configuração repetida (branch protection, secrets, templates de PR) em 7 repositórios.
- A divergência entre cópias da infraestrutura de mensageria é mitigada pelos testes de contrato ([ADR-0016](0016-estrategia-de-testes-e-sonarcloud.md)).
