# ADR-0005: Processamento assíncrono com RabbitMQ

- **Status:** Aceito
- **Data:** 2026-11-23
- **Decisores:** time FIAP X
- **Requisitos relacionados:** RF-01 (vários vídeos ao mesmo tempo), RF-02 (não perder requisição em picos), RNF-02

## Contexto

No projeto base, o `POST /upload` só responde depois que o ffmpeg termina. Com isso:
- a conexão HTTP fica presa por minutos, o que gera timeouts no gateway e no cliente;
- picos de upload viram picos de CPU no mesmo processo, que recusa ou derruba requisições;
- se o processo cair durante o processamento, o trabalho se perde sem deixar registro.

## Decisão

1. A API **apenas registra** o pedido e responde `202 Accepted`. O processamento vira uma mensagem `video.uploaded` num broker durável.
2. O broker é o **RabbitMQ** (o mesmo da fase 4), com:
   - exchange `fiapx.events` do tipo **topic** e routing keys `video.*` e `user.*`;
   - **quorum queues** (replicadas e duráveis) para todos os consumidores;
   - `x-delivery-limit` na fila do worker e **dead-letter exchange** `fiapx.dlx` com filas `*.dlq`;
   - mensagens persistentes (`delivery_mode=2`), *publisher confirms* e **ack manual só após concluir o trabalho**.
3. O worker consome com **prefetch = 1 por slot de processamento**, para não reter mensagens que não vai processar logo.
4. A topologia completa está em [04-mensageria](../architecture/04-mensageria.md).

O pico deixa de ser um problema de disponibilidade e vira só **latência**: a fila acumula, o KEDA sobe mais
workers ([ADR-0014](0014-escalabilidade-hpa-keda.md)) e nada se perde.

## Alternativas consideradas

| Alternativa | Por que não |
|---|---|
| Amazon SQS | Gerenciado e ótimo para isso, mas não roda localmente sem LocalStack, e o time já opera RabbitMQ. |
| Apache Kafka | Log distribuído é excessivo para uma fila de trabalho; o consumo por partição complica o paralelismo por mensagem. |
| Fila em tabela do Postgres (`SKIP LOCKED`) | Simples, mas acopla o worker ao banco da API e não demonstra mensageria. |
| Goroutines/threads em memória | Perde trabalho em restart; não escala horizontalmente. |

## Consequências

**Positivas**
- RF-02 atendido por construção: toda requisição aceita está persistida no Postgres (outbox) **antes** do `202`.
- O worker escala de 0 a N pelo tamanho da fila.

**Negativas / riscos**
- Processamentos longos estouram o `consumer_timeout` (30 min por padrão), e o RabbitMQ fecha o canal.
  **Mitigação:** limitar a duração do vídeo ([ADR-0018](0018-regras-de-processamento-de-video.md)) e
  definir `x-consumer-timeout` na fila do worker acima do tempo máximo esperado.
- RabbitMQ dentro do cluster é estado a operar (PVC, backup). Amazon MQ for RabbitMQ fica registrado como evolução.
- Entrega *at-least-once*: os consumidores precisam ser idempotentes ([ADR-0007](0007-entrega-confiavel-outbox-inbox.md)).
