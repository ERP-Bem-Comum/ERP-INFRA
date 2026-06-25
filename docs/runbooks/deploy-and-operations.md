[← Voltar para `docs/`](../README.md)

# 🛠️ Runbook — Deploy & Operações (ERP Bem Comum)

| | |
|---|---|
| **Tipo** | Runbook operacional (tarefas) + algumas árvores de decisão estilo *playbook* (§6) |
| **Donos** | Tech Lead (web-app) · Time de Infra (VPS/tailnet/secrets) |
| **Público** | Qualquer pessoa de plantão — escrito p/ um(a) dev **sem contexto** conseguir executar |
| **Última atualização** | 2026-06-25 |
| **Pré-leitura** | [`env-and-secrets.reference.yaml`](../env-and-secrets.reference.yaml) (catálogo de env/secrets, verificado no código) |

> **Princípio (Splunk):** runbook bom é **simples, sequencial e acessível** — instruções claras pro problema
> comum e bem-entendido. Cada procedimento aqui (RB-xxx) é **autocontido**: Sintoma → Diagnóstico → Resolução
> → Verificação → Escalonar. Se um deploy doer de um jeito **novo**, adicione um RB novo (§13, melhoria contínua).

---

## Índice rápido

- **Subir:** [§3 dev local](#3-subir-a-aplicação) · [§4 QA (CI/CD)](#4-qa--cicd-o-jeito-normal) · [§5 prod](#5-prod-lightsail-interino)
- **Verificar:** [§6 smoke checks](#6-verificação-pós-deploy-smoke-checks)
- **Quando algo quebra (RBs):** [RB-001 login "server"](#rb-001--login-falha-com-algo-deu-errado--error-server) · [RB-002 deploy vermelho](#rb-002--deploy-ci-vermelho) · [RB-003 boot crash](#rb-003--container-crasha-no-boot) · [RB-004 /ready 503](#rb-004--ready-retorna-503) · [RB-005 core-api 5xx](#rb-005--core-api-authlogin-5xx) · [RB-006 disco cheio](#rb-006--vps-sem-disco) · [RB-007 rollback](#rb-007--rollback) · [RB-008 rotação de key](#rb-008--rotação-da-auth-key-do-tailnet)
- **Manutenção:** [§11 rotação de segredos](#11-rotação-de-segredos-prazos) · [§12 escalonamento](#12-escalonamento) · [§13 melhoria contínua](#13-melhoria-contínua--automação)

---

## 0. TL;DR (caminho feliz)

| Quero… | Comando |
|---|---|
| **Subir local (tudo)** | `cd ../ERP-INFRA/local && ./up.sh` → `https://app.localhost` |
| **Deploy QA** | `git push` em **`develop`** → CI builda + escaneia + publica + deploya sozinho |
| **Está no ar?** | `curl -fsS https://<host>/health` (200) · `…/ready` (200 `{config:true,coreApi:true}`) |
| **Login quebrou** | [RB-001](#rb-001--login-falha-com-algo-deu-errado--error-server) (90% é `CORE_API_URL` sem `/api`) |
| **Rollback** | [RB-007](#rb-007--rollback) |

---

## 1. Acessos necessários (tenha ANTES de começar)

| Acesso | Pra quê | Como obter |
|---|---|---|
| `gh` autenticado (GitHub) | rodar/ver CI, PRs, secrets | `gh auth login` (org `ERP-Bem-Comum`) |
| **Tailscale** no seu dispositivo | alcançar a VPS QA (rede privada) | entrar no tailnet `tailf5e6ca.ts.net`; p/ SSH manual à VPS é preciso a regra `autogroup:admin → tag:cd-target` na ACL |
| Docker local | subir o stack dev | Docker Desktop |
| Console Magalu / AWS Lightsail | ver/operar a VPS | credenciais da cloud (Infra) |
| Secret Manager / acesso aos `./secrets` | valores de segredo | Infra |

---

## 2. Topologia (o que roda onde)

```
            ┌── Caddy (TLS · ÚNICA porta pública 80/443) ──┐
 browser ──▶│ app.* → web (front+BFF) ; api.* → core-api   │
            └──────────────────────────────────────────────┘
 web (TanStack Start) ──server-to-server──▶ core-api (Fastify) ──▶ MySQL 8.4
 • o browser NUNCA fala com o core-api direto — só via o BFF (mesma origem)
 • token vive no core-api/SessionStore; cookie __Host-session = sessionId OPACO
```

| Ambiente | Host | Sobe via | Imagem web |
|---|---|---|---|
| dev local | sua máquina | `ERP-INFRA/local/up.sh` | build local |
| **QA** | VPS Magalu `erp-bem-comum-qa` (`201.23.88.74`, 10 GB) | **CI/CD** (push `develop`) | `ghcr.io/.../bemcomum-web:qa` |
| prod (interino) | AWS **Lightsail** single-node (ADR-0002) | `deploy.sh` (script) | `:sha-<commit>` |
| prod (atual) | `erp-bem-comum.codebit.biz` (+ `…-api…`) | Codebit | — |

Imagem web = **Chainguard/Wolfi**, non-root, `.output` do Nitro (web-app ADR-0015). Ambiente **nunca compila** — só puxa.

---

## 3. Subir a aplicação

### dev local
```bash
cd ../ERP-INFRA/local
./up.sh                 # tudo → https://app.localhost  (login: admin@bemcomum.dev / SEED_PASSWORD)
./up.sh mysql minio     # só dados
./down.sh               # derruba
```
**Só o front contra core-api remoto** (sem subir core-api/mysql): crie um override setando
`CORE_API_URL: https://erp-bem-comum-api.codebit.biz/api/v2` e rode
`docker compose -f local/docker-compose.yml -f local/docker-compose.override.yml -f <override> up -d --no-deps --build web caddy`.

## 4. QA — CI/CD (o jeito normal)
**`git push` em `develop`** → workflow **`build-publish-deploy (QA)`** faz tudo num run:
```
build (Chainguard) → Trivy → push GHCR (:qa + :sha) → tailnet (TS_AUTHKEY) → SSH ubuntu@erp-bem-comum-qa
  → docker system prune -af (auto-cura de disco) → /opt/erp-qa/deploy.sh (pull :qa + up --wait)
```
Disparo = **push em `develop`** (é o gatilho confiável). ⚠️ `gh workflow run`/`workflow_dispatch`/`schedule`
do GitHub **só disparam da branch default `main`** — como os workflows vivem na `develop`, **use push**
(um commit vazio `git commit --allow-empty` força um run). Some isso some quando a `develop` virar default
ou os workflows forem pra `main`.
⚠️ o **core-api** tem pipeline/imagem própria; o `deploy.sh` puxa **as duas** — garanta que ele também publicou.

## 5. Prod (Lightsail, interino — ADR-0002)
Imagens por digest/tag imutável, `deploy.sh` versionado (ver `platform/aws-lightsail-prod/README.md`).
⚠️ **antes de subir o web-app:** `CORE_API_URL` deve terminar em `/api/v2` (o guard de boot derruba o container se errado — fail-loud).

---

## 6. Verificação pós-deploy (smoke checks)
```bash
HOST=https://erp-bem-comum.codebit.biz        # local: https://app.localhost (use curl -k p/ a CA interna)
curl -fsS $HOST/health    # 200 (liveness; não toca o backend)
curl -fsS $HOST/ready     # 200 {"status":"ready","checks":{"config":true,"coreApi":true}} ; senão 503
```
`/ready` é o **discriminador**: `coreApi:false` → BFF não alcança o core-api; `config:false` → env inválida.
**Login (smoke):** abrir `$HOST/login` e tentar com cred inválida → deve dar **"credenciais inválidas"** (não "Algo deu errado").

---

# 🔧 Runbooks de incidente (RB)

> Cada RB é uma tarefa sequencial. Comece pelo **Sintoma**. Se a **Resolução** não resolver, vá em **Escalonar**.

## RB-001 — Login falha com "Algo deu errado" / `error: "server"`
- **Sintoma:** tela de login mostra "Algo deu errado. Tente novamente." mesmo com credencial válida; resposta do `_serverFn/...login` tem `error:"server"`.
- **Severidade:** 🔴 alta (ninguém loga).
- **Diagnóstico (passo a passo):**
  1. Pegue o **`x-request-id`** do header da resposta do login (DevTools → Network) **ou** o **reference-id** na tela.
  2. Procure esse id nos **logs do web-app** (canal privado/tailnet): vai aparecer `core-api-auth:unmapped-error-slug` com um campo **`status`**.
  3. Rode `curl -fsS https://<host>/ready` — anote `checks.coreApi`.
- **Resolução (por causa):**
  - **`status: 404`** (o caso mais comum) → o `CORE_API_URL` do web-app está **sem `/api`** ou com host errado.
    1. Corrija a env do deploy do web-app p/ terminar em **`/api/v2`** (ex.: `https://erp-bem-comum-api.codebit.biz/api/v2`).
    2. Reinicie o container do web-app.
    3. Confirme: `curl -X POST https://<core-api>/api/v2/auth/login -H 'content-type: application/json' -d '{"email":"x@x.com","password":"y"}'` deve dar **401** (não 404).
  - **`status: 5xx`** → o core-api está explodindo no login → siga **[RB-005](#rb-005--core-api-authlogin-5xx)**.
  - **`coreApi:false` no /ready** → BFF não alcança o core-api (rede/DNS/URL) → cheque conectividade e o valor de `CORE_API_URL`.
- **Verificação:** login com credencial válida funciona; `/ready` 200; cred inválida agora dá "credenciais inválidas".
- **Escalonar:** se o `CORE_API_URL` estiver correto e o core-api respondendo 401 em teste direto, mas o BFF ainda dá "server" → Tech Lead (web-app).
- **Prevenção (já no código):** guard de boot do `CORE_API_URL` (web-app ADR-0020) + reference-id em todo erro `server`.

## RB-002 — Deploy (CI) vermelho
- **Sintoma:** o run `build-publish-deploy (QA)` falhou.
- **Diagnóstico:** `gh run view <id> --repo ERP-Bem-Comum/web-app` → veja **qual step** falhou.
- **Resolução (por step):**

  | Step que falhou | Causa | Fix |
  |---|---|---|
  | **Trivy** (HIGH/CRITICAL) | CVE corrigível na base | a base é Chainguard (zero-CVE); se alguém reverteu p/ distroless Debian → libssl3 CVEs → voltar p/ Chainguard. Senão, bumpar o digest da base. |
  | **Conectar na tailnet** | `TS_AUTHKEY` expirada/inválida | **[RB-008](#rb-008--rotação-da-auth-key-do-tailnet)** |
  | **SSH** ("tailnet policy does not permit") | ACL/tag | conferir ACL `ssh tag:ci → tag:cd-target` (user `ubuntu`) e nó `erp-bem-comum-qa` = `tag:cd-target` + Tailscale SSH on |
  | **deploy.sh — `no space left`** | disco da VPS cheio | **[RB-006](#rb-006--vps-sem-disco)** |
  | **deploy.sh — não fica healthy** | app não sobe | ver logs do container → **[RB-003](#rb-003--container-crasha-no-boot)** / **[RB-005](#rb-005--core-api-authlogin-5xx)** |
- **Verificação:** re-disparar o workflow e ver verde.
- **Escalonar:** Infra (tailnet/ACL/VPS) ou Tech Lead (build/app).

## RB-003 — Container crasha no boot
- **Sintoma:** o container sobe e sai logo (exit !=0); log mostra `[env] configuração inválida: ...`.
- **Causa:** fail-fast de env inválida (de propósito — fail-loud).
- **Resolução:**
  1. Leia a env citada no erro.
  2. Web-app: garanta `CORE_API_URL` com `/api`. Core-api: confira o catálogo (drivers=mysql, `*_DATABASE_URL`, JWT em prod, `S3_REGION`/`S3_BUCKET` se contracts mysql).
  3. Corrija a env no deploy/Secret Manager e reinicie.
- **Verificação:** container fica `healthy`; `/ready` 200.
- **Escalonar:** Infra (valores de env/secret) + Tech Lead (qual env é exigida).

## RB-004 — `/ready` retorna 503
- **Sintoma:** `GET /ready` → 503.
- **Diagnóstico:** olhe o corpo: `checks.config` e `checks.coreApi`.
- **Resolução:** `config:false` → env inválida ([RB-003](#rb-003--container-crasha-no-boot)). `coreApi:false` → core-api não responde no host do `CORE_API_URL` (serviço caído / rede / DNS) → suba/cheque o core-api.
- **Verificação:** `/ready` 200 com ambos `true`.

## RB-005 — core-api `/auth/login` 5xx
- **Sintoma:** o web-app loga `core-api-auth:unmapped-error-slug status:5xx`; `/health` do core-api pode estar 200.
- **Causas comuns:** DB (`*_DATABASE_URL` errada/sem SSL/pool), argon2/bcrypt (módulo nativo incompatível com o Node/arch → crasha só no verify de senha), `AUTH_JWT_*` ausente/malformada.
- **Resolução:**
  1. Pegue o **stack trace do core-api** no horário do erro.
  2. Cruze com o catálogo (DB / JWT). Confirme drivers=mysql + as URLs.
  3. `GET /docs/json` do core-api (só `NODE_ENV != production`) confirma os contratos.
- **Escalonar:** time do core-api (backend).

## RB-006 — VPS sem disco
- **Sintoma:** `deploy.sh` falha com `no space left on device`.
- **Resolução:**
  1. O deploy **já** roda `docker system prune -af` antes do pull (auto-cura). Se persistir:
  2. SSH na VPS (precisa da regra ACL admin): `ssh ubuntu@erp-bem-comum-qa`
  3. `docker system prune -af` — ⚠️ **NUNCA `--volumes`** (apagaria o MySQL).
  4. Se ainda apertado: `docker images` e remova versões antigas manualmente.
- **Verificação:** `df -h` com folga; re-rodar o deploy.
- **Escalonar:** Infra (considerar aumentar o disco da VPS).

## RB-007 — Rollback
- **Quando:** uma versão ruim foi pro QA/prod.
- **Resolução:** imagens são imutáveis por `:sha-<commit>` no GHCR.
  1. No `.env` da VPS (`/opt/erp-qa/.env`): `WEB_IMAGE=ghcr.io/erp-bem-comum/bemcomum-web:sha-<commit-bom>` (idem `CORE_API_IMAGE`).
  2. Rode `/opt/erp-qa/deploy.sh` (pull + up).
- **Verificação:** smoke checks (§6) na versão antiga.

## RB-008 — Rotação da auth key do tailnet
- **Quando:** `TS_AUTHKEY` expirou (⚠️ **2026-09-23**) ou foi comprometida. (Rastreado: web-app **issue #92**.)
- **Aviso automático:** o job `deploy-qa` (no `build-publish.yml`) avisa (issue) quando faltam ≤14 dias.
- **Resolução:**
  1. Crie nova auth key `tag:ci` (reusable+ephemeral+preauth) via Tailscale API ou console.
  2. `printf '%s' "<nova>" | gh secret set TS_AUTHKEY --repo ERP-Bem-Comum/web-app` (sem ecoar).
  3. **Atualize o `KEY_EXPIRY`** em `web-app/.github/workflows/build-publish.yml` (job `deploy-qa`) p/ a nova data.
  4. (Opcional) revogue a key antiga.
- **Verificação:** no próximo **push em `develop`** (ou re-deploy) o step *Conectar na tailnet* fica verde.
  (`gh workflow run`/agendado **não** dispara de `develop` — só da branch default `main`.)

---

## 11. Rotação de segredos (prazos)

| Segredo | Onde | Prazo / gatilho | Procedimento |
|---|---|---|---|
| `TS_AUTHKEY` | GitHub Secrets (web-app) | **2026-09-23** (issue #92) | [RB-008](#rb-008--rotação-da-auth-key-do-tailnet) |
| `AUTH_JWT_PRIVATE/PUBLIC_KEY` | Secret Manager | trimestral / comprometimento | gerar par ES256 → rotacionar → invalidar sessões |
| Senhas de DB (`*_DATABASE_URL`) | Secret Manager / Docker secret | trimestral | rotacionar no MySQL → atualizar secret → reiniciar |
| `SMTP_PASS` / `RESEND_API_KEY` | Secret Manager | conforme provedor | atualizar secret → reiniciar |

Regra: segredo **nunca** em git/imagem/log.

## 12. Escalonamento

| Camada do problema | Responsável | Canal |
|---|---|---|
| Build / app / web-app (BFF) / contratos de erro | **Tech Lead (web-app)** | issue no repo `web-app` |
| core-api (login 5xx, DB, JWT, migrations) | **Time do core-api** | issue no repo `core-api` |
| VPS / tailnet / ACL / secrets / disco / Lightsail | **Time de Infra** | issue no repo `ERP-INFRA` |
| Incidente em produção (usuários afetados) | acionar Tech Lead **e** Infra em paralelo | + registrar um RB novo no fim (§13) |

> Sempre inclua o **`x-request-id`/reference-id** do erro ao escalar — é o que correlaciona tela ↔ log.

## 13. Melhoria contínua & automação

- **Toda vez que um incidente novo acontecer**, adicione um **RB-xxx** aqui (Sintoma→Diagnóstico→Resolução→Verificação→Escalonar). Runbook desatualizado é pior que não ter.
- **Candidatos a automação** (princípio Splunk — reduzir variáveis, tornar modular):
  - ✅ já automatizado: build+scan+publish+deploy (1 push); prune de disco no deploy; **smoke-check `/ready`
    pós-deploy**; **`/ready` sonda uma rota real `/api/v2`** (pega CORE_API_URL errado); **aviso de expiração
    da `TS_AUTHKEY` (<14d)** no job `deploy-qa`.
  - ⏳ a fazer: **OpenTelemetry + GlitchTip** self-hosted no tailnet — plano pronto em
    [`observability-self-hosted-plan.md`](observability-self-hosted-plan.md) (ADR-0019);
    schedule real do alerta de expiração (depende dos workflows estarem na branch default `main`).

## 14. Referências
- **[`env-and-secrets.reference.yaml`](../env-and-secrets.reference.yaml)** — catálogo de env/secrets (a referência).
- [`topology.md`](../topology.md) · [`environments.md`](../environments.md) · [`secrets.md`](../secrets.md) · [`observability.md`](../observability.md) · [`adr/0002-…`](../adr/0002-producao-economica-aws-lightsail.md)
- web-app: `.github/workflows/build-publish.yml` · ADRs 0014/0015/0016/0018/0019/0020 · **issue #92**.
- core-api ao vivo: `GET /docs/json` (`NODE_ENV != production`).
