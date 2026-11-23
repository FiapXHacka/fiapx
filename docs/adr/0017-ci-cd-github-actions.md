# ADR-0017: CI/CD com GitHub Actions

- **Status:** Proposto
- **Data:** 2026-11-23
- **Decisores:** time FIAP X
- **Requisitos relacionados:** RNF-04, RNF-05

## Contexto

Sete repositórios ([ADR-0004](0004-repositorios-por-responsabilidade.md)): quatro serviços em duas linguagens, dois de Terraform e o hub `fiapx`. Os pipelines precisam seguir o mesmo esqueleto para não divergir.

## Decisão

### Fluxo de trabalho
- **Trunk-based:** branches curtas `feat/<issue>-descricao`, PR para `main` com 1 aprovação, *squash merge*.
- Mensagens no padrão **Conventional Commits** (`feat(video-api): …`), e o PR referencia a issue (`Closes #12`).
- Proteção da `main`: checks de CI + quality gate do Sonar obrigatórios; sem push direto.

### Pipelines (`.github/workflows/` de cada repositório)

| Repositório | Workflow | Gatilho | Etapas |
|---|---|---|---|
| serviços .NET | `ci.yml` | PR e push na `main` | restore → Sonar begin → build → testes + cobertura → Sonar end → build da imagem → Trivy |
| `fiapx-video-processor` | `ci.yml` | PR e push na `main` | vet + golangci-lint → testes `-race` + cobertura → Sonar → build da imagem → Trivy |
| os 4 serviços | `deploy.yml` | CI verde na `main` | push da imagem no ECR (tag = SHA) → `kubectl apply -k k8s/overlays/aws` |
| `fiapx-infra-k8s`, `fiapx-infra-db` | `terraform.yml` | PR / push na `main` | fmt + validate + tflint → `plan` comentado no PR → `apply` na `main` com *environment* `aws` (aprovação manual) |
| `fiapx` | `e2e.yml` | PR, push na `main` e manual | `docker compose up --wait` (imagens `latest` do ECR/GHCR) → teste ponta a ponta |

- **Credenciais AWS via OIDC** (`aws-actions/configure-aws-credentials` + role IAM), sem *access keys* nos secrets.
- Imagens com tag do SHA do commit, multi-stage, usuário não-root e scan com Trivy (falha em `CRITICAL`).

## Alternativas consideradas

| Alternativa | Por que não |
|---|---|
| Workflows reutilizáveis num repositório central | Bom para evitar cópia, mas o versionamento entre repositórios complica o hackathon; com 4 serviços, copiar o template é aceitável. |
| Argo CD (GitOps) | Melhor para produção, mas é mais um componente no cluster para o hackathon. Fica como evolução. |

## Consequências

**Positivas**
- Cada repositório tem um pipeline curto e independente. O deploy é rastreável até o commit.

**Negativas / riscos**
- YAML parecido em 4 repositórios: mudanças no esqueleto têm que ser replicadas (checklist na issue).
