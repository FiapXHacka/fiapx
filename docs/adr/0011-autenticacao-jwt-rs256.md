# ADR-0011: Autenticação por usuário e senha com JWT RS256 + JWKS

- **Status:** Proposto
- **Data:** 2026-11-23
- **Decisores:** time FIAP X
- **Requisitos relacionados:** RF-03 (sistema protegido por usuário e senha), RF-04 (listar apenas os vídeos do usuário)

## Contexto

O projeto base não tem autenticação, usa CORS `*` e serve `/uploads` e `/outputs` estaticamente: qualquer um baixa o vídeo de qualquer um.
Na fase 4, o API Gateway usava um Lambda authorizer com JWT HS256 (segredo compartilhado).

## Decisão

1. **`identity-service`**:
   - `POST /auth/register` (nome, e-mail, senha) e `POST /auth/login` (e-mail, senha), que devolve o access token.
   - Senha com hash **PBKDF2** do `PasswordHasher<T>` do ASP.NET Core Identity (salt por usuário, iterações atuais do framework).
     Política mínima: 8 caracteres. E-mail único, sem diferenciar maiúsculas.
   - JWT **RS256**, expiração de 60 min, claims `sub` (userId), `email`, `name`, `iss`, `aud=fiapx-api`.
   - Chave privada no AWS Secrets Manager (no Compose, gerada no startup), com chave pública exposta em `/.well-known/jwks.json` e `kid` para rotação.
2. **Validação em duas camadas:**
   - **API Gateway HTTP API com JWT authorizer nativo** (issuer + JWKS), sem Lambda. Rotas `/auth/*` e `/.well-known/*` ficam públicas.
   - Cada serviço também valida o token (`AddJwtBearer` com o JWKS) — *defense in depth* e funcionamento igual no Compose, que não tem gateway.
3. **Autorização por dono:** toda consulta da `video-api` filtra por `user_id = sub`. Um vídeo de outro usuário devolve `404`, para não revelar que o id existe.

## Alternativas consideradas

| Alternativa | Por que não |
|---|---|
| Amazon Cognito | Menos código, mas não roda localmente e esconde a parte de segurança que queremos mostrar. Boa evolução. |
| HS256 com segredo compartilhado (fase 4) | Todo serviço que valida também poderia **emitir** tokens. Com RS256, só o `identity-service` assina. |
| Lambda authorizer | Custo e latência extras; o authorizer JWT nativo do HTTP API já faz o necessário. |
| Refresh token | Escopo do hackathon; um token de 60 min basta. Registrado como evolução. |

## Consequências

**Positivas**
- O gateway barra requisições sem token antes que cheguem ao cluster.
- Serviços validam sem chamar o `identity-service` em tempo de requisição (JWKS em cache).

**Negativas / riscos**
- Não há revogação imediata de token (logout só no cliente). Aceitável dado o TTL curto.
- O JWKS precisa ser acessível pelo API Gateway, então a rota pública `/.well-known/jwks.json` passa pelo próprio gateway.
