[← Voltar para `docs/`](../README.md)

# 📈 Plano de implementação — Observabilidade self-hosted no tailnet (OTel + GlitchTip)

| | |
|---|---|
| **Status** | 🔵 PLANO (pronto pra executar) — a fase 1 pós-MVP do web-app **ADR-0019** |
| **Donos** | Time de Infra (provisionar) · Tech Lead (instrumentar os apps) |
| **Decisão de base** | web-app ADR-0019 (observabilidade segura, adiada) — este doc é o COMO |
| **Última atualização** | 2026-06-25 |

> ⚠️ **Por que é um plano, e não "ligado" hoje:** subir observabilidade self-hosted é **infra de vários
> passos** (provisionar um nó dedicado + ClickHouse/Postgres + collector + backends, e instrumentar os **dois**
> apps com SDK). Não é um toggle. Hoje já temos o essencial barato: **`X-Request-Id` em toda resposta**,
> **reference-id na tela** nos erros, e **logs pino com redaction** acessíveis por canal privado. Este plano
> adiciona **tracing distribuído** e **agregação de exceções** por cima disso.

---

## 1. Objetivo & princípios

- **Privado por padrão:** tudo no **tailnet** (sem porta pública). OTLP e UIs só acessíveis por Tailscale.
- **Vendor-neutral:** instrumentar com **OpenTelemetry** (troca de backend sem reescrever o app).
- **Correlação:** o `trace_id` do OTel entra nos logs (junto do `request_id` que já existe) → log ↔ trace ↔ erro.
- **Custo consciente:** observability é pesada (ClickHouse/Postgres). Roda num **nó dedicado** (não na VPS de 10 GB).

## 2. Componentes (o que subir)

| Componente | Papel | Recomendação |
|---|---|---|
| **OTel Collector** | recebe traces/métricas (OTLP) dos apps e exporta pros backends | `otel/opentelemetry-collector-contrib` (Docker) |
| **Backend de traces/métricas** | armazena + UI de traces e métricas | **SigNoz** (all-in-one: traces+métricas+logs sobre ClickHouse) — 1 stack só. Alternativa: Grafana + Tempo + Prometheus. |
| **GlitchTip** | agregação de **exceções** (Sentry-compatible, leve) | `glitchtip/glitchtip` + Postgres + Redis (Docker) |

> SigNoz já inclui um OTel Collector. Pode-se usar o dele e dispensar um collector separado no MVP.

## 3. Onde rodar

- **Nó dedicado de observabilidade** no tailnet (ex.: VPS 4 GB+; ClickHouse/Postgres pedem RAM/disco).
- Taggear `tag:observability`; ACL: permitir `tag:cd-target`/`tag:prod` → `tag:observability` nas portas OTLP
  (4317 gRPC / 4318 HTTP) e as UIs só p/ `autogroup:admin`.
- **Nada exposto publicamente** — acesso às UIs (SigNoz/GlitchTip) só via tailnet.

## 4. Instrumentação dos apps (web-app + core-api)

Ambos Node — padrão idêntico. **Server-only** (nunca no bundle do browser).

1. **Tracing (OTel):**
   - deps: `@opentelemetry/sdk-node`, `@opentelemetry/auto-instrumentations-node`, `@opentelemetry/exporter-trace-otlp-http`.
   - bootstrap **antes** do app (no web-app: um Nitro plugin, como o `boot-env`; no core-api: no topo do `server.ts`).
   - auto-instrumenta `http`/`fetch` → o span BFF→core-api sai de graça; propaga `traceparent` (W3C) — o
     core-api **continua o mesmo trace** (já previsto no `observability.md`).
   - injeta o `trace_id` no logger pino (mixin) → correlaciona com o `request_id` que já existe.
2. **Exceções (GlitchTip):**
   - dep: `@sentry/node` (GlitchTip é Sentry-compatible) com o `dsn` do projeto GlitchTip.
   - captura exceções não tratadas + os erros `server` da borda (no web-app, o catch-all do `login.server-fn`
     e o `mapToServerResponse`; no core-api, o error handler do Fastify). **Com redaction** (sem PII/segredo).
3. **Sampling:** dev/staging 100%; **prod 10%** (configurável), como no `observability.md`.

## 5. Variáveis de ambiente novas (adicionar ao catálogo quando implementado)

> Ainda **não existem no código** — entram no [`env-and-secrets.reference.yaml`](../env-and-secrets.reference.yaml) na hora de instrumentar.

| Var | Secret? | Pra que |
|---|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | não | endpoint do collector no tailnet (ex.: `http://otel.<tailnet-ts.net>:4318`) |
| `OTEL_SERVICE_NAME` | não | `web-app-bff` / `core-api` |
| `OTEL_TRACES_SAMPLER` / `OTEL_TRACES_SAMPLER_ARG` | não | ex.: `parentbased_traceidratio` / `0.1` (prod) |
| `OTEL_SDK_DISABLED` | não | `true` em dev local / quando o collector não existe (degrada sem quebrar) |
| `GLITCHTIP_DSN` (`SENTRY_DSN`) | **sim** | DSN do projeto GlitchTip (por app) |

## 6. Rollout faseado (ordem recomendada)

1. **GlitchTip primeiro** (ganho rápido, leve): subir GlitchTip+Postgres+Redis no nó de obs; criar 2 projetos
   (web-app, core-api); instrumentar exceções nos dois → já vê os erros agregados. *(fecha o gap do reference-id:
   além do código na tela, o stack vai pro GlitchTip.)*
2. **OTel Collector + SigNoz**: subir a stack; abrir OTLP no tailnet.
3. **Instrumentar tracing** no web-app (Nitro plugin) → ver o trace BFF→core-api.
4. **Instrumentar tracing** no core-api (server.ts) → trace distribuído completo + spans de SQL.
5. **Dashboards + alertas** (RED por endpoint, erros 5xx, latência p95) e fechar os alertas do `observability.md`.
6. **`/metrics` Prometheus** incremental (já previsto) → SigNoz/Prometheus.

## 7. Definição de pronto (DoD)

- [ ] UIs do SigNoz e GlitchTip acessíveis **só** por tailnet (nenhuma porta pública).
- [ ] Um erro de login em QA aparece no **GlitchTip** com o **mesmo `request_id`** do log e do header `X-Request-Id`.
- [ ] Um request de leitura gera um **trace** web-app→core-api→SQL no SigNoz, com `trace_id` nos logs dos dois apps.
- [ ] Sampling 10% em prod; `OTEL_SDK_DISABLED=true` não quebra o boot (degrada).
- [ ] Vars novas no catálogo + RB de observabilidade no runbook (`deploy-and-operations.md`).

## 8. Referências
- web-app **ADR-0019** (observabilidade segura — a decisão) · [`observability.md`](../observability.md) (baseline) · [`deploy-and-operations.md`](deploy-and-operations.md) §9.
- OpenTelemetry JS · SigNoz (self-host) · GlitchTip (self-host, Sentry-compatible).
