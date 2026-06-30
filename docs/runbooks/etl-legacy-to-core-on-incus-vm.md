# Runbook — Validação em VM incus: stack ERP + migração legacy→core (ETL)

> **Status:** 🟡 EM CONSTRUÇÃO (diário de bordo de uma execução real, 2026-06-30).
> **Objetivo:** provisionar uma VM pequena (incus, no host `x99`) que **simula a infra** de `docs/topology.md`,
> subir a stack completa (`core-api` + `web-app` + MySQL `core`+`legacy` + MinIO + Caddy via `local/`),
> **carregar o dump de produção** (db legado) e **migrar legado→`core`** via os scripts de ETL do `core-api`.
> Registra **comando a comando**, com **resultados, erros e correções**, para a Infra reproduzir.
>
> **A parte mais valiosa** é a seção [Troubleshooting](#troubleshooting--o-que-não-deu-certo).

---

## 0. Contexto e alvo

- **Host:** `x99` (homelab na tailnet) — 28 cores, 15 GiB RAM, incus 7.1, `/dev/kvm` ok, pool btrfs `ssd` (384 GiB livres).
- **VM:** `erp-validate` — Ubuntu 24.04 (`images:ubuntu/24.04`), 4 vCPU / 6 GiB / 40 GiB · IP `10.10.10.41`.
- **Stack (de `ERP-INFRA/local/`):** MySQL 8.4 (`core` + `legacy`, 3 usuários por GRANT), MinIO, `core-api` (Fastify, branch `027-fin-document-payment-detail`), `web-app` (TanStack Start, branch `develop`), Caddy.
- **Dump:** `database/prod_dump/dump_prod_2026.sql` (1.3 MB). ⚠️ Cria o database **`abc-erp-financeiro-prod`** (32 tabelas), **não** `legacy`.
- **ETL:** `core-api/scripts/etl/` (`main.ts` = `runEtl`, `orchestrate.ts`, `legacy/{restore,reader,decode,rows}.ts`, `mappers/`).

---

## F0 — Código nos remotos (pré-requisito)

- `core-api`: branch **`027-fin-document-payment-detail`** (feature `paymentDetail` #273, W0–W3 closed-green) → `git push -u origin 027-fin-document-payment-detail`.
- `web-app`: branch **`develop`** (já em `origin/develop`).
- ⚠️ `ERP-INFRA/local/docker-compose.override.yml` é **git-ignored** → não vem em clone; **transferido à parte** (ver F2).

---

## F1 — VM incus + Docker

```bash
# no x99:
incus launch images:ubuntu/24.04 erp-validate --vm -c limits.cpu=4 -c limits.memory=6GiB -d root,size=40GiB
for i in $(seq 1 36); do incus exec erp-validate -- true 2>/dev/null && break; sleep 5; done   # aguarda agent
incus exec erp-validate -- bash -c '
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq && apt-get install -y -qq git curl ca-certificates rsync tar
  curl -fsSL https://get.docker.com | sh && systemctl enable --now docker'
```
**Resultado:** Docker 29.6.1 · Compose v5.2.0 · git 2.43.0. ✅ (Ver [T1](#t1) sobre cloud-init.)

---

## F2 — Montar o mono_repo na VM (transferência sem auth git)

Os repos são privados → em vez de autenticar git na VM, **transferimos um tarball** Mac → x99 → VM.

```bash
# no Mac (raiz do mono_repo) — empacota SEM node_modules/.git (o build Docker reinstala):
tar czf erp-stack.tgz --exclude=node_modules --exclude=.git --exclude=dist \
  --exclude=coverage --exclude=.pnpm-store --exclude=.output --exclude=build \
  core-api web-app ERP-INFRA
cp ../database/prod_dump/dump_prod_2026.sql .

scp erp-stack.tgz dump_prod_2026.sql x99:/tmp/

# no x99 — empurra para a VM e extrai mantendo a topologia mono_repo:
incus exec erp-validate -- mkdir -p /root/mono_repo /root/dump
incus file push /tmp/erp-stack.tgz erp-validate/root/erp-stack.tgz
incus file push /tmp/dump_prod_2026.sql erp-validate/root/dump/dump_prod_2026.sql
incus exec erp-validate -- tar xzf /root/erp-stack.tgz -C /root/mono_repo
```
**Resultado:** `/root/mono_repo/{core-api,web-app,ERP-INFRA}` + override presente. ✅
(Tarball 44 MB. Warnings `LIBARCHIVE.xattr.com.apple.provenance` do tar são metadados do macOS — inofensivos.)

---

## F3 — Subir a stack + carregar legado + ETL

### 3.1 — Subir a stack (`./up.sh`)

```bash
incus exec erp-validate -- bash -c 'cd /root/mono_repo/ERP-INFRA/local && cp -n .env.example .env && ./up.sh'
```
O `up.sh` builda `core-api` (Dockerfile) e `web` (web.Dockerfile, target dev) das pastas-irmãs e sobe a stack.

⚠️ **Falhou na 1ª tentativa** — `core-api` em crash-loop (`dependency failed to start: unhealthy`). Causa e correção em [T2](#t2). Após a correção:

```
SERVICE    STATUS
caddy      Up        (healthy)
core-api   Up        (healthy)
minio      Up        (healthy)
mysql      Up        (healthy)
web        Up        (healthy)
```
✅ Stack completa de pé.

### 3.2 — Carregar o dump de prod (db legado)

O dump **traz seu próprio `CREATE DATABASE \`abc-erp-financeiro-prod\`** + `USE` → carrega-se direto como root (não em `legacy`):

```bash
incus exec erp-validate -- bash -c 'cd /root/mono_repo/ERP-INFRA/local && \
  docker compose exec -T mysql mysql -u root -proot_local_dev_only < /root/dump/dump_prod_2026.sql'

# confere:
docker compose exec -T mysql mysql -u root -proot_local_dev_only -e "SHOW DATABASES"
```
**Resultado:** databases `abc-erp-financeiro-prod` (**32 tabelas** de dados reais) + `core` (novo) + `legacy` (casca). ✅
(Ver [T3](#t3): o nome do db legado é o de prod, não `legacy` — impacta o reader do ETL.)

### 3.3 — Migração legado → `core` (ETL) — ✅ EXECUTADO

O orquestrador é `core-api/scripts/etl/main.ts` → `runEtl({ dumpPath, connectionString, dryRun })`:
1. `withLegacyMysql(dump, fn)` sobe um **MySQL efêmero PRÓPRIO** (`compose.etl.yaml`, porta 3307) e restaura o dump **lá** — não usa o `abc-erp-financeiro-prod` já carregado.
2. `readLegacyData()` lê o legado → `orchestrate(deps)(data)` (lógica pura, mappers).
3. Escreve no `core` destino via `buildAuthEtlPort` + `buildPartnersEtlPort` (`#src/modules/{auth,partners}/public-api/etl.ts`).
4. Quarentena dupla (resumo PII-free versionável + detalhe PII gitignored).

**Constraints descobertas (decisões pendentes p/ a Infra):**
- ⚠️ É **gated** por `PARTNERS_ETL_INTEGRATION=1` e o comentário avisa: *"NUNCA roda contra o dump de producao: o dump default e o sintetico de testes"*. Num **ambiente isolado** (esta VM efêmera) usar a cópia do dump de prod é o objetivo — mas a Infra deve ratificar essa exceção e jamais apontar para prod.
- Precisa **Node 24 + Docker** no host que roda o ETL (Docker p/ o MySQL efêmero). A VM tem Docker mas **não** Node fora dos containers → **instalar Node 24 + pnpm na VM** (ou rodar num container Node com o socket do Docker montado).
- O ETL atual cobre **auth + partners** (usuários/parceiros). Cobertura de outros agregados é incremento.

**Executado** (ambiente isolado; uso do dump de prod ratificado pelo dono):
```bash
# Node 24 + pnpm na VM:
curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && apt-get install -y nodejs && corepack enable
cd /root/mono_repo/core-api && pnpm install            # ~27s

# ⚠️ AJUSTE OBRIGATÓRIO no dump (ver T4): remover CREATE DATABASE/USE do dump de prod,
#    senão restaura em `abc-erp-financeiro-prod` e o reader não acha `legacy.*` (T3).
cd /root/dump && sed -E '/^CREATE DATABASE .*abc-erp-financeiro-prod/d; /^USE .abc-erp-financeiro-prod./d' \
  dump_prod_2026.sql > dump_legacy.sql

# rodar o ETL (destino = core do compose principal, :3306):
cd /root/mono_repo/core-api && \
  ETL_CORE_CONNECTION_STRING=mysql://core_app:core_local_dev_only@127.0.0.1:3306/core \
  PARTNERS_ETL_INTEGRATION=1 \
  node --experimental-strip-types --no-warnings scripts/etl/main.ts --dump=/root/dump/dump_legacy.sql
```
> ⚙️ O `--dump=<path>` é parseado por `parseArgs`; o destino vem de `ETL_CORE_CONNECTION_STRING`. O ETL sobe um
> MySQL **efêmero próprio** (`compose.etl.yaml`, :3307) via Docker do host da VM e restaura o `dump_legacy.sql` lá.

**Resultado (reconciliação):**
```
suppliers:     read=100  migrated=17  quarantined=83
financiers:    read=0    migrated=0   quarantined=0
collaborators: read=91   migrated=86  quarantined=5
users:         read=14   migrated=12  quarantined=2
```
Confirmado no `core`: `par_collaborators=86`, `par_suppliers=17`, `auth_user=13` (12 migrados + admin seed). ✅ **A migração legado→core funciona.**

**Achados de DADOS** (qualidade/mapeamento — não são falhas do provisionamento, mas precisam de tratamento antes de um go-live real):
- **Quarentena alta de suppliers (83/100):** maioria dos fornecedores do legado reprovou a validação do domínio (provável documento/CNPJ inválido). Investigar o detalhe de quarentena (resumo PII-free versionável; detalhe PII gitignored).
- **`food_category` Data too long ([T5](#t5)):** 5 collaborators quarentenados — a coluna `par_collaborators.food_category` é mais curta que o valor do legado (ex.: `PREFIRO_NAO_RESPONDER`). Bug de schema/mapeamento no core, a corrigir (fora do escopo do `paymentDetail`).
- **`financiers` read=0:** a tabela `financiers` do dump está vazia.

---

## F4 — Validação

- ✅ **Schema da feature 027 no MySQL real:** `DESCRIBE core.fin_documents` →
  `payment_detail varchar(255) YES NULL`. A migration `0026` foi aplicada pelo `job:migrate`.
- ✅ **Stack acessível:** `core-api` responde `/health` 200; `web` healthy atrás do Caddy.
- ✅ **ETL legado→core executado** (F3.3): 86 collaborators, 17 suppliers, 12 users migrados para o `core`; achados de dados registrados.
- ⏳ **E2E HTTP do `paymentDetail`** (login → criar documento com `paymentDetail` → GET detalhe) — pendente.
- ⏳ **Acesso externo do front** (`https://app.localhost`) — expor via tailscale/proxy na VM (a fazer).

---

## Troubleshooting — o que NÃO deu certo {#troubleshooting--o-que-não-deu-certo}

### T1 — `cloud-init status --wait` → `Command not found` {#t1}
**Causa:** a imagem `images:ubuntu/24.04` (linuxcontainers) é minimal, sem cloud-init.
**Correção:** detectar o agent via loop `incus exec -- true`; ou usar a imagem `ubuntu:24.04` (Canonical) que traz cloud-init.

### T2 — `core-api` em crash-loop: `auth-seed: ... user-repo-unavailable` {#t2}
**Sintoma:** `[user-repo:findByEmail] Failed query: select ... from auth_user` + `Fatal ao iniciar: auth-seed`. `docker compose ps` → `core-api Restarting`.
**Causa-raiz:** o database `core` estava **vazio** (`SHOW TABLES` → 0). O override (`docker-compose.override.yml`) roda `node src/server.ts` **sem um passo de migration**, e o `auth-seed` do boot consulta `auth_user` antes de a tabela existir.
**Correção:** aplicar as migrations ANTES do core-api via o job dedicado, depois reiniciar:
```bash
docker compose run --rm --no-deps \
  -e MIGRATE_DATABASE_URL=mysql://core_app:core_local_dev_only@mysql:3306/core \
  --entrypoint node core-api --experimental-strip-types --no-warnings src/jobs/migrate/run.ts
docker compose up -d --wait core-api
```
**Saída esperada:** `[migrate] ok: auth, contracts, financial, notifications, partners, programs` → `core-api Up (healthy)`.
> 📌 **Recomendação p/ a Infra:** o `local/docker-compose.override.yml` deveria ter um serviço one-shot `migrate`
> (depends_on mysql healthy; o core-api depende dele) para reproduzir o staging/prod, onde o `job migrate` roda
> antes dos serviços (Slice B do mysql-driver). Hoje a stack local depende do migrate-no-boot, que não ocorreu.

### T3 — Dump não carrega em `legacy` {#t3}
**Causa:** o `dump_prod_2026.sql` traz `CREATE DATABASE \`abc-erp-financeiro-prod\`` + `USE` → ignora o `legacy` alvo e cria seu próprio database.
**Correção/decisão:** carregar como root sem forçar database (cria `abc-erp-financeiro-prod`); o **reader do ETL deve apontar para esse nome** (ou normalizar o dump). A topologia chama de `legacy` logicamente; o **nome físico** é o de prod.

### T4 — ETL falha: `Table 'legacy.financiers' doesn't exist` {#t4}
**Sintoma:** `node scripts/etl/main.ts --dump=dump_prod_2026.sql` → `Error: Table 'legacy.financiers' doesn't exist`.
**Causa-raiz:** `restore.ts` aplica o dump com `mysql -uroot legacy` (database alvo `legacy`), mas o `dump_prod_2026.sql` contém `CREATE DATABASE \`abc-erp-financeiro-prod\`` + `USE \`abc-erp-financeiro-prod\`` — o `USE` **sobrescreve** o database alvo, então as tabelas caem em `abc-erp-financeiro-prod` e o reader (que lê `legacy.*`) não as encontra. O ETL foi desenhado para um dump **sem** cabeçalho de database (o sintético restaura direto em `legacy`).
**Correção:** gerar um dump sem essas linhas e passar esse ao ETL:
```bash
sed -E '/^CREATE DATABASE .*abc-erp-financeiro-prod/d; /^USE .abc-erp-financeiro-prod./d' \
  dump_prod_2026.sql > dump_legacy.sql
```
> 📌 **Recomendação p/ a Infra:** padronizar o dump de migração **sem** `CREATE DATABASE`/`USE` (ex.: `mysqldump --no-create-db` e restaurar com `-D legacy`), ou ensinar o `restore.ts`/reader a usar o nome real do schema. Documentar qual é o contrato.

### T5 — `Data too long for column 'food_category'` (collaborators) {#t5}
**Sintoma:** durante o ETL, vários `[partners-etl-store:collaborators.provision] Failed query: insert into par_collaborators ... cause: Data too long for column 'food_category' (errno=1406)`. Os registros vão para **quarentena** (não derrubam o ETL).
**Causa-raiz:** a coluna `par_collaborators.food_category` (core novo) é mais curta que o valor vindo do legado (ex.: `PREFIRO_NAO_RESPONDER`, 21 chars). É divergência de **schema/mapeamento** no destino, não do dump nem do provisionamento.
**Correção:** ajustar o tamanho/tipo da coluna `food_category` (ou o mapper) no `core-api` — fora do escopo deste runbook/feature; abrir issue. O ETL é resiliente (quarentena), mas esses 5 collaborators ficam de fora até o fix.

---

## Apêndice — limpeza

```bash
incus exec erp-validate -- bash -c 'cd /root/mono_repo/ERP-INFRA/local && ./down.sh -v'   # derruba a stack + volumes
incus stop erp-validate && incus delete erp-validate                                       # destrói a VM
```
