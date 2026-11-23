-- notification_db — dono: notification-service (fonte oficial: fiapx-notification-service/db/schema.sql)
\connect notification_db

-- Projeção local de user.registered (ADR-0012)
CREATE TABLE user_contacts (
    user_id     uuid        PRIMARY KEY,
    email       text        NOT NULL,
    name        text        NOT NULL,
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE notifications (
    id          uuid        PRIMARY KEY,
    user_id     uuid        NOT NULL,
    video_id    uuid        NOT NULL,
    type        text        NOT NULL CHECK (type IN ('VIDEO_FAILED','VIDEO_COMPLETED')),
    channel     text        NOT NULL DEFAULT 'EMAIL',
    status      text        NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','SENT','FAILED')),
    attempts    int         NOT NULL DEFAULT 0,
    last_error  text,
    created_at  timestamptz NOT NULL DEFAULT now(),
    sent_at     timestamptz,
    CONSTRAINT ux_notifications_video_type UNIQUE (video_id, type)   -- nunca 2 e-mails do mesmo evento
);
CREATE INDEX ix_notifications_user ON notifications (user_id, created_at DESC);

CREATE TABLE inbox_messages (
    message_id    uuid        NOT NULL,
    consumer      text        NOT NULL,
    processed_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (message_id, consumer)
);
