# Contribuindo para ERP-INFRA

Este repositório tem uma natureza **dupla**: ele é tanto uma **especificação técnica viva** (consumida por devs que precisam entender a infra) quanto um **espelho da implementação real** (mantido pelo time de infra). Por isso, as regras de contribuição aqui são mais conservadoras do que em repos de aplicação.

Para o padrão geral da organização, veja [`ERP-Bem-Comum/.github/CONTRIBUTING.md`](https://github.com/ERP-Bem-Comum/.github/blob/main/CONTRIBUTING.md). Este documento **complementa** aquele com regras específicas deste repo.

---

## Princípios

1. **Verdade > beleza.** Se a infra real diverge da spec, atualize a spec antes do próximo deploy — não no próximo. Specs desatualizadas mentem.
2. **Mudança de infra é mudança de contrato.** Toda alteração em `platform/` ou em `docs/topology.md` afeta consumidores (devs, CI/CD, runtime). Avise no PR.
3. **PRs pequenos.** Evite PRs gigantes que misturam IaC + docs + scripts. Quebre por escopo: um PR muda topologia, outro reflete a topologia na IaC.
4. **Sem segredos commitados.** Nunca. Nem em arquivos de exemplo, nem em variáveis. Veja [`docs/secrets.md`](docs/secrets.md).

---

## Tipos de mudança e quem aprova

| Diretório | Tipo de mudança | Reviewer obrigatório |
|---|---|---|
| `local/` | Docker compose, scripts de dev local | 1 dev sênior |
| `docs/` (exceto `adr/`) | Diagrama de topologia, ambientes, secrets, observabilidade | 1 dev sênior + 1 do time de infra |
| `docs/adr/` | Decisão arquitetural com impacto duradouro | 2 reviewers: 1 dev sênior + 1 líder de infra |
| `platform/` | IaC real (Terraform, Helm, Pulumi, etc.) | 1 líder de infra (via CODEOWNERS) |
| Raiz (README, LICENSE, etc.) | Documentação institucional | 1 dev sênior |

Quem aprova qual diretório está formalizado em [`CODEOWNERS`](CODEOWNERS).

---

## Commits — padrão obrigatório da org

[Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/#summary). Tipos comuns neste repo:

- `feat(local)`: nova capacidade no docker-compose local
- `feat(platform)`: novo recurso de IaC (módulo terraform, chart helm, ...)
- `fix(local)`: correção em scripts locais
- `fix(platform)`: correção em IaC
- `docs(topology)`: atualização do diagrama / texto de topologia
- `docs(secrets)`: catálogo de secrets
- `docs(adr)`: nova ADR ou atualização
- `chore(ci)`: workflows do GitHub Actions
- `refactor(platform)`: reorganização sem mudança de comportamento

Validação automática via [reusable workflow da org](https://github.com/ERP-Bem-Comum/.github/blob/main/.github/workflows/commitlint.yml).

---

## Fluxo de PR

1. **Issue primeiro** (exceto correções triviais). Descreva o "porquê" antes do "o quê".
2. **Branch a partir de `main`** com nome `<tipo>/<descricao-curta>`. Exemplos: `feat/terraform-vpc`, `docs/topology-bradesco-egress`, `fix/compose-mysql-volume`.
3. **PR draft enquanto trabalha**, marca como ready quando CI passar.
4. **Descrição do PR** deve responder:
   - O que mudou?
   - Por quê? (link para issue, ADR, ou incidente)
   - Impacto: quem é afetado? Há mudança de contrato?
   - Como testar? (especialmente para `local/` e `platform/`)
5. **CI verde** antes do review.
6. **Aprovação** conforme tabela acima. Use [`CODEOWNERS`](CODEOWNERS) — o GitHub adiciona reviewers automaticamente.
7. **Squash merge** preferido. O título do PR vira a mensagem de commit final (siga Conventional Commits).
8. **Branch deletada após merge.**

---

## Adicionando uma ADR

Para decisões arquiteturais que afetam este repo:

1. Copie o template (a definir; por enquanto, crie como `docs/adr/000N-titulo-em-kebab.md`).
2. Numere sequencialmente.
3. Status: `proposta` → `aceita` → (eventualmente `superada por N`).
4. Inclua: contexto, decisão, consequências (positivas e negativas), alternativas consideradas.
5. PR com 2 reviewers (ver tabela).

---

## Quando NÃO usar este repo

Algumas coisas **não pertencem aqui**:

- ❌ Código de aplicação (vai nos repos dos serviços: `core-api`, `legacy-api`, `bff-gateway`, etc.)
- ❌ Schemas de banco de dados de aplicação (vai no repo do serviço-dono daquela tabela)
- ❌ Contratos de API entre serviços (vai em `ERP-CONTRACTS` — repo separado)
- ❌ Documentação de negócio / domínio (vai no handbook)
- ❌ Segredos reais (vai no Secrets Manager provisionado em [`platform/`](platform/))

Quando em dúvida, abra issue antes de commitar.
