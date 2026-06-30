# ADR-0003 — Produção em AWS ECS

**Status:** ✅ Aceito
**Data:** 2026-06-30
**Decisor inicial:** Time de Infra (confirmado com o time de plataforma)
**Reviewers obrigatórios:** dev sênior + líder de infra

---

## Contexto

Esta ADR **substitui a [ADR-0002](0002-producao-economica-aws-lightsail.md)**
(produção econômica single-node em AWS Lightsail), que ficou apenas como registro
histórico da alternativa de menor custo considerada e descartada. O diretório
`platform/aws-lightsail-prod/` foi removido — o baseline Lightsail nunca foi
provisionado.

A produção real do ERP Bem Comum foi implementada em **AWS ECS** com pipeline
gerenciado de entrega contínua (CodePipeline/CodeBuild/CodeDeploy), banco
gerenciado (RDS), load balancer gerenciado (ELB) e segredos no Secrets Manager.
Isso atende o alvo de alta disponibilidade descrito em
[`../topology.md`](../topology.md): múltiplas réplicas da API atrás de um load
balancer, banco gerenciado e deploy sem necessidade de operar uma VPS manualmente.

O `core-api` já descreve toda a sua topologia de processos em um único
[`compose.yaml`](../../../core-api/compose.yaml) (a **planta**): um serviço HTTP
(`http`), cinco workers long-running (profile `workers`), jobs one-shot
(profile `jobs`, incluindo o `migrate`) e as dependências de infra (`mysql`,
`minio`, `mailpit`) que em produção viram managed services. Em vez de manter um
manifesto ECS escrito à mão e divergente, a infra **traduz essa planta** para os
artefatos do ECS.

## Decisão

Rodar a produção em **AWS ECS**, com a seguinte composição de serviços
gerenciados:

- **Orquestração de containers:** AWS **ECS** (Task Definitions + ECS Services).
- **CI/CD:** **CodePipeline** → **CodeBuild** (build da imagem + push para o
  **ECR**) → **CodeDeploy** (registra a nova Task Definition e atualiza o ECS
  Service).
- **Banco de dados:** **RDS** (MySQL 8.4 gerenciado) — substitui o container
  `mysql` da planta. Mantém ADR-0013/0020 (MySQL como engine/dialeto único).
- **Load balancer / borda:** **ELB** — substitui o `edge`/Caddy local; termina o
  TLS e distribui para as réplicas da API.
- **Segredos:** **AWS Secrets Manager** — substitui os arquivos `./secrets/*.txt`
  da planta (ADR-0011 continua válido: segredo nunca em imagem/env literal/log).
- **E-mail:** **Amazon SES via SMTP** — `EMAIL_PROVIDER=smtp`,
  `SMTP_HOST=email-smtp.<região>.amazonaws.com`. O contrato de e-mail (ADR-0010)
  é o mesmo dos demais ambientes; só muda o host/credencial.
- **Storage de documentos:** AWS **S3** (ADR-0019) — substitui o `minio` local.

### Como funciona (tradução do `compose.yaml` → ECS)

A infra **traduz o `compose.yaml` do core-api** (branch `main`) para o ECS,
serviço a serviço:

| Na planta (`compose.yaml`)            | Em produção (AWS ECS)                                              |
| ------------------------------------- | ----------------------------------------------------------------- |
| cada `service` de aplicação           | **1 Task Definition + 1 ECS Service** (mesma imagem do ECR)       |
| `command` / `entrypoint` do service   | `command` sobrescrito na Task Definition (mesma imagem, papel ≠)  |
| `http` (profile `app`)                | ECS Service **atrás do ELB** (tem porta HTTP `:3000`)            |
| os 5 workers (profile `workers`)      | 1 ECS Service **cada, sem ELB** (não expõem porta HTTP)          |
| `migrate` (profile `jobs`/`app`)      | task one-shot executada antes de atualizar os Services            |
| `mysql`                               | **RDS** (MySQL gerenciado)                                         |
| `edge`/Caddy                          | **ELB**                                                            |
| `secrets:` (arquivos `*.txt`)         | **Secrets Manager** (injetado na Task Definition)                 |
| `minio`                               | **S3**                                                             |

