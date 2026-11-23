-- identity_db — dono: identity-service (fonte oficial: fiapx-identity-service/db/schema.sql)
\connect identity_db

CREATE TABLE users (
    id             uuid        PRIMARY KEY,               -- uuid v7 gerado na aplicação
    email          text        NOT NULL,
    name           text        NOT NULL,
    password_hash  text        NOT NULL,                  -- PasswordHasher<T> (PBKDF2)
    created_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT users_email_format CHECK (position('@' in email) > 1)
);
CREATE UNIQUE INDEX ux_users_email_lower ON users (lower(email));

CREATE TABLE outbox_messages (
    id            uuid        PRIMARY KEY,               -- = CloudEvent.id
    type          text        NOT NULL,                  -- routing key, ex.: user.registered
    payload       jsonb       NOT NULL,                  -- CloudEvent completo
    occurred_at   timestamptz NOT NULL DEFAULT now(),
    published_at  timestamptz,
    attempts      int         NOT NULL DEFAULT 0
);
CREATE INDEX ix_outbox_pending ON outbox_messages (occurred_at) WHERE published_at IS NULL;
