# ADR-0014: Escalabilidade — HPA nas APIs, KEDA no worker

- **Status:** Proposto
- **Data:** 2026-11-23
- **Decisores:** time FIAP X
- **Requisitos relacionados:** RF-01, RF-02, RNF-02

## Contexto

CPU é um sinal ruim para escalar o worker: quando a CPU sobe, a fila já cresceu. O sinal certo é a **profundidade da fila**.
As APIs, por outro lado, têm carga proporcional a requisições, e para elas CPU funciona bem.

## Decisão

| Componente | Mecanismo | Configuração inicial |
|---|---|---|
| `video-processor` | **KEDA `ScaledObject`** com o scaler `rabbitmq` (modo `QueueLength`) | `queueLength: 2`, `minReplicaCount: 1` (0 fora da demo), `maxReplicaCount: 10`, `cooldownPeriod: 120` |
| `video-api`, `identity-service` | **HPA** por CPU | 2–6 réplicas, alvo de 70% de CPU |
| `notification-service` | Réplica fixa (2) | Volume baixo |
| Nós | Cluster Autoscaler / Karpenter no node group `processing` | 1–4 nós |

Concorrência **dentro** do worker: `WORKER_CONCURRENCY` (padrão 2) goroutines por pod, cada uma com seu canal e prefetch 1.
O ffmpeg roda com `-threads` limitado para que `concurrency × threads ≈ vCPU do pod`.

Recursos do pod do worker: `requests: cpu 1, memory 512Mi, ephemeral-storage 4Gi`; `limits: cpu 2, memory 1Gi, ephemeral-storage 8Gi`.

`PodDisruptionBudget` e `terminationGracePeriodSeconds: 600` no worker: no SIGTERM, ele para de consumir e termina o vídeo atual.
Se não terminar a tempo, não dá ack e a mensagem volta para a fila.

## Alternativas consideradas

| Alternativa | Por que não |
|---|---|
| HPA por CPU no worker | Reage tarde e não escala de/para zero. |
| HPA com métrica externa (Prometheus Adapter) | Funciona, mas é mais peças que o KEDA para o mesmo resultado. |
| Réplicas fixas | Não atende "escalável" e desperdiça recurso fora de pico. |

## Consequências

**Positivas**
- O requisito "vários vídeos ao mesmo tempo" é atendido em duas dimensões: goroutines por pod e pods por fila.
- Demo: enviar 20 vídeos e mostrar os pods subindo (`kubectl get pods -w`) e a fila drenando no Grafana.

**Negativas / riscos**
- Escalar de zero tem *cold start* (pull de imagem + nó novo). Mitigação: `minReplicaCount: 1` e imagem pequena.
