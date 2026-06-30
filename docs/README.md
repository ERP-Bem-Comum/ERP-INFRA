[← Voltar para raiz](../README.md)

# 📐 docs/

Esta pasta é a **especificação técnica viva** da infraestrutura do ERP Bem Comum.

| Arquivo | Função | Audiência |
|---|---|---|
| [`topology.md`](topology.md) | Diagrama Mermaid de componentes e fluxos | Dev + Infra |
| [`environments.md`](environments.md) | dev / staging / prod — diferenças e promoção | Dev + Infra |
| [`secrets.md`](secrets.md) | Catálogo de secrets (resumo; ver o YAML abaixo) | Dev + Infra + Security |
| [`env-and-secrets.reference.yaml`](env-and-secrets.reference.yaml) | **Catálogo COMPLETO de env vars & secrets** (frontend + backend), verificado no código — a referência | Dev + Infra + Security |
| [`observability.md`](observability.md) | Logs, métricas, tracing, alertas baseline | Dev + Infra + Oncall |
| [`runbooks/aws-ecs-architecture-by-layer.md`](runbooks/aws-ecs-architecture-by-layer.md) | **Guia didático da prod AWS ECS, camada por camada** (Rede/RDS/Secrets/ECS/ELB/CloudWatch) — diagramas + Terraform/HCL + Task Def JSON | Dev + Infra |
| [`runbooks/ci-cd-pipeline.md`](runbooks/ci-cd-pipeline.md) | **Guia do pipeline CI/CD** CodePipeline→CodeBuild→ECR→CodeDeploy→ECS — `buildspec.yml`/`appspec.yaml`/`taskdef.json` + diagramas | Dev + Infra |
| [`runbooks/deploy-and-operations.md`](runbooks/deploy-and-operations.md) | **Runbook de deploy & operações** — subir, verificar, debugar (RBs), rollback, rotação | Dev + Infra + Oncall |
| [`runbooks/observability-self-hosted-plan.md`](runbooks/observability-self-hosted-plan.md) | Plano de OTel + GlitchTip self-hosted no tailnet (fase 1 — ADR-0019) | Dev + Infra |
| [`adr/`](adr/) | Decisões arquiteturais específicas deste repo | Todos |

## Status dos documentos

Cada documento abre com um cabeçalho **Status** que indica:

- 🔵 **PLANEJADA** — reflete a decisão do handbook, ainda não validada contra infra real
- 🟢 **VIGENTE** — confirmada que reflete a infra real provisionada
- 🟡 **DIVERGENTE** — sabidamente diferente do que está em prod (PR em andamento)
- 🔴 **DESATUALIZADA** — divergência conhecida sem PR; precisa correção urgente

> **Time de Infra**: por favor mantenham esses status atualizados. Documentos sem status presumem-se 🔵.

## Como contribuir com docs

Veja [`../CONTRIBUTING.md`](../CONTRIBUTING.md). Resumo:

- PRs em `docs/` precisam de **1 dev sênior + 1 do time de infra**
- ADRs precisam de **2 reviewers** (dev sênior + líder de infra)
- Squash merge; título do PR vira a mensagem final em Conventional Commits
