[← Voltar para `platform/`](../README.md)

# 🟦 `aws-ecs-prod/` — Task Definitions de produção (AWS ECS)

| | |
|---|---|
| **Tipo** | Artefato de IaC (templates de ECS Task Definition, um por serviço) + guia didático |
| **Decisão-mãe** | [`ADR-0003 — Produção em AWS ECS`](../../docs/adr/0003-producao-aws-ecs.md) |
| **Planta traduzida** | [`core-api/compose.yaml`](../../../core-api/compose.yaml) + [`core-api/Dockerfile`](../../../core-api/Dockerfile) |
| **Guias irmãos** | [`aws-ecs-architecture-by-layer.md`](../../docs/runbooks/aws-ecs-architecture-by-layer.md) (camada a camada) · [`ci-cd-pipeline.md`](../../docs/runbooks/ci-cd-pipeline.md) (como esses arquivos viram deploy) |
| **Status** | 🔵 REFERÊNCIA — descreve o **alvo** do ADR-0003. Valores reais (conta, região, ARNs, cluster) **a confirmar com o time de infra**. |

> ### ⚠️ Sobre os valores nos arquivos
> Todo `*.taskdef.json` usa **placeholders** — `<ACCOUNT_ID>`, `<REGIAO>`,
> `<DOMINIO_FRONT>`, `<CIDR_DO_ELB>`, `<SES_SMTP_USERNAME>`, `<commit>`. Os valores
> reais (conta AWS, região, ARNs dos secrets, nome do bucket, usuário SMTP do SES)
> são **a confirmar com o time de infra**. Os arquivos ensinam o **formato e a
> ligação** entre serviços — não estão prontos para `register-task-definition` como
> estão.

---

## 0. A ideia central: **uma imagem, N Task Definitions**

O `core-api` descreve toda a sua topologia de processos num único arquivo —
[`compose.yaml`](../../../core-api/compose.yaml), a **"planta"**. A produção não
reinventa essa planta: **traduz** cada `service` de aplicação em **1 Task Definition
+ 1 ECS Service** (regra do [`ADR-0003`](../../docs/adr/0003-producao-aws-ecs.md)).

A imagem Docker é **uma só** — `core-api:sha-<commit>`, publicada no ECR pelo
CodeBuild. O [`Dockerfile`](../../../core-api/Dockerfile) tem
`ENTRYPOINT ["tini", "--", "node", "src/server.ts"]`: por padrão a imagem **sobe a
API**. Cada worker/job **sobrescreve** isso (`entryPoint` + `command`) para subir o
seu próprio `run.ts`. **Mesma imagem, processo diferente** — é a frase que organiza
tudo aqui.

```
            ┌──────────────────────────────────────────────┐
            │   ECR: core-api:sha-<commit>  (UMA imagem)    │
            │   ENTRYPOINT: tini -- node src/server.ts      │
            └──────────────────────────────────────────────┘
                 │            │              │           │
   (sem override)│   (override command)     │           │
                 ▼            ▼              ▼           ▼
            api.taskdef   outbox-*.taskdef  …projection  migrate/sweeper
            (server.ts)   (worker run.ts)   (worker)     (job run.ts)
                 │            │              │           │
                 ▼            ▼              ▼           ▼
            ECS Service   ECS Service    ECS Service   RunTask one-shot
            + ELB         (sem ELB)      (sem ELB)     (não é Service)
```

### Como esses arquivos viram ECS Services

Cada `*.taskdef.json` é um **template de revisão** de Task Definition. No deploy
([`ci-cd-pipeline.md`](../../docs/runbooks/ci-cd-pipeline.md)):

1. **CodeBuild** constrói a imagem (`--target runtime`) e publica `core-api:sha-<commit>`
   no **ECR**; emite `imagedefinitions.json`/`imageDetail.json` com a URI da imagem.
2. **CodeDeploy/CodePipeline** registra cada taskdef como uma **nova revisão** (injetando
   a URI da imagem) e atualiza o **ECS Service** correspondente — a API em **blue/green**
   (tem ELB), os workers em **rolling** (não têm ELB).
