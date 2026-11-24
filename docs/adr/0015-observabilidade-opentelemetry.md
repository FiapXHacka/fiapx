# ADR-0015: Observabilidade com OpenTelemetry + Prometheus/Grafana

- **Status:** Proposto
- **Data:** 2026-11-23
- **Decisores:** time FIAP X
- **Requisitos relacionados:** stack recomendada no PDF (monitoramento)

## Contexto

Na fase 4 usamos Datadog. O PDF recomenda Prometheus + Grafana ou ELK. Com processamento assíncrono entre .NET e Go,
sem tracing distribuído não dá para responder "onde está o vídeo X?".

## Decisão

1. **Instrumentação com OpenTelemetry** em todos os serviços (SDK .NET e Go): traces, métricas e logs.
   Os serviços enviam OTLP para um **OpenTelemetry Collector**, então o backend é configuração, não código.
2. **Backends:**
   - Local: imagem `grafana/otel-lgtm` (Collector + Prometheus/Mimir + Tempo + Loki + Grafana num container).
   - EKS: `kube-prometheus-stack` + Tempo + Loki via Helm.
3. **Propagação:** `traceparent` no header HTTP e como extensão CloudEvents nas mensagens ([ADR-0006](0006-contratos-de-mensagem-cloudevents.md)).
   O trace cobre upload → fila → worker → evento → notificação.
4. **Logs** estruturados em JSON, com `trace_id`, `video_id` e `user_id` (nunca e-mail ou senha).
5. **Métricas de negócio** (além de RED/USE):
   - `fiapx_videos_created_total`, `fiapx_videos_completed_total`, `fiapx_videos_failed_total{error_code}`
   - `fiapx_video_processing_duration_seconds` (histograma), `fiapx_video_frames_total`
   - Profundidade das filas e DLQ (exporter Prometheus nativo do RabbitMQ)
6. **Dashboards** versionados no `fiapx-infra-k8s` (`observability/dashboards/*.json`) e **alertas**: DLQ > 0, fila > 50 por 5 min, taxa de falha > 10%.

## Alternativas consideradas

| Alternativa | Por que não |
|---|---|
| Datadog (fase 4) | Pago e fora do Compose local. Pode ser ligado como exporter do Collector, sem mudar código. |
| ELK | Pesado para rodar localmente; o foco dele é log, e nós precisamos de trace. |
| Só Prometheus (sem tracing) | Não mostra o caminho assíncrono do vídeo. |

## Consequências

**Positivas**
- O mesmo dashboard funciona no Compose e no EKS. Na demo, o trace ponta a ponta de um vídeo é um bom momento visual.

**Negativas / riscos**
- Mais componentes no cluster; o `otel-lgtm` não é para produção, e por isso o EKS usa a stack Helm.
