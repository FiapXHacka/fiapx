# ADR-0001: Registrar decisões de arquitetura com ADRs

- **Status:** Aceito
- **Data:** 2026-11-23
- **Decisores:** time FIAP X

## Contexto

O hackathon exige "documentação da arquitetura proposta" e um vídeo explicando a arquitetura escolhida.
O time trabalha em paralelo e precisa saber *por que* cada escolha foi feita, não só *o que* foi feito.
Decisões tomadas só em chamadas ou no chat se perdem.

## Decisão

Toda decisão que afete estrutura, tecnologia, contratos entre serviços, segurança ou operação é registrada
como ADR em `docs/adr/`, no formato do [template](template.md) (inspirado em MADR), em português.

- Um ADR nasce **Proposto** num PR; vira **Aceito** quando o PR é aprovado por pelo menos mais um integrante.
- ADRs aceitos não são editados no conteúdo: mudanças geram um ADR novo que substitui o anterior.
- Diagramas ficam em Mermaid dentro do Markdown, para versionar junto com o código e renderizar no GitHub.

## Alternativas consideradas

| Alternativa | Por que não |
|---|---|
| Wiki do GitHub | Não passa por PR/review e não versiona junto com o código. |
| Documento único de arquitetura | Difícil de revisar por partes; perde o histórico de cada decisão. |
| Diagramas em draw.io/Miro | Binários ou externos, ficam desatualizados; Mermaid é diff-ável. |

## Consequências

**Positivas**
- O vídeo de apresentação pode seguir o índice de ADRs como roteiro.
- Revisão por PR obriga o time a discutir a decisão antes de implementar.

**Negativas / riscos**
- Custo de escrita; mitigado mantendo ADRs curtos (1–2 páginas).
