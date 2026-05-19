# ADR-0001 — Propósito e stewardship do repositório `ERP-INFRA`

**Status:** ✅ Aceita
**Data:** 2026-05-19
**Decisor inicial:** Gabriel Aderaldo
**Reviewers obrigatórios para mudar esta ADR:** dev sênior + líder de infra

---

## Contexto

A reformulação open source do ERP da Associação A Bem Comum envolve **dois grupos** com necessidades sobrepostas mas perspectivas distintas:

- **Devs** precisam entender como a infra parece para acertarem decisões de runtime (timeouts, retries, paths, env vars) e para rodarem a stack localmente.
- **Time de infra/plataforma** precisa entregar a infra real, com IaC, e manter o que está provisionado alinhado com o que foi acordado.

Antes da existência deste repo, o handbook arquitetural privado guarda o desenho **planejado**, mas:

1. Não é acessível a colaboradores externos open source.
2. Não tem como hospedar IaC executável.
3. Não tem como hospedar docker-compose para dev local.
4. Não comporta evolução conjunta dev ↔ infra com PR review.

Resultado: hoje o dev "imagina" a infra a partir de docs estáticos; o infra "imagina" o que dev quer a partir de conversas informais.

## Decisão

Criar o repositório público `ERP-Bem-Comum/ERP-INFRA` como **único ponto de convergência** entre dev e infra, com responsabilidades dividas em três pastas:

- `local/` — docker-compose e scripts para que qualquer dev rode a stack mínima local em < 5 min.
- `docs/` — especificação técnica viva (topologia, ambientes, secrets, observabilidade). **Fonte de verdade** sobre o "como deveria ser".
- `platform/` — IaC real (Terraform / Helm / Pulumi / a definir). **Fonte de verdade** sobre o "como está provisionado".

Quando `docs/` e `platform/` divergem, abre-se um PR para reconciliar. A divergência é um bug de processo, não um estado aceitável.

### Stewardship

| Pasta | Steward primário | Steward secundário |
|---|---|---|
| `local/` | Time de dev | — |
| `docs/topology.md`, `docs/environments.md` | Time de dev (arquitetura) | Líder de infra |
| `docs/secrets.md` | Líder de infra | Security |
| `docs/observability.md` | Time de dev (arquitetura) + Oncall | Líder de infra |
| `docs/adr/` | Quem propõe + 1 dev sênior + 1 líder de infra | — |
| `platform/` | Líder de infra | — |

Reviewers obrigatórios automatizados via [`CODEOWNERS`](../../CODEOWNERS).

## Alternativas consideradas

### Alt. 1 — Manter tudo no handbook + repo separado só para IaC

**Rejeitada.** Mantém a fragmentação. Dev continua lendo handbook estático; infra continua sem espelho do que dev precisa. Não resolve o problema original.

### Alt. 2 — IaC dentro do repo de cada serviço

**Rejeitada.** IaC compartilhada (VPC, banco, Secrets Manager, LB) não tem dono natural. Duplicar nos 3 repos quebra single source of truth. Espalhar entre repos esconde a topologia.

### Alt. 3 — Repos separados para `docs-infra` e `platform-infra`

**Rejeitada.** Aumenta a fricção do PR de reconciliação (precisaria de PRs sincronizados em 2 repos). Um repo único com pastas resolve melhor.

## Consequências

### Positivas

- ✅ Devs têm um lugar único para ler "como a infra parece".
- ✅ Infra tem um lugar único para commitar IaC e atualizar specs.
- ✅ PRs de reconciliação são triviais (1 repo, 1 PR).
- ✅ Open source: o desenho da infra fica auditável para a A Bem Comum e para outras ONGs que queiram reusar.
- ✅ Secrets nunca vazam porque o catálogo é só de **nomes**, jamais de valores.

### Negativas

- ❌ Repo tem duas audiências; risco de virar uma bagunça se não houver disciplina de pastas. Mitigação: [`CODEOWNERS`](../../CODEOWNERS) e regras claras em [`CONTRIBUTING.md`](../../CONTRIBUTING.md).
- ❌ Mudança de IaC pode bloquear no review de infra se o líder estiver indisponível. Mitigação: ter ao menos 2 mantenedores de `platform/` no CODEOWNERS.

## Indicador de sucesso

Em 3 meses, conseguir remover a seção "⚠️ Estado atual — planejado vs. real" do README porque o status de todos os docs em `docs/` está 🟢 VIGENTE.

## Referências

- [`../topology.md`](../topology.md)
- [`../environments.md`](../environments.md)
- [`../../CONTRIBUTING.md`](../../CONTRIBUTING.md)
- [`../../CODEOWNERS`](../../CODEOWNERS)
