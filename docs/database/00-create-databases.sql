-- FIAP X — criação dos bancos e usuários por serviço (ADR-0009)
-- Único script aplicado fora dos serviços: executado pelo usuário master do RDS (fiapx-infra-db) e pelo init do Postgres no docker-compose.
-- As tabelas são criadas pelas migrations de cada serviço (01..03 são cópias geradas, para a entrega).
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
