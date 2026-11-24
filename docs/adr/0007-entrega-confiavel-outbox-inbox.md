# ADR-0007: Entrega confiável — outbox, inbox, publisher confirms e idempotência

- **Status:** Proposto
- **Data:** 2026-11-23
- **Decisores:** time FIAP X
- **Requisitos relacionados:** RF-02 (não perder requisição), RF-04 (status correto)

## Contexto

"Não perder nenhuma requisição" falha nos pontos entre sistemas:
1. A API grava no banco e o broker cai antes do `publish`: o vídeo fica parado em `UPLOADED` para sempre.
2. A API publica e o banco faz rollback: o worker processa um vídeo que não existe.
3. O worker processa e cai antes do `ack`: a mensagem é reentregue e o vídeo é processado duas vezes.
4. O worker cai em loop (OOM, vídeo malicioso): mensagem venenosa.

## Decisão

| Ponto | Mecanismo |
|---|---|
| Serviços .NET publicando | **Transactional outbox:** o evento é gravado em `outbox_messages` na **mesma transação** da mudança de estado. Um `BackgroundService` publica com *publisher confirms* e marca `published_at`. |
| Serviços .NET consumindo | **Inbox:** `inbox_messages(message_id, consumer)` com PK composta, gravada na mesma transação do efeito. Duplicata vira no-op + ack. |
| Worker Go (sem banco) publicando | Publica o evento de resultado com *publisher confirms* e **só depois** dá ack na mensagem de entrada. Uma queda entre os dois passos gera reprocessamento, nunca perda. |
| Worker Go idempotente | O resultado tem chave determinística `results/{userId}/{videoId}/frames.zip`. Se o objeto já existir com metadado `x-amz-meta-frame-count`, o worker só republica `video.processed`. |
| Status monotônico | A `video-api` só aplica transições permitidas pela máquina de estados (ver [05-dados](../architecture/05-dados.md)). Evento fora de ordem ou repetido é ignorado. Há também controle otimista por coluna `version`. |
| Falha no handler | **Retry em processo** com backoff exponencial e jitter (.NET: 3 tentativas a partir de 200 ms; worker: 1 s, 4 s, 16 s). Esgotou → `basic.reject(requeue=false)` → DLX → `*.dlq`. **Nunca `basic.nack(requeue=true)` para falha:** no RabbitMQ 4 o `nack` não incrementa o `delivery-count`, então a mensagem entraria em loop e o `x-delivery-limit` nunca dispararia. |
| Queda do processo no meio da mensagem | A conexão cai, o broker reentrega e **incrementa** o `delivery-count`; o `x-delivery-limit` (3 no worker, 5 nos .NET) manda para a DLQ (ex.: vídeo que sempre causa OOM). |
| Shutdown / cancelamento | `basic.nack(requeue=true)`: não é falha, não conta tentativa. |
| Tipo desconhecido / envelope sem `id` | `ack` + log (*tolerant reader*). Tipo conhecido com `data` inválido → `reject(false)` → DLQ. |
| Serviço sem handler registrado | O consumer não é iniciado; as mensagens esperam na fila durável (nada vai para a DLQ). |
| DLQ do worker | O próprio worker consome `video-processor.video-uploaded.dlq` e publica `video.processing-failed` com `errorCode=MAX_ATTEMPTS_EXCEEDED`. |
| Rede de segurança | Job de reconciliação na `video-api` (a cada 5 min): vídeos em `UPLOADED` ou `PROCESSING` há mais que o limite viram `FAILED` (`PROCESSING_TIMEOUT`) e o evento é publicado. |

## Desempenho

- Consumers .NET: `PrefetchCount=16` e `ConsumerConcurrency=4` (handlers paralelos, um escopo de DI e uma transação por mensagem). A ordem não importa porque a inbox e a máquina de estados são idempotentes.
- Retry em processo curto (< 2 s nos .NET), para não segurar um slot de consumo; falhas longas (dependência fora do ar por minutos) vão para a DLQ e são reprocessadas por *shovel* manual ou pelo reconciliador.
- Evolução registrada: fila de retry com TTL (*delayed retry*) para não ocupar o consumer durante o backoff.

## Alternativas consideradas

| Alternativa | Por que não |
|---|---|
| Publicar direto após o `SaveChanges` | Cenários 1 e 2 acima. |
| Transações distribuídas (2PC) | O RabbitMQ não participa de XA; complexidade alta. |
| Debezium/CDC lendo a outbox | Robusto, mas é mais um componente (Kafka Connect) para operar. |
| `nack(requeue=true)` + `x-delivery-limit` | Não funciona no RabbitMQ 4: `nack` não conta tentativa e gera loop quente (observado nos testes do video-api: 43 reentregas em milissegundos). |
| *Exactly-once* | Não existe ponta a ponta com RabbitMQ; *at-least-once* com consumidor idempotente é o padrão de mercado. |

## Consequências

**Positivas**
- Toda requisição aceita (`202`) termina em `COMPLETED` ou `FAILED`. Nenhum vídeo fica preso sem resposta.
- O cenário "matar o worker no meio do processamento" pode ser mostrado ao vivo no vídeo de apresentação.

**Negativas / riscos**
- Latência extra de até 1 intervalo de polling da outbox (configurar 500 ms–1 s).
- As tabelas de outbox e inbox crescem; é preciso um job de limpeza (retenção de 7 dias).
