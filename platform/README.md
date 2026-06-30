[← Voltar para raiz](../README.md)

# 🏗️ `platform/` — Infraestrutura como código (real)

> **Status atual:** 🟡 PARCIAL — há OpenTofu para a VM/rede de `qa` e um runbook
> de deploy em [`vps-qa/`](vps-qa/) (Magalu Cloud). A **produção roda em AWS ECS**
> (ver [`ADR-0003`](../docs/adr/0003-producao-aws-ecs.md)); a IaC do ECS é mantida
> pelo time de infra (ARNs/região/cluster a confirmar).

Esta pasta é o **lar da IaC real**: o código que provisiona e mantém o que está rodando em `dev`, `staging` e `prod`. Diferente de [`../docs/`](../docs/) (que é especificação), aqui é **execução**.

## QA rápido na Magalu Cloud

- Provisionamento: [`tofu/environments/qa/`](tofu/environments/qa/)
- Runtime da VPS: [`vps-qa/`](vps-qa/)
- VM criada: Ubuntu 24.04, `br-ne1-a`, `BV1-2-20`
- ID: `c9e17d68-a474-41b2-a079-be747192f55c`
- Chave SSH: `erp-bem-comum`; usuário: `ubuntu`

> A VM foi criada inicialmente pelo painel. Não execute `tofu apply` até
> importar os recursos existentes para o state, para evitar recursos duplicados.

Esse QA é econômico e single-node. Não substitui o `staging` espelhado a
produção descrito em [`../docs/environments.md`](../docs/environments.md).

## Produção na AWS (ECS)

- Orquestração: **AWS ECS** — a infra **traduz o `compose.yaml` do core-api** em
  **1 Task Definition + 1 ECS Service por service** (mesma imagem do ECR, `command`
  sobrescrito). A **API** (`http`) fica atrás do **ELB**; os 5 workers do profile
  `workers` são ECS Services **sem ELB** (não expõem porta HTTP).
- Banco: **RDS** (MySQL gerenciado) · Segredos: **Secrets Manager** ·
  E-mail: **Amazon SES (SMTP)** · Documentos: **S3**.
- CI/CD: **CodePipeline → CodeBuild** (build da imagem + push para o **ECR**) →
  **CodeDeploy** (registra a Task Definition + atualiza o ECS Service).
- Decisão e detalhes: [`ADR-0003 — Produção AWS ECS`](../docs/adr/0003-producao-aws-ecs.md).
  A IaC do ECS é mantida pelo time de infra; **ARNs/região/cluster/conta a confirmar**.

> Este alvo entrega a alta disponibilidade descrita em
> [`../docs/topology.md`](../docs/topology.md) (ELB + múltiplas tasks da API + RDS).
> A antiga produção econômica single-node em Lightsail foi descartada
> ([`ADR-0002`](../docs/adr/0002-producao-economica-aws-lightsail.md), superada).

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

| Componente | qa | staging | prod | Última atualização |
|---|---|---|---|---|
| VPC / rede | 🟡 | 🔵 | 🟢 AWS | 2026-06-30 |
| Orquestrador (runtime) | 🟡 Docker Compose | 🔵 | 🟢 **ECS** | 2026-06-30 |
| MySQL managed | 🔵 | 🔵 | 🟢 **RDS** | 2026-06-30 |
| Load Balancer | 🔵 | 🔵 | 🟢 **ELB** | 2026-06-30 |
| Secrets Manager | 🔵 | 🔵 | 🟢 **✓** | 2026-06-30 |
| CI/CD (pipeline) | 🟡 GitHub Actions | 🔵 | 🟢 **CodePipeline** | 2026-06-30 |
| E-mail (SMTP) | 🔵 | 🔵 | 🟢 **Amazon SES** | 2026-06-30 |
| Coletor de logs | 🔵 | 🔵 | 🔵 | — |
| Prometheus + dashboards | 🔵 | 🔵 | 🔵 | — |
| Tracing (OTLP collector) | 🔵 | 🔵 | 🔵 | — |
| Alertas | 🔵 | 🔵 | 🔵 | — |
| Egress whitelist Bradesco | 🔵 | 🔵 | 🔵 | — |

🔵 = não provisionado · 🟡 = parcial · 🟢 = pronto e validado · ⚪ = não aplicável · 🔴 = problema conhecido

> Prod em **AWS ECS** conforme [`ADR-0003`](../docs/adr/0003-producao-aws-ecs.md).
> Os detalhes específicos (conta, região, nome do cluster, ARNs) são **a confirmar
> com o time de infra**. O ambiente `x99` (sandbox interno `incus`, docker-compose)
> não entra neste quadro de IaC cloud — ver [`../docs/environments.md`](../docs/environments.md).
