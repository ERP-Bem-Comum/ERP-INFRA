[← Voltar para `docs/`](README.md)

# 🏗️ Topologia do Sistema

> **Status:** PLANEJADA (alvo de produção) — esta é a topologia decidida em ADRs do handbook. Descreve o **alvo de produção** (alta disponibilidade), não o que sobe no dev local (isso fica em [`../local/README.md`](../local/README.md)). Confirmar com o time de infra se a infra REAL provisionada já reflete este desenho. Atualizar quando divergir.
>
> ✅ **A produção já roda neste alvo de HA — em AWS ECS.** Ver [`adr/0003-producao-aws-ecs.md`](adr/0003-producao-aws-ecs.md). A infra **traduz o `compose.yaml` do core-api** em ECS: a **API** fica atrás do **ELB** (substitui o Caddy/edge como borda), com **múltiplas réplicas**; o banco é **RDS** (MySQL gerenciado, não no mesmo host); os segredos vivem no **Secrets Manager**; e-mail via **Amazon SES (SMTP)**. Os 5 workers do profile `workers` são ECS Services **sem ELB**. O baseline econômico single-node em **AWS Lightsail** ([`ADR-0002`](adr/0002-producao-economica-aws-lightsail.md)) foi **descartado**. Os ambientes econômicos (`qa` na Magalu, `x99` no homelab) seguem single-node com Caddy + Docker Compose. A imagem do `web-app` é **distroless non-root** (web-app ADR-0015) e expõe `/health` + `/ready`.
>
> **Fontes-fonte da decisão:** [handbook architecture/02-system-topology.md](https://github.com/ERP-Bem-Comum) e [handbook infrastructure/01-infra-handoff.md](https://github.com/ERP-Bem-Comum).

---

## 1. Visão de componentes (planejada)

```mermaid
flowchart TB
    Internet(("🌐 Internet"))
    Internet --> LB

    subgraph PUB["Barramento público — HTTPS :443 (TLS + WAF) · expõe web-app E core-api"]
        LB["⚖️ Load Balancer<br/>TLS + WAF (regras OWASP)"]
        WEB["🚪 web-app<br/>TanStack Start (Node 24 · Nitro)<br/>Front (SSR) + BFF no mesmo processo<br/>Stateless · ≥2 réplicas<br/>512 MB / 0.5 vCPU"]
        LB --> WEB
    end

    LB -- "HTTPS :443<br/>/api/* — core-api TAMBÉM é público no barramento" --> CORE
    WEB -- "server functions (BFF)<br/>/api/v2/* via HTTP interno" --> CORE

    subgraph INT["Aplicação — subnets privadas (tasks rodam atrás do LB)"]
        CORE["⭐ core-api<br/>Node 24 LTS · Fastify<br/>Modular Monolith<br/>Exposto via LB (HTTPS) + chamado pelo BFF<br/>Stateless · ≥2 réplicas<br/>1 GB / 0.5 vCPU"]
    end

    CORE --> DB
    CORE --> OBJ
    MIG["📦 job de importação<br/>(one-shot / batch)<br/>carrega dump do ERP antigo"] --> DB

    subgraph DBLAYER["MySQL 8.4 LTS managed (RDS / Cloud SQL) · Multi-AZ · PITR"]
        direction LR
        DB[(MySQL 8.4)]
        COREDB[("database core<br/>user: core_app<br/>GRANT em core.*")]
        LEGACYDB[("database legacy<br/>dados importados do ERP antigo<br/>sem serviço em runtime")]
        BIDB[("read-only BI<br/>user: readonly_bi<br/>SELECT em ambos")]
        DB --- COREDB
        DB --- LEGACYDB
        DB --- BIDB
    end

    OBJ[("🗄️ Object Storage<br/>S3-compatible<br/>(MinIO em dev · S3/GCS em prod)")]

    CORE -- "egress whitelist" --> VAN["🏦 VAN Bradesco<br/>(CNAB / OFX)"]
    CORE -- "egress whitelist" --> OCR["📄 Provider OCR<br/>(futuro)"]

    classDef external fill:#fee2e2,stroke:#dc2626,color:#7f1d1d
    classDef public fill:#dbeafe,stroke:#2563eb,color:#1e3a8a
    classDef internal fill:#dcfce7,stroke:#16a34a,color:#14532d
    classDef storage fill:#fef3c7,stroke:#d97706,color:#78350f
    classDef batch fill:#ede9fe,stroke:#7c3aed,color:#4c1d95

    class Internet,VAN,OCR external
    class LB,WEB public
    class CORE internal
    class DB,COREDB,LEGACYDB,BIDB,OBJ storage
    class MIG batch
```

### Princípios invioláveis

1. **O BFF (web-app, server-side) nunca toca em DB.** Ele só conhece HTTP: serve o front (SSR) e, via server functions, chama o `core-api`. O browser nunca fala com o `core-api` direto.
2. **Só o `core-api` escreve em runtime, e só no database `core`.** O database `legacy` guarda os dados importados do ERP antigo; **nenhum serviço o serve via API em runtime** — é fonte histórica / BI, populada por job de importação.
3. **Isolamento por GRANT de usuário é inegociável.** `core_app` só enxerga `core.*`; `readonly_bi` só faz `SELECT`. O carregamento de `legacy.*` usa um usuário de importação dedicado, ativo **apenas** durante a migração.
4. **Sem joins cross-database em runtime.** Se o `core-api` precisa de dado do legado, lê via projeção mantida no próprio `core.*` (materializada na importação), nunca com `JOIN legacy.x`.
5. **Comunicação com sistemas externos é via outbox.** Efeitos colaterais para fora (VAN/CNAB, OCR) saem por entrega assíncrona confiável (outbox + worker), não no caminho síncrono da request.

> 📌 **Mudança vs. desenho anterior:** não há mais `bff-gateway` como serviço separado (o BFF é o próprio `web-app`/TanStack Start) nem `legacy-api` rodando (o legado é o frontend congelado `web-app-legacy` + os **dados** importados no database `legacy`). O outbox deixou de ser canal cross-BC `legacy ↔ core` e passou a ser o canal de **egress** do `core-api` para sistemas externos.

---

## 1·A. Produção em AWS ECS — alvo provisionado (🟢)

> O diagrama de §1 é a **visão de componentes** (lógica: quem fala com quem). O
> diagrama abaixo é a **materialização em AWS ECS** dessa visão — como a prod
> realmente é montada (ELB + tasks ECS + RDS + Secrets Manager + SES + CloudWatch),
> traduzindo o [`compose.yaml`](../../core-api/compose.yaml) do core-api conforme
> [`ADR-0003`](adr/0003-producao-aws-ecs.md).
>
> 📘 **Guia didático camada por camada (com exemplos de código por camada — HCL +
> JSON):** [`runbooks/aws-ecs-architecture-by-layer.md`](runbooks/aws-ecs-architecture-by-layer.md).

```mermaid
flowchart TB
    Internet(("🌐 Internet"))

    subgraph VPCNET["🛡️ VPC — região &lt;REGIAO&gt; (a confirmar com infra)"]
        subgraph PUBNET["Subnets PÚBLICAS (≥2 AZs)"]
            ELB["⚖️ ELB / ALB<br/>HTTPS :443 (cert ACM)<br/>termina TLS · health /health"]
            NATGW["🔀 NAT Gateway"]
        end
        subgraph PRIVNET["Subnets PRIVADAS (≥2 AZs)"]
            subgraph ECSCL["ECS Cluster (Fargate)"]
                APISVC["🟢 ECS Service: api (http)<br/>N tasks · :3000 · atrás do ELB<br/>ENTRYPOINT node src/server.ts"]
                WKSVC["⚙️ 5 ECS Services: workers (sem ELB)<br/>outbox-contracts · outbox-partners<br/>supplier-projection · contract-count-projection<br/>email-dispatch"]
            end
            RDS[("🗄️ RDS MySQL 8.4<br/>Multi-AZ · :3306 · database core")]
        end
    end

    SM["🔐 Secrets Manager<br/>*_DATABASE_URL · AUTH_JWT_* · smtp_pass"]
    SES["📧 Amazon SES (SMTP)<br/>email-smtp.&lt;REGIAO&gt;.amazonaws.com"]
    ECR["📦 ECR<br/>core-api :sha-&lt;commit&gt;"]
    CW["📊 CloudWatch Logs<br/>1 log group por service"]

    Internet --> ELB
    ELB -->|":3000 (SG ELB→ECS)"| APISVC
    APISVC -->|":3306 (SG ECS→RDS)"| RDS
    WKSVC -->|":3306"| RDS
    WKSVC -->|"SMTP :587 via NAT"| SES
    APISVC -. "valueFrom no boot" .-> SM
    WKSVC -. "valueFrom no boot" .-> SM
    ECSCL -. "docker pull" .-> ECR
    APISVC -. awslogs .-> CW
    WKSVC -. awslogs .-> CW

    classDef edge fill:#dbeafe,stroke:#2563eb,color:#1e3a8a
    classDef compute fill:#dcfce7,stroke:#16a34a,color:#14532d
    classDef data fill:#fef3c7,stroke:#d97706,color:#78350f
    classDef managed fill:#ede9fe,stroke:#7c3aed,color:#4c1d95
    class ELB,NATGW edge
    class APISVC,WKSVC compute
    class RDS data
    class SM,SES,ECR,CW managed
```

**Tradução planta → ECS (ADR-0003):** cada `service` do `compose.yaml` vira
**1 Task Definition + 1 ECS Service** (mesma imagem do ECR, `command` sobrescrito).
A **API** (`http`) fica atrás do **ELB**; os **5 workers** do profile `workers` são
ECS Services **sem ELB**. `mysql`→**RDS**, `edge`/Caddy→**ELB**,
arquivos `secrets/*.txt`→**Secrets Manager**, `minio`→**S3**, e-mail→**Amazon SES (SMTP)**.
Detalhes (conta, região, ARNs, cluster) **a confirmar com o time de infra**.

---

## 2. Fluxo: leitura em tela nova

```mermaid
sequenceDiagram
    autonumber
    participant B as Browser
    participant LB as Load Balancer
    participant WEB as web-app (BFF/SSR)
    participant CORE as core-api
    participant DB as MySQL (core)

    B->>LB: GET /documentos/123 (navegação)
    LB->>WEB: GET /documentos/123<br/>(TLS terminated)
    WEB->>WEB: auth de sessão, rate limit, X-Request-Id
    WEB->>CORE: GET /api/v2/documentos/123<br/>(server function → HTTP interno)
    CORE->>DB: SELECT FROM core.documentos<br/>WHERE id = 123
    DB-->>CORE: row
    CORE-->>WEB: 200 JSON
    WEB-->>LB: 200 HTML/JSON (SSR ou fetch do cliente)
    LB-->>B: 200
```

---

## 3. Fluxo: escrita com efeito em sistema externo (egress confiável)

```mermaid
sequenceDiagram
    autonumber
    participant B as Browser
    participant WEB as web-app (BFF)
    participant CORE as core-api
    participant CDB as MySQL (core)
    participant W as Outbox Worker
    participant VAN as VAN Bradesco

    B->>WEB: POST /cnab/remessa
    WEB->>CORE: POST /api/v2/cnab/remessa<br/>(server function)
    CORE->>CDB: BEGIN TRANSACTION
    CORE->>CDB: INSERT INTO core.remessa_cnab
    CORE->>CDB: INSERT INTO core.outbox<br/>(event_type='RemessaCnabGerada')
    CORE->>CDB: COMMIT
    CORE-->>WEB: 201 Created
    WEB-->>B: 201 Created

    Note over W: assíncrono
    W->>CDB: SELECT outbox WHERE processed_at IS NULL
    CDB-->>W: evento RemessaCnabGerada
    W->>VAN: entrega (CNAB / OFX, egress whitelist)
    VAN-->>W: ACK
    W->>CDB: UPDATE outbox SET processed_at=NOW()
```

> O outbox garante que o efeito externo acontece **exatamente uma vez** mesmo se a VAN estiver fora: o evento fica empilhado até a entrega confirmar. A request do usuário não espera o egress.

---

## 4. Banco de dados — estrutura de isolamento

```mermaid
flowchart LR
    subgraph MYSQL["MySQL 8.4 LTS · Multi-AZ · PITR · binlog"]
        direction TB

        subgraph CORE_DB[database: core]
            T2[tabelas fin_*<br/>módulo Financeiro]
            T3[tabelas ctr_*<br/>módulo Contratos]
            T4[tabela outbox<br/>egress para sistemas externos]
        end

        subgraph LEGACY_DB[database: legacy]
            T1[tabelas legacy<br/>carga do dump do ERP antigo<br/>histórico / BI — sem serviço em runtime]
        end
    end

    UAPP2["user: core_app<br/>GRANT ALL ON core.*"] --> CORE_DB
    UMIG["user: legacy_loader<br/>GRANT ALL ON legacy.*<br/>(ativo só na importação)"] --> LEGACY_DB
    UBI["user: readonly_bi<br/>SELECT em ambos"] --> CORE_DB
    UBI --> LEGACY_DB

    classDef user fill:#e0e7ff,stroke:#4f46e5,color:#312e81
    class UAPP2,UMIG,UBI user
```

> ⚠️ **O isolamento por GRANT de usuário é a única coisa que impede um dev/serviço de violar a regra de domínio. Não negocie.** O `core-api` se conecta como `core_app` e, por permissão negada do MySQL, **não consegue** tocar em `legacy.*` — nem por engano, nem de propósito. O acesso de leitura ao legado (BI, conferência de migração) passa por `readonly_bi`.

Detalhes em [handbook architecture/03-data-architecture.md](https://github.com/ERP-Bem-Comum) e ADR-0014.

---

## 5. Egress / conectividade externa

| Origem | Destino | Porta | Propósito | Status |
|---|---|---|---|---|
| `core-api` | VAN Bradesco | a confirmar | CNAB / OFX (via outbox) | 🔵 planejado |
| `core-api` | Provider OCR | a definir | Processamento de documentos | 🔵 planejado (provedor a contratar) |
| `core-api` | Object Storage (S3-compat) | 443 | Anexos / documentos | 🔵 planejado (MinIO em dev) |
| Todos | Secrets Manager | 443 | Leitura de credenciais | 🔵 planejado |
| Todos | Coletor de logs/métricas | 443 | Observabilidade | 🔵 planejado |

🔵 = planejado · 🟢 = provisionado e validado · 🔴 = divergência conhecida

> **Time de Infra**: por favor atualizem a coluna Status quando provisionarem cada rota.

---

## 6. Mudanças nesta topologia

Mudanças nesta página exigem:

1. PR em `ERP-INFRA` com diff do Mermaid e descrição do "porquê"
2. Aprovação de **1 dev sênior + 1 líder de infra** (ver [`CODEOWNERS`](../CODEOWNERS))
3. Se a mudança vier de uma decisão arquitetural maior, criar uma ADR em [`docs/adr/`](adr/) **antes** ou **junto** ao PR

---

## 7. Referências

- [`environments.md`](environments.md) — diferenças entre dev / staging / prod
- [`secrets.md`](secrets.md) — catálogo de secrets que esta topologia consome
- [`observability.md`](observability.md) — onde olhar quando algo quebra
- [`runbooks/aws-ecs-architecture-by-layer.md`](runbooks/aws-ecs-architecture-by-layer.md) — **guia didático da arquitetura de prod AWS ECS, camada por camada** (VPC · RDS · Secrets Manager · ECS · ELB · CloudWatch), com exemplos de código (HCL + JSON) por camada
- [`adr/0003-producao-aws-ecs.md`](adr/0003-producao-aws-ecs.md) — decisão de produção em AWS ECS
- [`adr/`](adr/) — decisões arquiteturais específicas deste repo
- Handbook arquitetural — fonte canônica das decisões originais (`ADR-0005`, `ADR-0006`, `ADR-0013`, `ADR-0014` referenciados acima)
