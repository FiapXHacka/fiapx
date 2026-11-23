-- FIAP X — criação dos bancos e usuários por serviço (ADR-0009)
-- Executado pelo usuário master do RDS (fiapx-infra-db) ou pelo init do Postgres no docker-compose.
-- As senhas vêm de variáveis (psql -v) — nunca versionar senhas reais.
--   psql -v identity_pwd="'...'" -v video_pwd="'...'" -v notification_pwd="'...'" -f 00-create-databases.sql

CREATE ROLE identity_svc     LOGIN PASSWORD :identity_pwd;
CREATE ROLE video_svc        LOGIN PASSWORD :video_pwd;
CREATE ROLE notification_svc LOGIN PASSWORD :notification_pwd;

CREATE DATABASE identity_db     OWNER identity_svc;
CREATE DATABASE video_db        OWNER video_svc;
CREATE DATABASE notification_db OWNER notification_svc;

-- Ninguém além do dono conecta em cada banco
REVOKE CONNECT ON DATABASE identity_db     FROM PUBLIC;
REVOKE CONNECT ON DATABASE video_db        FROM PUBLIC;
REVOKE CONNECT ON DATABASE notification_db FROM PUBLIC;
