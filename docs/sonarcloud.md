# Integração com o SonarQube Cloud

Organização: <https://sonarcloud.io/organizations/fiapxhacka> · Decisão: [ADR-0016](adr/0016-estrategia-de-testes-e-sonarcloud.md)

A análise roda no GitHub Actions em modo **secretless**: o job troca o seu token OIDC do GitHub por um token do
SonarQube Cloud que vale 30 minutos e só serve para o projeto vinculado ao repositório
([`sonarqube-auth-action`](https://github.com/SonarSource/sonarqube-auth-action)). **Não existe `SONAR_TOKEN`** para
criar, rotacionar ou vazar.

## ⚠️ Visibilidade

A organização `fiapxhacka` está no plano gratuito, que cria **projetos públicos**. Os repositórios da `FiapXHacka`
no GitHub são privados, mas depois da primeira análise o código fica visível em sonarcloud.io.
O time precisa aceitar isso (e então tornar os repositórios públicos) ou contratar o plano Team.

## Configuração (já feita na organização)

- *Administration → Organization settings → Analysis → Enable secretless analysis for GitHub Actions*: **ligado**.

## Passo a passo (uma vez por repositório de serviço)

1. Em <https://sonarcloud.io/projects/create>, escolher a organização **FiapXHacka** e importar o repositório
   (`fiapx-identity-service`, `fiapx-video-api`, `fiapx-notification-service`, `fiapx-video-processor`).
   A *project key* gerada é `FiapXHacka_<repositório>`, e a importação já **vincula o repositório ao projeto**, que é um pré-requisito do modo secretless.
2. No projeto: **Administration → Analysis Method → desligar *Automatic Analysis***. Com ela ligada, o SonarQube Cloud rejeita a análise vinda do CI.
3. **Quality Gates** (uma vez na organização): criar `FiapX` (cobertura ≥ 80% em código novo, duplicação < 3%,
   0 bugs/vulnerabilidades novas, hotspots revisados) e defini-lo como padrão.
4. **New Code**: "Previous version" (padrão da organização).
5. No GitHub, em cada repositório: **Settings → Branches → main** → exigir o check `SonarCloud Code Analysis`.

Limitação: PRs vindos de *forks* não recebem `id-token: write`, então não são analisados. Para o time isso não importa, porque todos trabalham em branches do próprio repositório.

## Workflow — serviços .NET (`.github/workflows/ci.yml`)

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:

jobs:
  build-test-analyze:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: read
      id-token: write          # análise secretless (OIDC)
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0       # o Sonar precisa do histórico para blame e new code

      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: 10.0.x

      - uses: actions/setup-java@v4   # o scanner .NET roda em Java 17+
        with:
          distribution: temurin
          java-version: 21

      - name: Install SonarScanner for .NET
        run: dotnet tool install --global dotnet-sonarscanner

      - name: SonarQube Cloud auth (secretless)
        id: sonar
        uses: SonarSource/sonarqube-auth-action@v1   # exporta SONAR_TOKEN (30 min) para os próximos passos

      - name: Sonar begin
        run: >
          dotnet sonarscanner begin
          /k:"${{ steps.sonar.outputs.project-key }}"
          /o:"${{ steps.sonar.outputs.organization }}"
          /d:sonar.host.url="https://sonarcloud.io"
          /d:sonar.token="${SONAR_TOKEN}"
          /d:sonar.cs.opencover.reportsPaths="**/TestResults/**/coverage.opencover.xml"
          /d:sonar.coverage.exclusions="**/Program.cs,**/Migrations/**,**/*Dto.cs"

      - run: dotnet build -c Release --no-incremental

      - name: Test (unit + integration com Testcontainers)
        run: >
          dotnet test -c Release --no-build
          --collect:"XPlat Code Coverage"
          --
          DataCollectionRunConfiguration.DataCollectors.DataCollector.Configuration.Format=opencover

      - name: Sonar end
        run: dotnet sonarscanner end /d:sonar.token="${SONAR_TOKEN}"
```

O token vale 30 minutos. Se build e testes passarem disso, mova o passo de auth para logo antes do `begin` e
mantenha o pipeline curto (o `end` também usa o token).

## Workflow — `fiapx-video-processor` (Go)

Em uso no repositório: [`ci.yml`](https://github.com/FiapXHacka/fiapx-video-processor/blob/main/.github/workflows/ci.yml).
O `sonar-project.properties` define a organização e a key, então o scan não precisa de `args`:

```properties
sonar.projectKey=FiapXHacka_fiapx-video-processor
sonar.organization=fiapxhacka
sonar.sources=.
sonar.exclusions=**/*_test.go,**/testdata/**,**/vendor/**
sonar.tests=.
sonar.test.inclusions=**/*_test.go
sonar.go.coverage.reportPaths=coverage.out
sonar.coverage.exclusions=cmd/**
```

```yaml
    permissions:
      contents: read
      pull-requests: read
      id-token: write
    steps:
      # … checkout (fetch-depth: 0), setup-go, ffmpeg, vet …
      - uses: golangci/golangci-lint-action@v9
        with:
          version: v2.15.0   # versões anteriores foram compiladas com Go < 1.27 e não analisam o código
      - run: go test ./... -race -covermode=atomic -coverprofile=coverage.out
      - uses: SonarSource/sonarqube-auth-action@v1
      - uses: SonarSource/sonarqube-scan-action@v8
```

## Verificação

- O PR recebe a decoração do SonarQube Cloud com o quality gate.
- O dashboard da organização mostra os projetos com análise da `main`.
- Badge no README de cada repositório:
  `[![Quality Gate](https://sonarcloud.io/api/project_badges/measure?project=FiapXHacka_<repo>&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=FiapXHacka_<repo>)`
