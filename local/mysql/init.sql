-- ============================================================================
-- Bootstrap do MySQL para desenvolvimento local — ERP Bem Comum
-- ----------------------------------------------------------------------------
-- Reflete o handbook (infrastructure/01-infra-handoff.md secao 4.2) e a
-- topologia em docs/topology.md:
--   - 2 databases isolados: core (runtime) + legacy (dados importados do ERP
--     antigo; CASCA em dev, sem servico que o sirva em runtime)
--   - 3 usuarios com GRANTs estritos:
--       core_app      -> GRANT ALL em core.*     (o core-api conecta como este)
--       legacy_loader -> GRANT ALL em legacy.*   (so o job de importacao usa)
--       readonly_bi   -> SELECT em ambos         (BI / conferencia de migracao)
--
-- O isolamento por GRANT eh a unica coisa que impede um dev/servico de violar
-- a regra de dominio. Nao negocie. O core-api, conectado como core_app, NAO
-- consegue tocar em legacy.* — permissao negada pelo proprio MySQL.
--
-- Charset/collation: utf8mb4 + utf8mb4_unicode_ci (ADR-0014).
-- ============================================================================

-- Databases isolados
CREATE DATABASE IF NOT EXISTS core   CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS legacy CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Usuarios. Senhas em desenvolvimento sao TRIVIAIS, intencionalmente.
-- NUNCA reutilize estas senhas em qualquer ambiente nao-local.
CREATE USER IF NOT EXISTS 'core_app'@'%'      IDENTIFIED BY 'core_local_dev_only';
CREATE USER IF NOT EXISTS 'legacy_loader'@'%' IDENTIFIED BY 'legacy_local_dev_only';
CREATE USER IF NOT EXISTS 'readonly_bi'@'%'   IDENTIFIED BY 'bi_local_dev_only';

-- Grants estritos
GRANT ALL PRIVILEGES ON core.*   TO 'core_app'@'%';
GRANT ALL PRIVILEGES ON legacy.* TO 'legacy_loader'@'%';
GRANT SELECT          ON core.*   TO 'readonly_bi'@'%';
GRANT SELECT          ON legacy.* TO 'readonly_bi'@'%';

FLUSH PRIVILEGES;

-- Smoke test do isolamento (manual):
--   docker compose exec mysql mysql -u core_app -pcore_local_dev_only -e "USE legacy;"
--   -> deve dar ERROR 1044 (Access denied) = isolamento funcionando.
