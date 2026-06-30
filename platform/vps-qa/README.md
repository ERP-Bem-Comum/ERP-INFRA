# VPS de QA — `erp-bem-comum-qa` (Magalu Cloud)

Ambiente de homologação / PBE (ver [ADR-0021](../../../core-api/handbook/architecture/adr/0021-aws-primary-magalu-pbe-supersedes-0007.md)):
**sem dados reais**, custeado pela equipe, single-node, descartável.

Uma VPS Magalu `BV1-2-10` (1 vCPU / 2 GB RAM / 10 GB) roda Caddy + core-api + workers +
MySQL 8.4 via Docker Compose. A imagem do core-api é **buildada no GitHub Actions** e
publicada no ghcr; **esta VPS nunca compila** — só faz `docker compose pull` da tag `:qa`.

```text
Internet
  -> DNS A  erp-qa.gabrieladeraldo.dev
  -> IP público da VPS
  -> Caddy :80/:443             (TLS automático via ACME)
  -> web :3000                  (BFF TanStack Start)
  -> core-api :3000             (API HTTP — monolito: auth + partners + contracts + programs + financial)
  -> core-api-outbox-contracts  (worker outbox contracts, long-running)
  -> core-api-outbox-partners   (worker outbox partners, long-running)
  -> core-api-supplier-projection    (worker projeção fin_supplier_view, long-running)
  -> core-api-contract-count-projection (worker projeção contract count, long-running)
  -> core-api-email-dispatch    (worker envio de e-mail via SMTP/SES, long-running)
  -> core-api-migrate           (job one-shot, roda antes do core-api subir)
  -> core-api-sweeper           (job one-shot, agendamento externo — systemd timer/ofelia)
  -> MySQL 8.4 :3306            (rede interna, sem porta publicada)
```

## Provisionamento da VPS

A VM é criada via `mgc` (CLI da Magalu), região `br-ne1`, AZ `br-ne1-a`:

- flavor `BV1-2-10`, imagem `cloud-ubuntu-24.04 LTS`;
- VPC default, SSH key `magalu-bootstrap`, IP público;
- security group com `22` (key-only), `80`, `443` e egress;
- `cloud-init` ([../tofu/environments/qa/cloud-init.yaml](../tofu/environments/qa/cloud-init.yaml))
  instala docker, cria 2 GB de swap, habilita UFW e prepara `/opt/erp-qa`.

> SSH só por chave (`PasswordAuthentication no`). Acesso administrativo restrito; o
> deploy automático usa uma deploy key travada por *forced-command* em `deploy.sh`.

## Instalação do runtime

```bash
# da máquina do operador, com a VPS já no ar:
rsync -av --exclude secrets ./ ubuntu@<IP>:/opt/erp-qa/
ssh ubuntu@<IP>
cd /opt/erp-qa
cp .env.example .env      # ajuste APP_ADDRESS / APP_URL se o subdomínio mudar
./init-secrets.sh         # gera mysql + JWT ES256
docker login ghcr.io      # se o pacote core-api for privado (PAT com read:packages)
```

## DNS (obrigatório antes do primeiro deploy)

Crie um registro **A** `erp-qa.gabrieladeraldo.dev` → `<IP público da VPS>`. O Caddy só
consegue emitir o certificado TLS depois que o DNS resolver para o IP.

## Deploy e rollback

```bash
./deploy.sh                                   # pull da :qa + up --wait + ps
curl -fsSI https://erp-qa.gabrieladeraldo.dev/health
```

`deploy.sh` é também o alvo do forced-command da deploy key — o workflow
`core-api/.github/workflows/deploy-qa.yml` builda a imagem, faz push e dispara
`ssh ubuntu@<IP> deploy`. Para rollback, fixe `CORE_API_IMAGE` num digest anterior
no `.env` e rode `./deploy.sh` de novo. **Nunca compile imagem na VPS.**

## Migrations e seed

As migrations de todos os módulos (auth / partners / contracts / programs / financial /
notifications) rodam no job dedicado `core-api-migrate` (`src/jobs/migrate/run.ts`)
**antes** do `core-api` subir (`depends_on: service_completed_successfully`). O banco
zerado é migrado no primeiro start. O seed de RBAC/usuário admin (`AUTH_SEED_JSON`,
`pnpm db:seed:partners`) é passo separado, ainda **não** automatizado aqui.

## Operação

```bash
docker compose ps
docker stats --no-stream
docker compose logs -f core-api
docker compose logs -f core-api-outbox-contracts
docker compose logs -f core-api-email-dispatch
free -h && df -h /
```

### Invocar o sweeper manualmente

```bash
# O sweeper NÃO sobe via `compose up` (profile opt-in).
# Disparo avulso (mesma imagem do core-api, executa e sai):
docker compose run --rm core-api-sweeper
```

O agendamento recorrente (1×/dia às 00:05 America/Sao_Paulo) é configurado
externamente via **systemd timer** ou **ofelia** na VPS — não via `compose up`.

## Limitações conhecidas

- ponto único de falha; sem HA, sem réplica;
- `BV1-2-10` é enxuto: 2 GB RAM + 2 GB swap. Com os 5 workers, o footprint total
  sobe para ~2568 MB (baseline 1608 m + workers 960 m). Monitorar com `docker stats`.
  Se houver OOM ou disco cheio (10 GB), subir para `BV1-2-20` / `BV2-2-20`;
- sem backup automatizado (ambiente descartável — recriar do zero é o plano de recuperação).
