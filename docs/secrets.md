[← Voltar para `docs/`](README.md)

# 🔐 Catálogo de Secrets

> **Status:** 🔵 PLANEJADA — sincronizada com [handbook infrastructure/03-secrets-catalog.md](https://github.com/ERP-Bem-Comum). Time de Infra: atualize quando os slots forem provisionados no Secrets Manager.

> ⚠️ **Este arquivo lista NOMES e PROPÓSITOS de secrets, NUNCA valores.** Qualquer PR contendo valor real é bloqueado pelo secret scanning da org.

---

## 1. Ferramenta de Secrets Manager

🔵 **A definir** pelo time de infra. Candidatas:

- AWS Secrets Manager
- Google Secret Manager
- HashiCorp Vault
- Doppler (SaaS)

Critério para escolha: integração com o cloud provider escolhido + suporte a rotação automática + audit log + custo.

---

## 2. Slots por categoria

### 2.1. Banco de dados

| Nome do slot | Propósito | Quem lê | Rotação |
|---|---|---|---|
| `DATABASE_URL_LEGACY` | Conexão `legacy-api` ao database `legacy` (user `legacy_app`) | `legacy-api` | trimestral |
| `DATABASE_URL_CORE` | Conexão `core-api` ao database `core` (user `core_app`) | `core-api` | trimestral |
| `DATABASE_URL_READONLY` | Conexão read-only (user `readonly_bi`) para BI/analytics | BI / ferramentas analytics | semestral |

Formato esperado: `mysql://user:password@host:3306/database?ssl-mode=REQUIRED`

### 2.2. Integração Bradesco

| Nome do slot | Propósito | Quem lê | Rotação |
|---|---|---|---|
| `BRADESCO_API_KEY` | Chave de API | `core-api` | conforme banco exigir |
| `BRADESCO_API_SECRET` | Secret correspondente | `core-api` | conforme banco exigir |
| `BRADESCO_CERT_PEM` | Certificado cliente para mTLS | `core-api` | conforme validade (anual) |
| `BRADESCO_CERT_KEY` | Chave privada do certificado | `core-api` | conforme validade |
| `BRADESCO_VAN_HOST` | Host(s) da VAN para egress | `core-api` | quando banco trocar |
| `BRADESCO_BENEFICIARIO_CONFIG` | Configuração do beneficiário (agência, conta, convênio) | `core-api` | quando trocar |

### 2.3. Autenticação e sessão

| Nome do slot | Propósito | Quem lê | Rotação |
|---|---|---|---|
| `JWT_SIGNING_KEY` | Chave para assinar JWTs | `bff-gateway` | trimestral |
| `SESSION_SECRET` | Chave para HMAC de sessões | `bff-gateway` | trimestral |
| `OIDC_CLIENT_ID` | Cliente OIDC (Zitadel ou equivalente) | `bff-gateway` | conforme IdP |
| `OIDC_CLIENT_SECRET` | Secret correspondente | `bff-gateway` | trimestral |

### 2.4. Integrações externas (futuras)

| Nome do slot | Propósito | Quem lê | Rotação |
|---|---|---|---|
| `OCR_PROVIDER_KEY` | Chave do provedor OCR | `core-api` | quando contratado |

---

## 3. Convenções de nomeação

- **Nomes em UPPER_SNAKE_CASE**
- **Prefixo por domínio**: `DATABASE_*`, `BRADESCO_*`, `OCR_*`, etc.
- **Sufixo por papel**: `_KEY`, `_SECRET`, `_TOKEN`, `_URL`, `_HOST`
- **Mesmo nome em todos os ambientes** (dev/staging/prod) — só o VALOR varia. Isso simplifica o código: `process.env.DATABASE_URL_CORE` funciona igual em qualquer lugar.

---

## 4. Por ambiente

| Slot | dev | staging | prod |
|---|---|---|---|
| `DATABASE_URL_*` | local Docker | managed staging | managed prod |
| `BRADESCO_*` | **sandbox/teste do banco** | **sandbox/teste do banco** | **produção do banco** |
| `JWT_SIGNING_KEY` | ephemeral | dedicado | dedicado, rotacionado |
| Demais | dedicado por ambiente | dedicado por ambiente | dedicado por ambiente |

> ⚠️ **Nunca usar secrets de prod em dev ou staging.** Auditoria depende dessa separação.

---

## 5. Como secrets chegam aos serviços

```mermaid
flowchart LR
    SM["🔐 Secrets Manager<br/>(escolha do infra)"] -->|"fetch on startup<br/>via IAM/service account"| BFF
    SM --> LEGACY
    SM --> CORE

    BFF["bff-gateway<br/>(env vars em runtime)"]
    LEGACY["legacy-api<br/>(env vars em runtime)"]
    CORE["core-api<br/>(env vars em runtime)"]

    classDef sm fill:#fde68a,stroke:#d97706,color:#78350f
    classDef svc fill:#dcfce7,stroke:#16a34a,color:#14532d
    class SM sm
    class BFF,LEGACY,CORE svc
```

Padrões aceitáveis:

- **Injeção em env vars no startup** via plugin do orquestrador (k8s External Secrets, ECS Task Definitions com Secrets Manager, etc.)
- **Sidecar de mount** (k8s CSI driver)
- **SDK em runtime** (último recurso — adiciona complexidade no app)

Padrões **proibidos**:

- ❌ Secrets no Docker image
- ❌ Secrets em variáveis do GitHub Actions sem proteção
- ❌ Secrets em arquivos commitados (mesmo `.env`)

---

## 6. Rotação

| Tipo | Frequência mínima | Em caso de comprometimento |
|---|---|---|
| Senhas de DB | Trimestral | Imediata |
| JWT signing keys | Trimestral | Imediata + invalidação de sessões |
| Bradesco | Conforme contrato | Conforme contrato + comunicação ao banco |
| Certificados | Conforme validade | Imediata |
| OIDC client secrets | Trimestral | Imediata |

Procedimento de rotação detalhado: 🔵 a definir pela infra + security.

---

## 7. Para o dev local

Veja [`../local/.env.example`](../local/.env.example) — todos os slots têm um valor de exemplo seguro para desenvolvimento local. **Nenhum valor de exemplo é compatível com qualquer ambiente real**, por design.

---

## 8. Referências

- [`topology.md`](topology.md) — onde cada secret é consumido
- [`environments.md`](environments.md) — separação entre ambientes
- Handbook `infrastructure/03-secrets-catalog.md` — fonte canônica
- [`../platform/README.md`](../platform/README.md) — IaC do Secrets Manager (a preencher)