3. O job **`migrate` roda ANTES** de promover os Services (schema migrado primeiro).

> **Sobre o campo `image`.** Nestes templates ele aparece como a URI completa
> `<ACCOUNT_ID>.dkr.ecr.<REGIAO>.amazonaws.com/core-api:sha-<commit>` (didático). No
> fluxo CodeDeploy, esse valor costuma ser o token literal **`<IMAGE1_NAME>`**, que o
> pipeline substitui pela URI `:sha-<commit>` em cada deploy (ver `ci-cd-pipeline.md`
> §4). Troque conforme o modo de deploy que a infra escolher.

> **JSON estrito (sem comentários).** Diferente dos exemplos `jsonc` dos runbooks
> (que usam `//` só para ensinar), estes arquivos são **JSON válido e parseável** —
> prontos para `aws ecs register-task-definition --cli-input-json file://...`. Toda a
> explicação didática vive **aqui no README**.

---

## 1. Anatomia de uma Task Definition — bloco a bloco

Use o [`api.taskdef.json`](taskdefs/api.taskdef.json) como referência ao ler.

### Nível da task (a "receita" da task inteira)

| Campo | O que é / por que importa |
|---|---|
| **`family`** | O **nome** da Task Definition. Cada `register` cria uma nova **revisão** (`family:1`, `family:2`, …); o Service aponta para uma revisão. Convenção aqui: `erp-prod-<servico>`. |
| **`requiresCompatibilities: ["FARGATE"]`** | Roda em **Fargate** (serverless): a AWS gerencia o host; você não cuida de EC2. |
| **`networkMode: "awsvpc"`** | Cada task ganha **sua própria ENI/IP** na VPC. É o que permite prendê-la a um security group e colocá-la em subnet privada (Camada 1 do `architecture-by-layer.md`). Obrigatório no Fargate. |
| **`cpu` / `memory`** | Reserva de CPU (em unidades: `256` = 0.25 vCPU, `512` = 0.5, `1024` = 1) e RAM em MiB. **Combinações são fixas no Fargate** (ex.: cpu `256` aceita memory 512/1024/2048). Ver dimensionamento na §3. |
| **`runtimePlatform`** | `cpuArchitecture: X86_64` + `operatingSystemFamily: LINUX`. A imagem é construída para `linux/amd64` (o `--platform linux/amd64` do buildspec) — declarar evita "exec format error". |
| **`executionRoleArn`** | A **role do AGENTE do ECS** (não do seu código). Usada **no boot da task** para: puxar a imagem do ECR, **ler os secrets do Secrets Manager** e escrever logs no CloudWatch. Sem ela (e sem `secretsmanager:GetSecretValue`), a task **nem sobe**. |
| **`taskRoleArn`** | A **role do SEU CÓDIGO em runtime**. É por aqui que a API fala com o **S3** sem chave estática (IAM Role; ver §"S3" abaixo). Workers/jobs usam uma role mínima. |
| **`containerDefinitions`** | A lista de containers (aqui, **um** por task). Detalhado abaixo. |
| **`tags`** | Metadados (`Environment`, `Service`, `Type`, `Owner`, `Repo`) — para custo/auditoria e para identificar o serviço. |

### Nível do container (dentro de `containerDefinitions[0]`)

