# ADR-0006: Contratos de mensagem em CloudEvents + AsyncAPI, sem MassTransit

- **Status:** Proposto
- **Data:** 2026-11-23
- **Decisores:** time FIAP X

## Contexto

- Produtores e consumidores estão em .NET **e** Go ([ADR-0003](0003-linguagens-dotnet-e-go.md)).
- Na fase 4 usamos MassTransit, que envolve as mensagens num envelope próprio e cria exchanges pelo nome do tipo .NET.
  Um consumidor em Go teria que imitar esse formato.
- O MassTransit v9 passou a exigir licença comercial, e o v8 (open source) só recebe suporte até o fim de 2026.

## Decisão

1. **Formato:** [CloudEvents 1.0](https://cloudevents.io) em *structured mode* JSON (`content-type: application/cloudevents+json`):

   ```json
   {
     "specversion": "1.0",
     "id": "0b8f6c1e-…",              // MessageId: chave de idempotência
     "source": "fiapx/video-api",
     "type": "video.uploaded",        // também é a routing key
     "time": "2026-11-23T18:00:00Z",
     "subject": "<videoId>",
     "dataschema": "fiapx/video.uploaded/v1",
     "traceparent": "00-…",           // extensão de distributed tracing (W3C)
     "data": { … }
   }
   ```

2. **Catálogo de contratos** documentado em [`docs/contracts/asyncapi.yaml`](../contracts/asyncapi.yaml) (AsyncAPI 3.0),
   que é a fonte da verdade. As classes C# e structs Go são escritas a partir dele, e os testes de contrato
   ([ADR-0016](0016-estrategia-de-testes-e-sonarcloud.md)) validam exemplos contra o schema.
3. **Versionamento:** só mudanças aditivas dentro de uma versão. Uma mudança incompatível cria um `dataschema` `/v2` e
   um período em que as duas versões são publicadas.
4. **Sem MassTransit.** Uma camada fina própria em cada serviço .NET (pasta `Infrastructure/Messaging`) sobre `RabbitMQ.Client` (publisher com confirms,
   consumer com ack manual, outbox e inbox), e `github.com/rabbitmq/amqp091-go` no Go.

## Alternativas consideradas

| Alternativa | Por que não |
|---|---|
| MassTransit v8 com raw JSON | Possível (o time conhece), mas o suporte termina no fim de 2026 e exige desligar a topologia automática; sobra pouca vantagem. |
| MassTransit v9 | Licença comercial. |
| Wolverine / Rebus | Mais uma biblioteca para aprender durante o hackathon. |
| Protobuf / Avro | Mais eficiente, mas exige schema registry e dificulta inspecionar as mensagens no painel do RabbitMQ durante a demo. |
| JSON "livre" sem envelope | Sem id para idempotência, sem tipo e sem trace padronizados. |

## Consequências

**Positivas**
- Contrato neutro de linguagem, legível no RabbitMQ Management e padronizado (CNCF).
- O `traceparent` liga o trace do upload ao trace do processamento, já que o OpenTelemetry tem propagador W3C ([ADR-0015](0015-observabilidade-opentelemetry.md)).

**Negativas / riscos**
- Retry, outbox e inbox são escritos à mão no .NET (~300 linhas por serviço, sem pacote compartilhado — ver [ADR-0004](0004-repositorios-por-responsabilidade.md)) e precisam de testes próprios.
- Sem sagas prontas, mas o fluxo é linear e não precisa delas.
