# ADR-0010: Redis para cache de status e rate limiting

- **Status:** Proposto
- **Data:** 2026-11-23
- **Decisores:** time FIAP X
- **Requisitos relacionados:** RF-04 (listar status), RNF-02

## Contexto

A tela de status tende a fazer *polling* (`GET /videos` a cada poucos segundos) enquanto há vídeos em processamento.
Com muitos usuários, isso vira a maior parte das leituras no `video_db`. Além disso, login e criação de vídeo
são alvos naturais de abuso.

## Decisão

**Redis 7** (container no cluster e no Compose) com dois usos:

1. **Cache-aside da listagem:** chave `videos:user:{userId}:page:{n}`, TTL 30 s.
   **Invalidação** sempre que a `video-api` muda o status de um vídeo daquele usuário, depois do commit
   (delete da chave por padrão `videos:user:{userId}:*` via conjunto de índice).
2. **Rate limiting** (janela fixa) em `POST /auth/login` (5/min por IP+e-mail) e `POST /videos` (30/min por usuário).

O Redis é **descartável**: se estiver fora do ar, a API lê direto do Postgres e o rate limit falha aberto
(com log e métrica). Nenhum dado de negócio vive só no Redis.

## Alternativas consideradas

| Alternativa | Por que não |
|---|---|
| Sem cache | Funciona em pouca carga; o requisito do PDF sugere explicitamente Redis. |
| ElastiCache | Gerenciado, mas tem custo fixo; o Redis no cluster atende ao hackathon. |
| Push (SSE/WebSocket) em vez de polling | Melhor UX, mas fora do escopo mínimo; fica como evolução. |
| Cache em memória por pod | Inconsistente entre réplicas. |

## Consequências

**Positivas**
- O polling deixa de pesar no Postgres. A métrica de *hit ratio* pode ser mostrada no Grafana durante a demo.

**Negativas / riscos**
- Janela curta de dado defasado se a invalidação falhar; o TTL curto limita esse efeito.
