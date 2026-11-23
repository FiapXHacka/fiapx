# Integração com o SonarCloud

Organização: <https://sonarcloud.io/organizations/fiapxhacka> · Decisão: [ADR-0016](adr/0016-estrategia-de-testes-e-sonarcloud.md)

## ⚠️ Pré-requisito: plano × visibilidade

A organização `fiapxhacka` está no **plano gratuito, que só analisa projetos públicos**. Os repositórios da
`FiapXHacka` são **privados**. Antes de importar, o time precisa escolher uma opção:

1. **Tornar públicos os repositórios dos serviços** (recomendado: os avaliadores vão precisar do link de qualquer forma).
2. Contratar o plano Team do SonarCloud.

## Passo a passo (uma vez por repositório de serviço)

1. Em <https://sonarcloud.io/projects/create>, escolher a organização **FiapXHacka** e selecionar o repositório
   (`fiapx-identity-service`, `fiapx-video-api`, `fiapx-notification-service`, `fiapx-video-processor`).
   A *project key* gerada será `FiapXHacka_<repositório>`.
2. **Administration → Analysis Method → desligar *Automatic Analysis*** (a análise roda no GitHub Actions).
3. **My Account → Security → Generate Token**, criar um token e salvá-lo como secret da organização no GitHub:
   ```bash
   gh secret set SONAR_TOKEN --org FiapXHacka --visibility all
   ```
4. **Quality Gates** → criar `FiapX` (cobertura ≥ 80% em código novo, duplicação < 3%, 0 bugs/vulnerabilidades novas,
   hotspots revisados) e defini-lo como padrão da organização.
5. **New Code** → "Previous version" (o padrão da organização já está assim).
6. No GitHub, em cada repositório: **Settings → Branches → main** → exigir o check `SonarCloud Code Analysis`.

## Workflow — serviços .NET (`.github/workflows/ci.yml`)

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read
  pull-requests: read

jobs:
  build-test-analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0            # o Sonar precisa do histórico para blame e new code

      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: 10.0.x

      - uses: actions/setup-java@v4  # o scanner .NET roda em Java 17+
        with:
          distribution: temurin
          java-version: 21

      - name: Install SonarScanner for .NET
        run: dotnet tool install --global dotnet-sonarscanner

      - name: Sonar begin
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
        run: >
          dotnet sonarscanner begin
          /k:"FiapXHacka_${{ github.event.repository.name }}"
          /o:"fiapxhacka"
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
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
        run: dotnet sonarscanner end /d:sonar.token="${SONAR_TOKEN}"
```

## Workflow — `fiapx-video-processor` (Go)

`sonar-project.properties` na raiz do repositório:

```properties
sonar.projectKey=FiapXHacka_fiapx-video-processor
sonar.organization=fiapxhacka
sonar.sources=.
sonar.exclusions=**/*_test.go,**/testdata/**,**/vendor/**
sonar.tests=.
sonar.test.inclusions=**/*_test.go
sonar.test.exclusions=**/vendor/**
sonar.go.coverage.reportPaths=coverage.out
sonar.coverage.exclusions=cmd/**
```

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read
  pull-requests: read

jobs:
  build-test-analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: actions/setup-go@v5
        with:
          go-version-file: go.mod
      - name: Install ffmpeg (testes de integração do adaptador)
        run: sudo apt-get update && sudo apt-get install -y ffmpeg
      - run: go vet ./...
      - uses: golangci/golangci-lint-action@v6
      - run: go test ./... -race -covermode=atomic -coverprofile=coverage.out
      - uses: SonarSource/sonarqube-scan-action@v5
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
          SONAR_HOST_URL: https://sonarcloud.io
```

## Verificação

- O PR recebe o comentário do SonarCloud com o quality gate.
- O dashboard da organização mostra os 4 projetos com análise da `main`.
- Badges no README de cada repositório:
  `[![Quality Gate](https://sonarcloud.io/api/project_badges/measure?project=FiapXHacka_<repo>&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=FiapXHacka_<repo>)`
