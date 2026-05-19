[← Voltar para `docs/`](../README.md)

# 📜 ADRs — Architecture Decision Records (deste repo)

ADRs registram **decisões arquiteturais** específicas do repo `ERP-INFRA`. Não duplicam as ADRs do handbook (que cobrem decisões do produto inteiro); cobrem apenas decisões sobre **como este repo opera**.

## Índice

| Nº | Título | Status |
|---|---|---|
| [0001](0001-proposito-e-stewardship-do-erp-infra.md) | Propósito e stewardship do repositório `ERP-INFRA` | ✅ Aceita |

## Como adicionar uma ADR

1. Use o próximo número sequencial (zero-padded a 4 dígitos).
2. Nome do arquivo: `NNNN-titulo-em-kebab.md`.
3. Cabeçalho mínimo:
   ```markdown
   # ADR-NNNN — Título

   **Status:** Proposta | Aceita | Superada por ADR-XXXX
   **Data:** YYYY-MM-DD
   **Decisor inicial:** @handle
   **Reviewers obrigatórios:** ...
   ```
4. Seções obrigatórias: Contexto, Decisão, Alternativas consideradas, Consequências.
5. PR com **2 reviewers** (dev sênior + líder de infra), conforme [`../../CONTRIBUTING.md`](../../CONTRIBUTING.md).

## ADRs do handbook (referência)

Decisões maiores do produto vivem no handbook arquitetural (acesso restrito). Algumas das mais relevantes para entender as escolhas deste repo:

- ADR-0001 — Strangler Fig over rewrite
- ADR-0002 — Manter Node.js como runtime
- ADR-0005 — Thin BFF gateway
- ADR-0006 — Modular monolith no core-api
- ADR-0013 — MySQL como engine de banco
- ADR-0014 — Isolamento por database (não por schema)
- ADR-0007 — Multi-cloud AWS + GCP
