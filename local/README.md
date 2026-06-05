[← Voltar para raiz](../README.md)

# 👤 `local/` — Ambiente de desenvolvimento local

> Tudo o que um dev precisa para subir a stack em < 5 minutos.

## Dois modos de subida

Este `local/` funciona em dois contextos, com o mesmo `docker-compose.yml`:

| Contexto | O que sobe | Como |
|---|---|---|
| **Clone público do `ERP-INFRA`** (sem o código dos serviços) | **Camada de dados**: `mysql` + `minio` (+ `phpmyadmin` opt-in) | `docker compose up -d --wait`. Os serviços de app sobem por imagem `ghcr.io/erp-bem-comum/*` quando o CI publicar (hoje são template comentado). |
| **Dentro do mono_repo** (com `core-api/` e `web-app/` como pastas-irmãs) | **Stack completa**: dados + `core-api` + `web` (TanStack/BFF) + `caddy` (HTTPS) | `./up.sh` → `https://app.localhost`. O `docker-compose.override.yml` (git-ignored) builda os serviços das pastas-irmãs e o `docker compose` o mescla automaticamente. |

> **Por que dois arquivos?** O `docker-compose.yml` é **autossuficiente e portável** (não referencia nada fora do repo) — é a promessa do [ADR-0001](../docs/adr/0001-proposito-e-stewardship-do-erp-infra.md). O `docker-compose.override.yml` é **git-ignored** porque depende de `../../core-api` e `../../web-app` existirem no disco — coisa que só acontece no mono_repo do mantenedor.

## O que sobe

| Componente | Status | Comentário |
|---|---|---|
| MySQL 8.4 (databases `core` + `legacy`, 3 usuários/GRANT) | ✅ Ativo (base) | Reflete `docs/topology.md`. `legacy` é casca em dev (dados importados). |
| MinIO + bucket `contracts-documents` | ✅ Ativo (base) | Storage S3-compatível (ADR-0019 do backend). |
| phpMyAdmin | ⚙️ Opt-in (`--profile tools`) | Inspeção visual do banco. |
| `core-api` (Node 24 · Fastify, modo HTTP) | 🔧 Via override (mono_repo) / 🔵 ghcr (público) | BFF do `web` fala com ele pela rede interna. |
| `web` (TanStack Start: front + BFF) | 🔧 Via override (mono_repo) / 🔵 ghcr (público) | Único acessível via browser, atrás do Caddy. |
| `caddy` (borda HTTPS `*.localhost`) | 🔧 Via override (mono_repo) | `app.localhost` → web, `api.localhost` → core-api. |

> Não há `legacy-api` nem `bff-gateway` como serviços — o legado é só dados (database `legacy`) e o BFF é o próprio `web` (TanStack server functions). Ver `docs/topology.md`.

## Pré-requisitos

- **Docker Desktop** (Mac/Windows) ou **Docker Engine** (Linux) — v24+, Compose v2.
- Porta `3306` livre (ou ajuste `MYSQL_PORT` em `.env`). Para a stack completa, `80`/`443` livres.

## Quick start

```bash
cp .env.example .env

# Camada de dados (funciona em qualquer clone):
docker compose up -d --wait
docker compose ps

# (Opcional) phpMyAdmin em http://localhost:8080
docker compose --profile tools up -d

# Stack COMPLETA (só no mono_repo — usa o override):
./up.sh           # → https://app.localhost  (login: admin@bemcomum.dev / DevPassw0rd!2024)
./down.sh         # para (./down.sh -v zera os volumes)
```

Na 1ª subida da stack completa, aceite a CA interna do Caddy (ou rode `caddy trust`).

## Senhas e secrets

As senhas de dev local são **triviais por design** (estão no `.env.example` e no `mysql/init.sql`) — são públicas, não há segredo a proteger num banco efêmero local. **Esta camada não usa SOPS.** Secrets reais (integração Bradesco, OCR) pertencem ao ambiente provisionado e vivem no Secrets Manager — ver [`../docs/secrets.md`](../docs/secrets.md), nunca neste repositório.

## Conectando ao banco

| Como | Comando / valor |
|---|---|
| CLI como `root` (host) | `docker compose exec mysql mysql -u root -proot_local_dev_only` |
| CLI como `core_app` | `docker compose exec mysql mysql -u core_app -pcore_local_dev_only core` |
| String de conexão (container) | `mysql://core_app:core_local_dev_only@mysql:3306/core` |
| Console do MinIO | http://localhost:9001 (`dev-access-key` / `dev-secret-key-min-8-chars`) |

## Validando o isolamento (smoke test)

O isolamento por GRANT é a regra mais importante:

```bash
# core_app NÃO pode tocar em legacy.* — deve dar ERRO
docker compose exec mysql mysql -u core_app -pcore_local_dev_only -e "USE legacy;"
# ERROR 1044 (42000): Access denied for user 'core_app'@'%' to database 'legacy'
```

Se deu ERROR, o isolamento está funcionando. ✅

## Carregando dump do legado

> 🔵 **Quando o dump anonimizado estiver disponível** (responsabilidade do time de infra / migração). Carregue no database `legacy` usando o usuário `legacy_loader`.

```bash
docker compose exec -T mysql mysql -u legacy_loader -plegacy_local_dev_only legacy < ~/dumps/legacy-anon.sql
```

> ⚠️ **Não commite dumps neste repo.** Mesmo anonimizados, são pesados e potencialmente sensíveis.

## Reset completo

```bash
docker compose down       # mantém dados
docker compose down -v    # remove volumes (erp-mysql-data, erp-minio-data)
docker compose up -d
```

## Troubleshooting

| Sintoma | Provável causa | Solução |
|---|---|---|
| `port 3306 already in use` | Outro MySQL no host | `MYSQL_PORT=3307` no `.env`, recriar |
| `Access denied ... to database 'legacy'` como `core_app` | **Isolamento funcionando! ✅** | Não é um problema |
| Navegador reclama do certificado em `app.localhost` | CA interna do Caddy não confiada | `caddy trust` ou aceitar no navegador |
| `core-api`/`web` não sobem num clone público | Imagens ghcr ainda não publicadas | Use o mono_repo (`./up.sh`) ou aguarde o CI |
| Volume enorme | Acúmulo de dados de teste | `docker compose down -v` |
