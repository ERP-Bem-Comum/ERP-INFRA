-- ============================================================================
-- Bootstrap do MySQL para desenvolvimento local — ERP Bem Comum
-- ----------------------------------------------------------------------------
-- Reflete o handbook (infrastructure/01-infra-handoff.md secao 4.2):
--   - 2 databases isolados: legacy, core
--   - 3 usuarios com GRANTs estritos:
--       legacy_app  -> GRANT ALL em legacy.*
--       core_app    -> GRANT ALL em core.*
--       readonly_bi -> SELECT em ambos
--
-- O isolamento por GRANT eh a unica coisa que impede um dev de violar
-- a regra de dominio. Nao negocie.
--
-- Charset/collation: utf8mb4 + utf8mb4_unicode_ci.
-- ============================================================================

-- Databases isolados
CREATE DATABASE IF NOT EXISTS legacy CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS core   CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Usuarios. Senhas em desenvolvimento sao TRIVIAIS, intencionalmente.
-- NUNCA reutilize estas senhas em qualquer ambiente nao-local.
CREATE USER IF NOT EXISTS 'legacy_app'@'%'  IDENTIFIED BY 'legacy_local_dev_only';
CREATE USER IF NOT EXISTS 'core_app'@'%'    IDENTIFIED BY 'core_local_dev_only';
CREATE USER IF NOT EXISTS 'readonly_bi'@'%' IDENTIFIED BY 'bi_local_dev_only';

-- Grants estritos
GRANT ALL PRIVILEGES ON legacy.* TO 'legacy_app'@'%';
GRANT ALL PRIVILEGES ON core.*   TO 'core_app'@'%';
GRANT SELECT          ON legacy.* TO 'readonly_bi'@'%';
GRANT SELECT          ON core.*   TO 'readonly_bi'@'%';

FLUSH PRIVILEGES;

-- Smoke test: cada user enxerga apenas o que deveria
-- (manualmente: docker compose exec mysql mysql -u legacy_app -p)
