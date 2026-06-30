# ERP-INFRA

> **Reflexo da infraestrutura do ERP Bem Comum.** Este repositório é o **ponto de conversão** entre o time de desenvolvimento e o time de infra/plataforma. Ele responde a duas perguntas, para duas audiências:

| Audiência | Pergunta | Onde olhar |
|---|---|---|
| 👤 **Desenvolvedor** | "Como rodo a stack inteira localmente para trabalhar no meu serviço?" | [`local/`](local/) |
| 👤 **Desenvolvedor** | "Como a infra deveria parecer em produção? Onde meu serviço vai rodar?" | [`docs/`](docs/) |
| 🏗️ **Time de Infra/Plataforma** | "Qual é o contrato técnico que devo materializar?" | [`docs/`](docs/) |
| 🏗️ **Time de Infra/Plataforma** | "Onde commito a IaC real (Terraform, Helm, Pulumi, etc.)?" | [`platform/`](platform/) |

---

## ⚠️ Estado atual — **planejado vs. real**

Este repositório nasce como **reflexo do PLANEJADO** descrito no [handbook arquitetural](https://github.com/ERP-Bem-Comum) (privado por enquanto). Os diagramas e specs em [`docs/`](docs/) refletem a decisão arquitetural; **podem não refletir o estado atual da infra provisionada**.

> **Time de Infra**: peço gentilmente que mantenham este repo atualizado com a infra **REAL** a cada provisionamento. Mudou IaC? Atualize [`platform/`](platform/). Mudou topologia provisionada? Reflita em [`docs/topology.md`](docs/topology.md). Adicionou ambiente? Atualize [`docs/environments.md`](docs/environments.md).
>
> Quando esta seção puder ser removida (planejado ≡ real), aceitarei o PR com gosto. 🤝

---

## 📁 Layout

```
ERP-INFRA/
├── local/                  👤 docker-compose + scripts para dev local
├── docs/                   📐 specs e diagramas (contrato técnico)
│   ├── topology.md             diagrama de componentes (Mermaid)
│   ├── environments.md         dev / staging / prod
│   ├── secrets.md              catálogo de secrets
│   ├── observability.md        logs, métricas, tracing, alertas
│   └── adr/                    decisões específicas deste repo
├── platform/               🏗️ IaC real (Terraform / Helm / ...) — preenchido pela infra
├── CODEOWNERS              quem revisa o quê
├── CONTRIBUTING.md         regras de contribuição específicas deste repo
└── LICENSE                 MIT
```

---

## 🚀 Quick start (dev local)

```bash
# 1. Clonar
git clone git@github.com:ERP-Bem-Comum/ERP-INFRA.git
cd ERP-INFRA/local

# 2. Configurar variáveis (copia exemplo e ajusta se precisar)
cp .env.example .env

# 3. Subir a stack mínima (MySQL com databases isolados)
docker compose up -d

# 4. Verificar
docker compose ps
docker compose logs -f mysql
```

Detalhes em [`local/README.md`](local/README.md).

## 🚀 Quick start (QA em VPS)

O caminho econômico para Magalu Cloud está em
[`platform/vps-qa/`](platform/vps-qa/). Ele prepara uma VPS Ubuntu 24.04,
recebe imagens construídas fora da máquina e expõe somente Caddy em `80/443`.

> O QA atual usa `BV1-2-20`. A
> `BV1-1-10` fica restrita a demonstrações curtas.

## 🚀 Produção (AWS ECS)

A produção roda em **AWS ECS** (alta disponibilidade): a infra **traduz o
`compose.yaml` do core-api** em 1 Task Definition + 1 ECS Service por service — a
**API** atrás do **ELB**, os 5 workers como Services sem ELB. Banco em **RDS**,
segredos no **Secrets Manager**, e-mail via **Amazon SES (SMTP)**, documentos em
**S3**, CI/CD por **CodePipeline → CodeBuild → CodeDeploy**.

Decisão e detalhes em [`ADR-0003 — Produção AWS ECS`](docs/adr/0003-producao-aws-ecs.md)
(supersede a [`ADR-0002`](docs/adr/0002-producao-economica-aws-lightsail.md), o
baseline econômico Lightsail descartado). Detalhes específicos (conta, região,
cluster, ARNs) são mantidos pelo time de infra.

---

## 🤝 Como contribuir

| Tipo de mudança | Quem aprova | Branch protection |
|---|---|---|
| Diagrama / spec em `docs/` | Dev sênior + Infra | PR obrigatório, 1 review |
| Docker compose / scripts em `local/` | Dev sênior | PR obrigatório, 1 review |
| IaC real em `platform/` | Líder de Infra | PR obrigatório, 1 review do CODEOWNER de infra |
| ADRs em `docs/adr/` | Dev sênior + Líder de Infra | PR obrigatório, 2 reviews |

Veja [`CONTRIBUTING.md`](CONTRIBUTING.md). Commits seguem [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/#summary) (padrão da org).

---

## 🔗 Referências

- [Organização ERP-Bem-Comum](https://github.com/ERP-Bem-Comum)
- [Padrões e community files da org](https://github.com/ERP-Bem-Comum/.github)
- Handbook arquitetural (acesso restrito; sincronize trechos relevantes aqui via PR)

---

## 📜 Licença

[MIT](LICENSE) — Copyright (c) 2026 Associação A Bem Comum and ERP Bem Comum contributors.
