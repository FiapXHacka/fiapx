# ADR-0013: AWS EKS + Terraform na nuvem, Docker Compose local

- **Status:** Aceito
- **Data:** 2026-11-23
- **Decisores:** time FIAP X
- **Requisitos relacionados:** RNF-02 (arquitetura escalável), RNF-05 (CI/CD)

## Contexto

O time já provisionou VPC, EKS, RDS e API Gateway com Terraform na fase 4 (`mechanics-infra-k8s`, `mechanics-infra-db`).
O PDF aceita "Docker + Kubernetes ou Docker Compose". O orçamento de créditos AWS é limitado.

## Decisão

**Nuvem (AWS, `us-east-1`)** com Terraform nos repositórios `fiapx-infra-k8s` (rede, cluster, gateway e add-ons) e `fiapx-infra-db` (RDS e S3), state remoto em S3 com lock nativo do S3:

| Recurso | Uso |
|---|---|
| VPC (2 AZs, subnets públicas/privadas, 1 NAT) | Rede |
| EKS (managed node group: `general` para APIs e `processing` com instâncias compute-optimized para o worker) | Execução |
| RDS PostgreSQL 17 (`db.t4g.micro`, single-AZ) | Bancos ([ADR-0009](0009-postgresql-banco-por-servico.md)) |
| S3 + lifecycle | Vídeos e zips ([ADR-0008](0008-armazenamento-s3-presigned-urls.md)) |
| ECR (1 repositório por serviço) | Imagens |
| API Gateway HTTP API + VPC Link + NLB interno | Entrada única, JWT authorizer ([ADR-0011](0011-autenticacao-jwt-rs256.md)) |
| IAM / IRSA (Pod Identity) | Acesso dos pods ao S3, Secrets Manager e SES sem chaves estáticas |
| Secrets Manager | Senhas de banco, chave RSA, SMTP |

No cluster (add-ons via Helm no `fiapx-infra-k8s`; manifests de cada serviço em `k8s/` do próprio repositório, com Kustomize): RabbitMQ (StatefulSet + PVC),
Redis, KEDA, kube-prometheus-stack, OpenTelemetry Collector e os quatro serviços.

**Local:** o `docker-compose.yml` do repositório `fiapx` sobe **tudo** (4 serviços, Postgres, RabbitMQ, Redis, MinIO, Mailpit,
otel-lgtm). É o ambiente de desenvolvimento, dos testes E2E no CI e plano B da demo.

**Custo:** o ambiente AWS é criado para testes integrados e para a gravação, e destruído (`terraform destroy`) fora disso.

## Alternativas consideradas

| Alternativa | Por que não |
|---|---|
| Só Compose | Não demonstra escalabilidade real (HPA/KEDA) nem infraestrutura como código. |
| ECS Fargate | Mais simples, mas o time já domina EKS e o KEDA não está disponível nele. |
| Serverless (Lambda + SQS) | Limite de 15 min e de `/tmp` no Lambda para ffmpeg; rompe com o que foi estudado. |
| Amazon MQ / ElastiCache | Gerenciados, mas com custo fixo por hora; ficam como evolução para produção. |

## Consequências

**Positivas**
- Reaproveita módulos e conhecimento da fase 4. A demo pode mostrar pods escalando de verdade.

**Negativas / riscos**
- EKS + NAT + RDS custam enquanto ligados, por isso o `destroy` deve ser disciplinado.
- RabbitMQ e Redis no cluster são estado a operar (ver riscos nos ADRs 0005 e 0010).