Princípios da tradução:

- **Uma imagem, vários papéis.** Todos os serviços de aplicação usam a **mesma
  imagem** do ECR (a do core-api); o que muda entre eles é só o `command`
  (qual processo Node subir), exatamente como na planta.
- **API atrás do ELB; workers não.** A API (`http`) recebe tráfego do ELB. Os
  workers não têm porta HTTP — são ECS Services sem target group.
- **Workers de outbox escalam horizontalmente.** `outbox-contracts` e
  `outbox-partners` usam `FOR UPDATE SKIP LOCKED`, então N réplicas consomem o
  outbox **sem duplicar evento** (ADR-0015). As projeções e o `email-dispatch`
  rodam com 1 réplica.
- **Migrations fora do boot.** O schema é aplicado pela task `migrate`
  (`src/jobs/migrate/run.ts`) **antes** de promover as novas Task Definitions —
  o `http` e os workers já sobem com o schema migrado.

> **Detalhes a confirmar com o time de infra** (não fixados nesta ADR para não
> divergir do provisionado): conta AWS, **região**, nome do **cluster ECS**,
> ARNs das Task Definitions / ECS Services / target groups, ARNs dos segredos no
> Secrets Manager, classe/Multi-AZ da instância **RDS**, repositório **ECR**,
> nome/idempotência do estágio **CodeDeploy** (blue/green vs rolling) e o
> mapeamento exato de `<região>` em `email-smtp.<região>.amazonaws.com`.

## Alternativas consideradas

### AWS Lightsail single-node (ADR-0002)

Era o baseline econômico inicial: uma VPS rodando Docker Compose. **Descartado** —
ponto único de falha, sem failover, MySQL competindo por recurso com as aplicações
e sem caminho de escala horizontal. Permanece como registro histórico na ADR-0002.

### EC2 self-managed + Docker Compose

Mais barato que ECS, porém transfere para a equipe a operação de patching, scaling
e disponibilidade do host. Rejeitado pelo custo operacional humano frente ao ECS
gerenciado.

### Kubernetes (EKS)

Poderoso, porém complexidade operacional e custo de control plane desproporcionais
ao tamanho atual do produto. Reavaliável se a malha de serviços crescer muito.

## Consequências

### Positivas

- ✅ **Alta disponibilidade real:** múltiplas réplicas da API atrás do ELB; RDS
  gerenciado com backup/PITR; sem ponto único de falha de aplicação.
- ✅ **Deploy sem operar VPS:** CodePipeline/CodeBuild/CodeDeploy entregam por
  imagem imutável; rollback é re-promover a Task Definition anterior.
- ✅ **Planta única como fonte de verdade:** o `compose.yaml` do core-api descreve
  os processos; a infra traduz, não reinventa. Menos divergência dev ↔ infra.
- ✅ **Escala horizontal dos workers de outbox** sem duplicar evento
  (`SKIP LOCKED`).
- ✅ **Segredos centralizados** no Secrets Manager com rotação/audit.

### Negativas

- ❌ Custo fixo maior que o baseline Lightsail descartado (ELB + RDS + NAT).
- ❌ Mais peças gerenciadas para entender e operar (ECS, ELB, RDS, Secrets
  Manager, CodePipeline) — a curva de aprendizado é maior que um `docker compose up`.
- ❌ A **tradução** planta→ECS precisa ser mantida em sincronia: se um `service`
  novo entrar no `compose.yaml`, a infra precisa criar a Task Def + Service
  correspondente. Divergência sem PR é bug de processo (ADR-0001).

## Referências

- [`0002-producao-economica-aws-lightsail.md`](0002-producao-economica-aws-lightsail.md) — ADR superada.
- [`../environments.md`](../environments.md) — inventário de ambientes.
- [`../topology.md`](../topology.md) — alvo de produção (HA).
- [`../../platform/README.md`](../../platform/README.md) — IaC real.
- [`../runbooks/deploy-and-operations.md`](../runbooks/deploy-and-operations.md) — §5 Prod (AWS ECS).
- [`compose.yaml` do core-api](../../../core-api/compose.yaml) — a planta traduzida para ECS.
