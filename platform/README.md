[← Voltar para raiz](../README.md)

# 🏗️ `platform/` — Infraestrutura como código (real)

> **Status atual:** 🔵 VAZIO — aguardando o time de infra/plataforma preencher.

Esta pasta é o **lar da IaC real**: o código que provisiona e mantém o que está rodando em `dev`, `staging` e `prod`. Diferente de [`../docs/`](../docs/) (que é especificação), aqui é **execução**.

---

## ⚠️ Para o time de infra

Por favor, ao começarem o provisionamento:

1. **Escolham a ferramenta primária** e documentem em uma ADR ([`../docs/adr/`](../docs/adr/)). Candidatas mencionadas no handbook:
   - Terraform (HashiCorp)
   - Pulumi (TypeScript/Python/Go)
   - AWS CDK (se for AWS exclusivo)
   - Helm + manifests Kubernetes (se for k8s exclusivo)
   - Combinação (Terraform para cloud, Helm para k8s, por exemplo)

2. **Estruturem em módulos por preocupação**, não por ambiente. Exemplo (Terraform):

   ```
   platform/
   ├── terraform/
   │   ├── modules/
   │   │   ├── vpc/
   │   │   ├── mysql/
   │   │   ├── ecs-or-k8s/
   │   │   ├── secrets/
   │   │   └── observability/
   │   └── environments/
   │       ├── dev/
   │       ├── staging/
   │       └── prod/
   ├── helm/                   (se aplicável)
   │   └── charts/
   └── scripts/                (one-off, anonimização de dumps, etc.)
   ```

   O princípio: **mesmo módulo, parâmetros diferentes por ambiente**. Espelhamento de staging/prod é regra (ver [`../docs/environments.md`](../docs/environments.md) §2).

3. **State remoto + locking** desde o primeiro commit (Terraform Cloud, S3+DynamoDB, GCS, Pulumi Cloud — escolha do time). State local nunca, mesmo em dev.

4. **Sem secrets commitados**. Use o Secrets Manager escolhido (ver [`../docs/secrets.md`](../docs/secrets.md)) e referencie via data sources.

5. **Documentem decisões importantes** em [`../docs/adr/`](../docs/adr/) — multi-cloud, isolamento de rede, estratégia de IAM, etc.

6. **Mantenham [`../docs/topology.md`](../docs/topology.md) atualizado** quando a infra real divergir do diagrama. Divergência sem PR é um bug de processo.

---

## O que devs precisam saber sobre esta pasta

- **Não toquem aqui sem coordenar com infra.** Mudanças têm impacto em produção.
- Se uma decisão arquitetural do time de dev exigir mudança de infra (nova porta, nova rota de egress, novo serviço de cache, etc.):
  1. Abram issue neste repo descrevendo a necessidade
  2. Discutam com o time de infra
  3. Quando acordado, infra commita; o PR aciona reviewer dev sênior via [`CODEOWNERS`](../CODEOWNERS)

---

## Convenções (a confirmar pela infra)

🔵 As convenções abaixo são **sugestões**; o time de infra define a versão final em ADR.

| Tópico | Sugestão |
|---|---|
| Nome de recursos | `erp-<servico>-<ambiente>` (ex.: `erp-mysql-prod`) |
| Tags / labels | `Environment`, `Service`, `Owner`, `CostCenter`, `Repo` |
| Versionamento de módulos | SemVer; `main` sempre verde |
| Apply | Via PR + plan revisado; nunca `terraform apply -auto-approve` em staging/prod |
| Rollback | Reverter o commit + replan + reapply |

---

## Status de provisionamento por componente

Atualizem este quadro conforme provisionarem:

| Componente | dev | staging | prod | Última atualização |
|---|---|---|---|---|
| VPC / rede | 🔵 | 🔵 | 🔵 | — |
| MySQL managed | 🔵 | 🔵 | 🔵 | — |
| Orquestrador (k8s / ECS / ...) | 🔵 | 🔵 | 🔵 | — |
| Load Balancer + WAF | 🔵 | 🔵 | 🔵 | — |
| Secrets Manager | 🔵 | 🔵 | 🔵 | — |
| Coletor de logs | 🔵 | 🔵 | 🔵 | — |
| Prometheus + dashboards | 🔵 | 🔵 | 🔵 | — |
| Tracing (OTLP collector) | 🔵 | 🔵 | 🔵 | — |
| Alertas | 🔵 | 🔵 | 🔵 | — |
| Egress whitelist Bradesco | 🔵 | 🔵 | 🔵 | — |

🔵 = não provisionado · 🟡 = parcial · 🟢 = pronto e validado · 🔴 = problema conhecido
