-- video_db — dono: video-api (fonte oficial: fiapx-video-api/db/schema.sql)
\connect video_db

CREATE TABLE videos (
    id                     uuid        PRIMARY KEY,
    user_id                uuid        NOT NULL,          -- sem FK: usuário pertence ao identity-service
    original_file_name     text        NOT NULL,
    content_type           text        NOT NULL,
    size_bytes             bigint      NOT NULL CHECK (size_bytes > 0),
    storage_key            text        NOT NULL,
    status                 text        NOT NULL DEFAULT 'PENDING_UPLOAD'
        CHECK (status IN ('PENDING_UPLOAD','UPLOADED','PROCESSING','COMPLETED','FAILED','EXPIRED')),
    frame_count            int,
    result_key             text,
    result_size_bytes      bigint,
    error_code             text,
    error_message          text,
    created_at             timestamptz NOT NULL DEFAULT now(),
    uploaded_at            timestamptz,
    processing_started_at  timestamptz,
    finished_at            timestamptz,
    updated_at             timestamptz NOT NULL DEFAULT now(),
    version                int         NOT NULL DEFAULT 0,   -- concorrência otimista (EF ConcurrencyToken)
    CONSTRAINT videos_completed_has_result CHECK (status <> 'COMPLETED' OR result_key IS NOT NULL),
    CONSTRAINT videos_failed_has_error     CHECK (status <> 'FAILED'    OR error_code IS NOT NULL)
);

-- Listagem do usuário (RF-04)
CREATE INDEX ix_videos_user_created ON videos (user_id, created_at DESC);
-- Reconciliador (ADR-0007)
CREATE INDEX ix_videos_open_status ON videos (status, updated_at)
    WHERE status IN ('PENDING_UPLOAD','UPLOADED','PROCESSING');

CREATE TABLE outbox_messages (
    id            uuid        PRIMARY KEY,
    type          text        NOT NULL,
    payload       jsonb       NOT NULL,
    occurred_at   timestamptz NOT NULL DEFAULT now(),
    published_at  timestamptz,
    attempts      int         NOT NULL DEFAULT 0
);
CREATE INDEX ix_outbox_pending ON outbox_messages (occurred_at) WHERE published_at IS NULL;

CREATE TABLE inbox_messages (
    message_id    uuid        NOT NULL,                  -- CloudEvent.id
    consumer      text        NOT NULL,                  -- nome do handler
    processed_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (message_id, consumer)
);
