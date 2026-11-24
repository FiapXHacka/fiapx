# ADR-0002: Decomposição em quatro microsserviços

- **Status:** Proposto
- **Data:** 2026-11-23
- **Decisores:** time FIAP X
- **Requisitos relacionados:** RF-01..RF-05, RNF-02 (escalabilidade)

## Contexto

O projeto base é um monólito em Go que recebe o upload, roda o ffmpeg **dentro da requisição HTTP**
e grava tudo em disco local. As cargas de trabalho têm perfis muito diferentes:

- APIs de cadastro/consulta: muitas requisições curtas, I/O-bound.
- Extração de frames: poucas tarefas longas, CPU-bound e com uso pesado de disco temporário.
- Envio de e-mail: raro, depende de um provedor externo que pode falhar.

Escalar tudo junto desperdiça recursos, e uma falha no ffmpeg não pode derrubar a API.

## Decisão

Dividir o sistema em quatro serviços, cada um com seu próprio dado e deploy independente:

| Serviço | Linguagem | Responsabilidade | Dados próprios |
|---|---|---|---|
| `identity-service` | .NET | Cadastro e login (usuário e senha), emissão de JWT, JWKS. Publica `user.registered`. | `identity_db` |
| `video-api` | .NET | Criar vídeo, gerar URL de upload/download, confirmar upload, listar status. Dono do ciclo de vida do vídeo. | `video_db`, cache Redis |
| `video-processor` | Go | Consome `video.uploaded`, baixa do S3, extrai frames com ffmpeg, gera o zip, sobe no S3 e publica o resultado. **Sem banco.** | objetos no S3 |
| `notification-service` | .NET | Mantém o e-mail dos usuários (projeção de `user.registered`) e envia e-mail em falha (e sucesso). | `notification_db` |

Comunicação:
- **Síncrona (HTTP/REST)** apenas entre cliente e serviços, via API Gateway.
- **Assíncrona (RabbitMQ)** entre serviços. Nenhum serviço chama outro por HTTP — ver [ADR-0005](0005-processamento-assincrono-rabbitmq.md).

## Alternativas consideradas

| Alternativa | Por que não |
|---|---|
| Monólito modular + worker | Atenderia ao requisito funcional, mas o desafio pede microsserviços explicitamente. |
| Notificação dentro da `video-api` | Menos um serviço, porém acopla a API à disponibilidade do SMTP e mistura responsabilidades. |
| Autenticação com Amazon Cognito | Menos código, mas tira do escopo um ponto avaliado (segurança) e não roda localmente sem emulação. Ver [ADR-0011](0011-autenticacao-jwt-rs256.md). |
| Worker grava o status direto no `video_db` | Quebra o banco por serviço ([ADR-0009](0009-postgresql-banco-por-servico.md)); o status passa a ter dois donos. |

## Consequências

**Positivas**
- O worker escala de forma independente, pelo tamanho da fila ([ADR-0014](0014-escalabilidade-hpa-keda.md)).
- Falhas ficam isoladas: SMTP fora do ar não impede o processamento, e um crash do ffmpeg não derruba a API.
- O worker sem estado fica simples de testar e escalar.

**Negativas / riscos**
- Consistência eventual: o status na listagem pode atrasar alguns segundos em relação ao processamento.
- Mais pipelines, imagens e manifests para manter; isso é mitigado com repositórios padronizados e o mesmo esqueleto de pipeline ([ADR-0004](0004-repositorios-por-responsabilidade.md), [ADR-0017](0017-ci-cd-github-actions.md)).