| Campo | O que é / por que importa |
|---|---|
| **`name`** | Nome do container. É o **alvo da injeção de imagem** do CodeDeploy (`Image1ContainerName`) e o que aparece no log stream. |
| **`image`** | A URI da imagem no ECR (`:sha-<commit>`). **A mesma** em todos os 8 arquivos — muda só o `command`. |
| **`essential: true`** | Se este container morre, a task inteira é considerada falha (e reiniciada). Como há 1 container por task, é sempre `true`. |
| **`entryPoint` + `command`** | **O coração da tradução "uma imagem, N papéis".** A **API não os declara** → usa o `ENTRYPOINT` da imagem (`tini -- node src/server.ts`). Cada **worker/job** sobrescreve `entryPoint: ["tini","--","node"]` (mantém `tini` como PID 1 + reaping de zumbis + forward de SIGTERM) e passa o `run.ts` em `command`. |
| **`environment`** | Variáveis **não-secretas** (drivers `=mysql`, `NODE_ENV`, host SMTP do SES, etc.). Vão em **texto** no JSON — nunca ponha segredo aqui. |
| **`secrets`** | Variáveis **secretas**: `{ name, valueFrom: <ARN do Secrets Manager> }`. O agente ECS resolve cada `valueFrom` **no boot** (via `executionRole`) e injeta como env var — **nunca** aparece em log, imagem ou `docker inspect`. Substitui o truque `sh -c "export X=$(cat /run/secrets/...)"` do compose local. |
| **`logConfiguration` (`awslogs`)** | Manda o `stdout`/`stderr` para um **log group do CloudWatch** (`/erp/prod/<servico>`). **Sem este bloco, NENHUM log aparece** (o `stdout` da task efêmera some). O core-api loga JSON estruturado em stdout. |
| **`portMappings`** | **Só a API.** Expõe a porta `3000` para o ELB registrar a task no target group. Workers/jobs **não escutam porta** → não têm. |
| **`healthCheck`** | **Só a API.** Probe `node -e "fetch('http://127.0.0.1:3000/health')…"` — **idêntico** ao do [`Dockerfile`](../../../core-api/Dockerfile) (a imagem base `bookworm-slim` não tem `curl`/`wget`). O ECS recicla a task se falhar. |

### Por que workers/jobs **não** têm `portMappings` nem `healthCheck`?

Porque **não são servidores HTTP** — são **loops** (workers long-running que drenam o
outbox/projeções) ou **processos one-shot** (jobs que rodam e saem). Não escutam porta,
então não há o que o ELB registrar nem o que um probe HTTP testar. A "saúde" deles é
simplesmente **estar `RUNNING`** (e, para jobs, **sair com exit 0**). Logs no CloudWatch
são o canal de observabilidade — daí todo worker/job manter o `logConfiguration`.

---

## 2. Tabela de TODOS os serviços de produção

| Arquivo | `command` (override) | Tipo | ELB? | Escala (prod) | Secrets principais |
|---|---|---|:--:|---|---|
| [`api.taskdef.json`](taskdefs/api.taskdef.json) | *(nenhum — `ENTRYPOINT` da imagem: `src/server.ts`)* | **API** | ✅ | **2+** (autoscaling por CPU, alvo 60%) | 5× `*_DATABASE_URL` + `AUTH_JWT_PRIVATE_KEY`/`_PUBLIC_KEY` |
| [`email-dispatch.taskdef.json`](taskdefs/email-dispatch.taskdef.json) | `src/workers/email-dispatch/run.ts` | worker | ❌ | **1** (não idempotente sob concorrência) | `AUTH_DATABASE_URL`, `PARTNERS_DATABASE_URL`, `SMTP_PASS` |
| [`outbox-contracts.taskdef.json`](taskdefs/outbox-contracts.taskdef.json) | `src/modules/contracts/worker/run.ts` | worker | ❌ | **2+** (escala via `SKIP LOCKED`) | `CONTRACTS_DATABASE_URL` |
| [`outbox-partners.taskdef.json`](taskdefs/outbox-partners.taskdef.json) | `src/modules/partners/worker/run.ts` | worker | ❌ | **2+** (escala via `SKIP LOCKED`) | `PARTNERS_DATABASE_URL` |
| [`supplier-projection.taskdef.json`](taskdefs/supplier-projection.taskdef.json) | `src/workers/supplier-view-projection/run.ts` | worker | ❌ | **1** | `PARTNERS_DATABASE_URL`, `FINANCIAL_DATABASE_URL` |
| [`contract-count-projection.taskdef.json`](taskdefs/contract-count-projection.taskdef.json) | `src/workers/contract-count-projection/run.ts` | worker | ❌ | **1** | `CONTRACTS_DATABASE_URL`, `PARTNERS_DATABASE_URL` |
| [`migrate.taskdef.json`](taskdefs/migrate.taskdef.json) | `src/jobs/migrate/run.ts` | **job** one-shot | ❌ | — (RunTask **antes** dos Services) | `MIGRATE_DATABASE_URL` |
| [`sweeper.taskdef.json`](taskdefs/sweeper.taskdef.json) | `src/jobs/contracts/sweeper/run.ts` | **job** cron | ❌ | — (1×/dia via EventBridge Scheduler) | `CONTRACTS_DATABASE_URL` |

