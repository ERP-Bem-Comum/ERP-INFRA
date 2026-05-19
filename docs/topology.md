[← Voltar para `docs/`](README.md)

# 🏗️ Topologia do Sistema

> **Status:** PLANEJADA — esta é a topologia decidida em ADRs do handbook. Confirmar com o time de infra se a infra REAL provisionada já reflete este desenho. Atualizar quando divergir.
>
> **Fontes-fonte da decisão:** [handbook architecture/02-system-topology.md](https://github.com/ERP-Bem-Comum) e [handbook infrastructure/01-infra-handoff.md](https://github.com/ERP-Bem-Comum).

---

## 1. Visão de componentes (planejada)

```mermaid
flowchart TB
    Internet(("🌐 Internet"))
    Internet --> LB

    subgraph PUB["Camada pública (única exposição externa)"]
        LB["⚖️ Load Balancer<br/>TLS + WAF (regras OWASP)"]
        BFF["🚪 bff-gateway<br/>Node 20 · Hono/Fastify<br/>Stateless · ≥2 réplicas<br/>256 MB / 0.25 vCPU"]
        LB --> BFF
    end

    BFF -- "/api/v1/*" --> LEGACY
    BFF -- "/api/v2/*" --> CORE

    subgraph INT["Camada interna (VPC privada)"]
        direction LR
        LEGACY["📜 legacy-api<br/>NestJS · existente<br/>Stateless · ≥2 réplicas"]
        CORE["⭐ core-api<br/>Node 24 LTS · Fastify<br/>Modular Monolith<br/>Stateless · ≥2 réplicas<br/>512 MB / 0.5 vCPU"]
        LEGACY -.-> |"eventos via outbox"| CORE
        CORE -.-> |"eventos via outbox"| LEGACY
    end

    LEGACY --> DB
    CORE --> DB

    subgraph DBLAYER["MySQL 8.4 LTS managed (RDS / Cloud SQL) · Multi-AZ · PITR"]
        direction LR
        DB[(MySQL 8.4)]
        LEGACYDB[("database legacy<br/>user: legacy_app<br/>GRANT em legacy.*")]
        COREDB[("database core<br/>user: core_app<br/>GRANT em core.*")]
        BIDB[("read-only BI<br/>user: readonly_bi<br/>SELECT em ambos")]
        DB --- LEGACYDB
        DB --- COREDB
        DB --- BIDB
    end

    CORE -- "egress whitelist" --> VAN["🏦 VAN Bradesco<br/>(CNAB / OFX)"]
    CORE -- "egress whitelist" --> OCR["📄 Provider OCR<br/>(futuro)"]

    classDef external fill:#fee2e2,stroke:#dc2626,color:#7f1d1d
    classDef public fill:#dbeafe,stroke:#2563eb,color:#1e3a8a
    classDef internal fill:#dcfce7,stroke:#16a34a,color:#14532d
    classDef storage fill:#fef3c7,stroke:#d97706,color:#78350f

    class Internet,VAN,OCR external
    class LB,BFF public
    class LEGACY,CORE internal
    class DB,LEGACYDB,COREDB,BIDB storage
```

### Princípios invioláveis

1. **BFF nunca toca em DB.** Ele só conhece HTTP.
2. **Cada serviço escreve só no próprio database.** `core-api` em `core.*`, `legacy-api` em `legacy.*`. Sem exceções.
3. **Toda comunicação cross-BC é via evento (outbox).** Sem chamada HTTP síncrona entre `legacy-api` e `core-api`.
4. **Sem joins cross-database entre serviços.** Se precisa de dado do outro, lê via API ou via projeção mantida no próprio database.
5. **Falha de um serviço não derruba o outro.** Eventos ficam empilhados na outbox até voltar.

---

## 2. Fluxo: leitura em tela nova

```mermaid
sequenceDiagram
    autonumber
    participant B as Browser
    participant LB as Load Balancer
    participant BFF as bff-gateway
    participant CORE as core-api
    participant DB as MySQL (core)

    B->>LB: GET /api/v2/documentos/123
    LB->>BFF: GET /api/v2/documentos/123<br/>(TLS terminated)
    BFF->>BFF: auth, rate limit, X-Request-Id
    BFF->>CORE: GET /api/v2/documentos/123
    CORE->>DB: SELECT FROM core.documentos<br/>WHERE id = 123
    DB-->>CORE: row
    CORE-->>BFF: 200 JSON
    BFF-->>LB: 200 JSON
    LB-->>B: 200 JSON
```

---

## 3. Fluxo: escrita com efeito cross-bounded-context

```mermaid
sequenceDiagram
    autonumber
    participant B as Browser
    participant BFF as bff-gateway
    participant CORE as core-api
    participant CDB as MySQL (core)
    participant W as Outbox Worker
    participant LEG as legacy-api
    participant LDB as MySQL (legacy)

    B->>BFF: POST /api/v2/cnab/remessa
    BFF->>CORE: POST /api/v2/cnab/remessa
    CORE->>CDB: BEGIN TRANSACTION
    CORE->>CDB: INSERT INTO core.remessa_cnab
    CORE->>CDB: INSERT INTO core.outbox<br/>(event_type='RemessaCnabGerada')
    CORE->>CDB: COMMIT
    CORE-->>BFF: 201 Created
    BFF-->>B: 201 Created

    Note over W: assíncrono
    W->>CDB: SELECT outbox WHERE processed_at IS NULL
    CDB-->>W: evento RemessaCnabGerada
    W->>LEG: deliver event
    LEG->>LDB: reage no próprio legacy.*
    LEG-->>W: ACK
    W->>CDB: UPDATE outbox SET processed_at=NOW()
```

---

## 4. Banco de dados — estrutura de isolamento

```mermaid
flowchart LR
    subgraph MYSQL["MySQL 8.4 LTS · Multi-AZ · PITR · binlog"]
        direction TB

        subgraph LEGACY_DB[database: legacy]
            T1[tabelas legacy<br/>(carga inicial do dump)]
        end

        subgraph CORE_DB[database: core]
            T2[tabelas fin_*<br/>módulo Financeiro]
            T3[tabelas ctr_*<br/>módulo Contratos]
            T4[tabela outbox]
        end
    end

    UAPP1["user: legacy_app<br/>GRANT ALL ON legacy.*"] --> LEGACY_DB
    UAPP2["user: core_app<br/>GRANT ALL ON core.*"] --> CORE_DB
    UBI["user: readonly_bi<br/>SELECT em ambos"] --> LEGACY_DB
    UBI --> CORE_DB

    classDef user fill:#e0e7ff,stroke:#4f46e5,color:#312e81
    class UAPP1,UAPP2,UBI user
```

> ⚠️ **O isolamento por GRANT de usuário é a única coisa que impede um dev de violar a regra de domínio. Não negocie.** O sistema operacional não tem como detectar `JOIN legacy.x` em queries do `core-api` — só o MySQL, via permissão negada.

Detalhes em [handbook architecture/03-data-architecture.md](https://github.com/ERP-Bem-Comum) e ADR-0014.

---

## 5. Egress / conectividade externa

| Origem | Destino | Porta | Propósito | Status |
|---|---|---|---|---|
| `core-api` | VAN Bradesco | a confirmar | CNAB / OFX | 🔵 planejado |
| `core-api` | Provider OCR | a definir | Processamento de documentos | 🔵 planejado (provedor a contratar) |
| `legacy-api` | (o que já consome hoje) | — | Manter funcionamento legado | 🔵 herdado |
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
- [`adr/`](adr/) — decisões arquiteturais específicas deste repo
- Handbook arquitetural — fonte canônica das decisões originais (`ADR-0005`, `ADR-0006`, `ADR-0013`, `ADR-0014` referenciados acima)
