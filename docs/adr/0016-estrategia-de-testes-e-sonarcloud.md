# ADR-0016: Estratégia de testes e quality gate no SonarCloud

- **Status:** Aceito
- **Data:** 2026-11-23
- **Decisores:** time FIAP X
- **Requisitos relacionados:** RNF-03 (testes que garantam a qualidade), RNF-05 (CI/CD)

## Contexto

O PDF pede "testes que garantam a sua qualidade". O time já usa SonarCloud com cobertura nas fases anteriores.
A organização `fiapxhacka` foi criada no SonarCloud para o hackathon.

## Decisão

### Pirâmide de testes

| Nível | .NET | Go | O que cobre |
|---|---|---|---|
| Unitário | xUnit + Shouldly (ou AwesomeAssertions) + NSubstitute | `testing` + `testify` | Domínio (máquina de estados do vídeo, validações), casos de uso com portas mockadas |
| Integração | `WebApplicationFactory` + **Testcontainers** (Postgres, RabbitMQ, Redis, S3 compatível) | **testcontainers-go** (RabbitMQ, S3 compatível) + ffmpeg real com vídeo de 3 s em `testdata/` | Repositórios, outbox/inbox, publisher/consumer, adaptadores S3 e ffmpeg |
| Contrato | Exemplos JSON de cada evento validados contra o `asyncapi.yaml` nos dois lados | idem | Compatibilidade .NET ↔ Go |
| E2E | Job no CI com `docker compose up` + coleção Postman/Newman ou script | — | Registrar → login → upload → aguardar `COMPLETED` → baixar zip; vídeo inválido → `FAILED` + e-mail no Mailpit |

FluentAssertions v8+ tem licença comercial, por isso não usamos.

### SonarCloud

- Organização **`fiapxhacka`**, **um projeto por repositório de serviço**, com análise via CI (*Automatic Analysis* desligada):

  | Repositório | Project key |
  |---|---|
  | `fiapx-identity-service` | `FiapXHacka_fiapx-identity-service` |
  | `fiapx-video-api` | `FiapXHacka_fiapx-video-api` |
  | `fiapx-notification-service` | `FiapXHacka_fiapx-notification-service` |
  | `fiapx-video-processor` | `FiapXHacka_fiapx-video-processor` |

- .NET: `dotnet-sonarscanner` + coverlet (OpenCover). Go: `sonarqube-scan-action` + `go test -coverprofile`.
- Autenticação **secretless** (OIDC do GitHub Actions via `sonarqube-auth-action`): nenhum token armazenado.
- **Quality gate** (Sonar way, ajustado): cobertura ≥ **80% em código novo**, 0 bugs/vulnerabilidades novas, duplicação < 3%, *security hotspots* revisados.
- O check do quality gate é **obrigatório** na proteção da branch `main`.
- Exclusões de cobertura: `Program.cs`, `Migrations/`, `cmd/` (wiring) e DTOs gerados.

Guia de configuração: [docs/sonarcloud.md](../sonarcloud.md).

## Alternativas consideradas

| Alternativa | Por que não |
|---|---|
| Um projeto Sonar agregado | O scanner .NET e o scanner genérico (Go) não analisam juntos no mesmo projeto. |
| SonarQube self-hosted | Infraestrutura extra sem ganho. |

## Consequências

**Positivas**
- Cada PR mostra a cobertura e os problemas do serviço alterado direto no GitHub.

**Negativas / riscos**
- **O plano gratuito do SonarCloud só analisa projetos públicos.** Os repositórios da `FiapXHacka` são privados.
  É preciso tornar o repositório público ou contratar o plano Team. Ver [docs/sonarcloud.md](../sonarcloud.md).
- Testcontainers deixa o CI mais lento (~1–2 min por serviço); o cache de imagens Docker ajuda.