> Fonte canônica de `command`/env/secrets: [`compose.yaml`](../../../core-api/compose.yaml)
> (service `http` + profiles `workers`/`jobs`) e o catálogo verificado
> [`env-and-secrets.reference.yaml`](../../docs/env-and-secrets.reference.yaml). A infra
> **traduz** — não reinventa (ADR-0003).

### Por que os outbox escalam e as projeções/`email-dispatch` não?

- **`outbox-contracts` / `outbox-partners`** leem o outbox com `SELECT … FOR UPDATE
  SKIP LOCKED` (ADR-0015). N réplicas consomem **sem duplicar evento** → `desiredCount ≥ 2`
  e escala com `aws ecs update-service --desired-count N`.
- **`supplier-projection`, `contract-count-projection`, `email-dispatch`** rodam com
  **1 réplica** — a projeção/dispatch **não é idempotente sob concorrência** hoje. Escalar
  exige cuidado (ou tornar idempotente antes).

### Os dois jobs (`migrate`, `sweeper`) — uma nota importante

Uma Task Definition **não** codifica "one-shot" — isso é **como** ela é executada. Os
jobs **não viram ECS Service** (que manteria N réplicas vivas para sempre). Eles rodam
via **`aws ecs run-task`** (ou um step do pipeline / EventBridge Scheduler):

- **`migrate`** — disparado **antes** de promover os Services em cada deploy (garante o
  invariante do ADR-0003: schema migrado primeiro). Exit `0` = ok, `78` = `MIGRATE_DATABASE_URL`
  ausente, `1` = erro de runtime.
- **`sweeper`** — auto-expire de contratos; agendado **1×/dia** (00:05 America/Sao_Paulo)
  via EventBridge Scheduler chamando `RunTask`. `SWEEP_BATCH_SIZE` controla o lote.

---

## 3. Dimensionamento (cpu/memory) — e o porquê

| Serviço | cpu | memory | Racional |
|---|---|---|---|
| **api** | `512` (0.5 vCPU) | `1024` (1 GB) | Borda HTTP sob carga real (Fastify + 5 pools `mysql2` + S3). É o serviço "maior" e o único com autoscaling (2→6 tasks). |
| **migrate** | `512` | `1024` | Roda as migrations dos **6 módulos** numa tacada; um pouco de folga evita timeouts em DDL pesada. One-shot — custo só no deploy. |
| **email-dispatch** | `256` (0.25 vCPU) | `512` | Worker leve: 2 loops de outbox + envio SMTP. I/O-bound. |
| **outbox-contracts / outbox-partners** | `256` | `512` | Loop de poll + entrega de evento; leve. A vazão vem de **escalar réplicas** (SKIP LOCKED), não de CPU por task. |
| **supplier-projection / contract-count-projection** | `256` | `512` | Projeção de read-model: ler outbox de um módulo, gravar view de outro. Leve, 1 réplica. |
| **sweeper** | `256` | `512` | Job curto: 1 query em lote + UPDATE. One-shot. |

> Combinações **válidas no Fargate** (`256` aceita 512/1024/2048; `512` aceita
> 1024–4096). Estes são **pontos de partida conservadores** — ajustar com base em
> métricas reais (CloudWatch Container Insights). **A confirmar/medir com infra.**

---

## 4. Decisões de credenciais e secrets

- **S3 sem chave estática (API).** O core-api usa credencial **XOR**: se
  `S3_ACCESS_KEY_ID` + `S3_SECRET_ACCESS_KEY` estão ausentes, cai na **provider chain
  do AWS SDK** → assume a **`taskRole`** (IAM Role da task). Por isso a API **não** lista
  `S3_*_KEY` em `secrets`: em prod o acesso ao S3 vem da `erp-prod-api-task` role
  (menos um segredo para rotacionar). `S3_REGION`/`S3_BUCKET` são env não-secretas e
  **obrigatórias** com `CONTRACTS_DRIVER=mysql` (lançam no boot se faltarem).
