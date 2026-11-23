# ADR-0003: .NET 10 nas APIs e Go no processador de vídeo

- **Status:** Aceito
- **Data:** 2026-11-23
- **Decisores:** time FIAP X

## Contexto

- O time usou C#/ASP.NET Core nas fases 1–4 (Clean Architecture, EF Core, testes com cobertura e pipeline com Sonar).
- O projeto base da FIAP X está em Go e a lógica de extração (ffmpeg + zip) já funciona nele.
- O suporte ao **.NET 8 LTS terminou em 10/11/2026**. O LTS vigente é o **.NET 10** (suporte até nov/2028).

## Decisão

- `identity-service`, `video-api` e `notification-service` em **C# / ASP.NET Core 10 (LTS)**, com Clean Architecture
  (Domain, Application, Infrastructure, Api), como nas fases anteriores.
- `video-processor` em **Go** (versão estável suportada, ≥ 1.26), com arquitetura hexagonal:
  o domínio depende de portas (`Storage`, `FrameExtractor`, `EventPublisher`), e S3, ffmpeg e RabbitMQ são adaptadores.
  A lógica do projeto base é reaproveitada, mas reescrita atrás dessas interfaces para ser testável.
- O ffmpeg é chamado como processo externo (`os/exec`) com `context` e timeout. Não usamos bindings em CGo.

## Alternativas consideradas

| Alternativa | Por que não |
|---|---|
| .NET em tudo | Reaproveitaria mais código interno, mas jogaria fora o código Go que já funciona; o time preferiu manter Go no worker. |
| Go em tudo | O time teria que reescrever em Go a autenticação, o EF e os padrões de teste que já domina. |
| Manter .NET 8 | Sem patches de segurança desde nov/2026; o Sonar e os scanners de imagem vão apontar isso. |

## Consequências

**Positivas**
- O time usa a linguagem que domina onde há mais regra de negócio, e Go onde há I/O e processos (imagem pequena, binário estático).
- A poliglotia mostra, na prática, que os contratos entre serviços são independentes de linguagem.

**Negativas / riscos**
- Dois toolchains no CI e duas formas de rodar o scanner do Sonar.
- As bibliotecas de mensageria não podem ser compartilhadas entre linguagens, então o contrato tem que ser explícito.
  Ver [ADR-0006](0006-contratos-de-mensagem-cloudevents.md).
- É preciso instalar o SDK do .NET 10 nas máquinas que ainda estão com o 8.
