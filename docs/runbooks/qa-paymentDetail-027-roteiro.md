# Roteiro de QA (v2 — corrigido) — `paymentDetail` (#273) + dados migrados

**Ambiente:** VM de validação (incus/x99) — core-api `027-fin-document-payment-detail` + web-app `develop` + MySQL com dump de prod migrado.
**Financial:** agora ligado ao **MySQL** (`FINANCIAL_DRIVER=mysql`) — documentos persistem no banco real.

> ❗ **Correções vs. a 1ª versão deste roteiro:**
> - O endpoint é **`/api/v2/financial/documents`** (a 1ª versão dizia `/api/v1` por engano — `/api/v1/financial/documents` **não existe**, dá 404).
> - O **front `develop` NÃO tem o campo `paymentDetail`** (a UI dele virá em `feat/contas-a-pagar-026`). Por isso o `paymentDetail` **só deve ser testado via API (Swagger)**, não pela tela de Lançar Documento.
> - O **Swagger** exige **aceitar o certificado** antes (ver passo 0).

---

## 0. Acesso

- **Front:** `https://app.localhost:8443` · **Swagger (API):** `https://api.localhost:8443/docs`
- **Aceitar o certificado (uma vez, ANTES do Swagger):** abrir `https://api.localhost:8443/` → **Avançado → Prosseguir** (CA interna do Caddy). Repetir para `https://app.localhost:8443/`.

**Credenciais:**

| Usuário | Senha | Para quê |
|---|---|---|
| `admin@bemcomum.dev` | `DevPassw0rd!2024` | Listagens (usuários/colaboradores/fornecedores) |
| `e2e-fin@bemcomum.dev` | `DevPassw0rd!2024` | **Criar documento financeiro** (permissão `fiscal-document`) |

---

## CT-01 — Login (UI) ✅
Logar com cada usuário → entra sem erro.

## CT-02 — Dados migrados (UI)
- `/usuarios` → **14 usuários** (e-mails reais: `nathaliamenezes@abemcomum.org`...). ⚠️ Campo **nome aparece "—"** — é o **bug conhecido [#277](https://github.com/ERP-Bem-Comum/core-api/issues/277)** (ETL não popula o nome do usuário), **não** é falha desta tela.
- **Colaboradores** → nomes completos ("Adriano Silva Lima"...).
- **Fornecedores** → razão social + CNPJ.
- ⚠️ Lista vazia ao abrir? **Relogar + hard refresh** (token/cache efêmero).

## CT-03 — `paymentDetail` no documento (via Swagger) — núcleo da #273
> Tudo em `https://api.localhost:8443/docs` (cert aceito no passo 0).

1. **Login:** `POST /api/v2/auth/login` body `{"email":"e2e-fin@bemcomum.dev","password":"DevPassw0rd!2024"}` → copiar `accessToken` → botão **Authorize** (topo) → colar `Bearer <token>`.
2. **Fornecedor:** usar `supplierRef = 2891bf72-b6ee-4506-9be0-72c41f5327a9` (fornecedor migrado) ou outro id da tela Fornecedores.
3. **Criar:** `POST /api/v2/financial/documents` (⚠️ **v2**):
   ```json
   {
     "type": "NFS-e", "documentNumber": "QA-PD-001",
     "supplierRef": "2891bf72-b6ee-4506-9be0-72c41f5327a9",
     "paymentMethod": "Boleto", "grossValueCents": "150000",
     "dueDate": "2026-12-31",
     "paymentDetail": "23793.38003 12345.678901 23456.789012 3 98760000012345",
     "retentions": [], "registeredTaxes": []
   }
   ```
   → **Esperado: 201** (`status: Open`); anotar o `id`.
4. **Detalhe:** `GET /api/v2/financial/documents/{id}` → **Esperado:** `paymentDetail` **idêntico** ao enviado.

## CT-04 — Validações de borda (devem dar **400**) — em `/api/v2`
Repetir o `POST /api/v2/financial/documents` variando só o `paymentDetail`:

| # | `paymentDetail` | Esperado |
|---|---|---|
| a | `""` | **400** |
| b | `"   "` | **400** |
| c | `"linha\ncom\nquebra"` | **400** |
| d | 256+ caracteres | **400** |
| e | **omitir** o campo | **201** (criado sem `paymentDetail`) |

## CT-05 — Detail-only — em `/api/v2`
`GET /api/v2/financial/documents` (lista) → itens **sem** `paymentDetail` (só no detalhe `/{id}`).

## CT-06 — UI "Lançar Documento" → **N/A**
O `develop` não tem o campo de complemento (estaria em `feat/contas-a-pagar-026`). `paymentDetail` é validado por CT-03/04/05 (API).

---

## Known issues do ambiente (não bloqueiam a #273)
| Achado | Issue |
|---|---|
| usuários migrados com `name`/nome = null → "—" | [#277](https://github.com/ERP-Bem-Comum/core-api/issues/277) |
| `food_category` curto → 5 colaboradores não migrados | [#274](https://github.com/ERP-Bem-Comum/core-api/issues/274) |
| 83% suppliers em quarentena (docs inválidos no legado) | [#275](https://github.com/ERP-Bem-Comum/core-api/issues/275) |
| lista vazia após restart do backend | ambiente (relogar + hard refresh) |

## Resultado esperado da #273 (referência)
Validado pelo dev no MySQL real: `POST /api/v2 → 201`, `GET detalhe → paymentDetail idêntico`, bordas `→ 400`, ausente na listagem, e **persistido em `fin_documents.payment_detail`** (confirmado: `com_payment_detail = 1`).
