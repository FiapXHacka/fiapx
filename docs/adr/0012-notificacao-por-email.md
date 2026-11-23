# ADR-0012: Notificação por e-mail em serviço dedicado

- **Status:** Proposto
- **Data:** 2026-11-23
- **Decisores:** time FIAP X
- **Requisitos relacionados:** RF-05 (notificar o usuário em caso de erro)

## Contexto

O usuário precisa ser avisado quando o processamento falha. O provedor de e-mail é externo e pode ficar lento ou fora do ar.
O worker não deve conhecer e-mail nem dados pessoais do usuário.

## Decisão

1. **`notification-service`** consome:
   - `user.registered` → faz upsert em `user_contacts(user_id, email, name)` (projeção local, sem chamar o `identity-service`);
   - `video.processing-failed` → e-mail "Não conseguimos processar seu vídeo" com o motivo (`errorCode` traduzido para texto amigável);
   - `video.processed` → e-mail "Seu zip está pronto" (opcional, ligado por feature flag `Notifications:NotifyOnSuccess`).
2. Envio via **SMTP** (MailKit): **Mailpit** no Compose (caixa de entrada visível na demo) e **Amazon SES** (interface SMTP) na AWS.
3. Idempotência: inbox ([ADR-0007](0007-entrega-confiavel-outbox-inbox.md)) + `UNIQUE(video_id, type)` em `notifications`.
   Um mesmo evento nunca gera dois e-mails.
4. Falha no SMTP: retry com backoff exponencial (3 tentativas). Depois disso, a notificação fica `FAILED` e a mensagem vai para a DLQ.

## Alternativas consideradas

| Alternativa | Por que não |
|---|---|
| E-mail enviado pelo worker | Mistura responsabilidades e espalha dados pessoais. |
| Worker/API consultando o e-mail no `identity-service` via HTTP | Acoplamento síncrono: a notificação falharia se o `identity-service` estivesse fora. |
| E-mail dentro do evento | PII trafegando em todas as mensagens de vídeo e retida nas filas. |
| SNS / webhook / push | O PDF cita e-mail; os outros canais podem ser adicionados no mesmo serviço depois. |

## Consequências

**Positivas**
- Mailpit permite mostrar o e-mail de erro chegando ao vivo no vídeo de apresentação.
- Um novo canal (SMS, Slack) é só mais um adaptador.

**Negativas / riscos**
- Se `user.registered` não tiver chegado (consistência eventual), não há e-mail. A mensagem é reenfileirada até o limite e depois vai para a DLQ.
- O SES começa em *sandbox* (só destinatários verificados), o que basta para a demo; produção exigiria liberação.