- **JWT (API).** `AUTH_JWT_PRIVATE_KEY` (assina ES256) **e** `AUTH_JWT_PUBLIC_KEY`
  (verifica) vão em `secrets`. A pública não é tecnicamente sigilosa, mas é um PEM
  multi-linha — guardá-la no Secrets Manager mantém o PEM íntegro e o par junto.
  **Sem elas em prod**, o boot gera um par **efêmero** e os tokens **não sobrevivem a
  restart** (todo mundo é deslogado).
- **SMTP/SES (`email-dispatch`).** `SMTP_HOST=email-smtp.<REGIAO>.amazonaws.com`,
  `SMTP_PORT=587`, `SMTP_SECURE=false` (STARTTLS), `SMTP_USER=<SES_SMTP_USERNAME>` são
  env; só `SMTP_PASS` é secret. `EMAIL_PROVIDER=smtp` força o adapter Nodemailer (ADR-0010).
- **ARNs do Secrets Manager.** Aqui aparecem como
  `arn:aws:secretsmanager:<REGIAO>:<ACCOUNT_ID>:secret:erp/prod/<NOME>`. ARNs **reais**
  têm um sufixo aleatório de 6 chars (`-AbCdEf`) — a infra preenche no momento de versionar.

---

## 5. Como usar (resumo operacional)

```bash
# Registrar uma revisão (exemplo; a infra normalmente faz via CodeDeploy/CodePipeline)
aws ecs register-task-definition \
  --cli-input-json file://taskdefs/api.taskdef.json \
  --region <REGIAO>

# Atualizar o Service para a nova revisão (rolling) — workers
aws ecs update-service --cluster erp-prod \
  --service outbox-contracts --task-definition erp-prod-outbox-contracts --region <REGIAO>

# Rodar o job migrate (one-shot) ANTES de promover os Services
aws ecs run-task --cluster erp-prod --launch-type FARGATE \
  --task-definition erp-prod-migrate \
  --network-configuration 'awsvpcConfiguration={subnets=[<subnet-priv>],securityGroups=[<sg-ecs>]}' \
  --region <REGIAO>
```

No fluxo normal **ninguém roda isso à mão**: o **CodePipeline → CodeBuild → CodeDeploy**
registra cada taskdef e atualiza o Service correspondente. Ver o passo a passo em
[`ci-cd-pipeline.md`](../../docs/runbooks/ci-cd-pipeline.md) e a operação (rollback,
troubleshooting) em [`deploy-and-operations.md`](../../docs/runbooks/deploy-and-operations.md) §5.

---

## 6. Referências

- [`ADR-0003 — Produção AWS ECS`](../../docs/adr/0003-producao-aws-ecs.md) — a decisão e a tabela de tradução `compose.yaml` → ECS.
- [`aws-ecs-architecture-by-layer.md`](../../docs/runbooks/aws-ecs-architecture-by-layer.md) — a infra de prod camada a camada (VPC, RDS, Secrets, ECS, ELB, CloudWatch).
- [`ci-cd-pipeline.md`](../../docs/runbooks/ci-cd-pipeline.md) — como a imagem vai do `git push` ao ECS (CodePipeline/CodeBuild/CodeDeploy) e como os workers reusam a imagem.
- [`env-and-secrets.reference.yaml`](../../docs/env-and-secrets.reference.yaml) — catálogo verificado de env/secrets (a fonte usada para montar `environment`/`secrets`).
- [`core-api/compose.yaml`](../../../core-api/compose.yaml) · [`core-api/Dockerfile`](../../../core-api/Dockerfile) — a planta traduzida.
- [`platform/README.md`](../README.md) — estado geral da IaC (QA Magalu via OpenTofu; ECS mantido pela infra).

> **Valores reais a confirmar com infra.** Conta AWS, região, ARNs (roles e secrets),
> nome do cluster, bucket S3, usuário SMTP do SES, CIDR do ELB e domínio do front são
> placeholders neste diretório.
