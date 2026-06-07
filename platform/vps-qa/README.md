# QA rápido em VPS

Este diretório sobe um ambiente de **QA econômico**, não um `staging` equivalente
a produção. A VM atual é uma Magalu Cloud `BV1-2-20` com Ubuntu 24.04,
2 GB de RAM e 20 GB de disco.

## Limites dessa máquina

- Serve apenas para homologação funcional, poucos usuários e base pequena.
- Não compile imagens nela. O build simultâneo de Node/pnpm excede RAM e disco.
- MinIO, observabilidade completa, alta disponibilidade e réplicas ficam fora.
- Contratos ficam em memória até o Object Storage ser configurado no `.env`.
- Sessões do `web-app` e chaves JWT ainda são voláteis: restart exige novo login.
- Use 2 GB de RAM e 20 GB de disco assim que houver testes concorrentes, anexos
  ou necessidade de maior estabilidade.

## Caminho mais rápido

1. Crie a VM com IPv4 público e a chave SSH.
2. No Security Group, abra `80/443` para a internet e `22` somente para seu IP.
3. Crie um registro DNS `A`, por exemplo `qa.seudominio.com`, para o IPv4.
4. Prepare a VM:

   ```bash
   scp bootstrap.sh ubuntu@IP:/tmp/
   ssh ubuntu@IP 'sudo bash /tmp/bootstrap.sh'
   ```

5. Autentique a VM no GitHub Container Registry (as imagens de QA são
   **privadas**). Use um PAT **clássico** com escopo `read:packages`:

   ```bash
   echo "$GHCR_TOKEN" | docker login ghcr.io -u SEU_USUARIO --password-stdin
   ```

6. Coloque os arquivos de infra em `/opt/erp-qa` e configure o `.env`:

   ```bash
   sudo chown -R ubuntu:ubuntu /opt/erp-qa
   scp compose.yaml Caddyfile deploy.sh ubuntu@IP:/opt/erp-qa/
   chmod +x /opt/erp-qa/deploy.sh
   cd /opt/erp-qa && cp .env.example .env && chmod 600 .env
   # edite .env: APP_ADDRESS (hostname com DNS → IP; sslip.io serve p/ QA),
   # MYSQL_ROOT_PASSWORD e MYSQL_APP_PASSWORD com `openssl rand -hex 32`.
   ```

7. Suba a stack:

   ```bash
   docker compose config
   docker compose up -d --wait
   docker compose ps
   ```

O Caddy obtém e renova TLS automaticamente. O login não deve ser homologado por
`http://IP`, porque o frontend usa cookie de sessão `Secure`.

## Deploy automático (push-via-CI)

Os builds rodam no **GitHub Actions** (`.github/workflows/deploy-qa.yml` em
`core-api` e `web-app`) — **nunca na VPS**. O fluxo:

```
push (core-api:dev / web-app:develop)
  → Actions builda linux/amd64 → push ghcr.io/erp-bem-comum/{core-api,bemcomum-web}:qa
  → job deploy: SSH na VPS → /opt/erp-qa/deploy.sh (compose pull && up -d --wait)
```

O job de deploy usa uma **chave SSH dedicada** (secret `DEPLOY_SSH_KEY` nos repos)
cuja pública está em `~ubuntu/.ssh/authorized_keys` travada por **forced command**
em `deploy.sh` (sem shell livre). Como `deploy.sh` roda `up -d --wait`, o run do
Actions fica **vermelho** se algum container não ficar `healthy` — esse é o sinal
de "deu ruim". Setup da chave:

```bash
ssh-keygen -t ed25519 -f deploy_key -N "" -C gha-deploy-qa
# na VPS, em ~ubuntu/.ssh/authorized_keys:
#   command="/opt/erp-qa/deploy.sh",no-port-forwarding,no-pty ssh-ed25519 AAAA... 
gh secret set DEPLOY_SSH_KEY --repo ERP-Bem-Comum/core-api  < deploy_key
gh secret set DEPLOY_SSH_KEY --repo ERP-Bem-Comum/web-app   < deploy_key
```

## Status page

`uptime-kuma` (no `compose.yaml`) é exposto pelo Caddy em
`https://status.${APP_ADDRESS}`. Crie o admin no 1º acesso e adicione monitores
HTTP para o site (`https://${APP_ADDRESS}`) e para os serviços internos
(`http://core-api:3000/health`, `http://web:3000/health`).

## Persistência funcional

Auth e Parceiros usam MySQL. Contratos começa em memória para não executar MinIO
na VPS de 1 GB. Para persistir contratos e documentos, crie um bucket privado no
Object Storage da Magalu, preencha `S3_*` e defina `CONTRACTS_DRIVER=mysql`.

Ainda existe estado volátil na aplicação:

- reiniciar `web` encerra as sessões atuais;
- sem chaves ES256 injetadas, reiniciar `core-api` invalida tokens;
- a timeline de contratos ainda é in-memory no código atual.

Esses limites impedem chamar esta VPS de `staging` equivalente à produção.

## Atualização

Automática: basta `git push` na branch de QA (`core-api:dev` / `web-app:develop`).
O Actions builda e redeploya só o serviço alterado. Para redeploy manual:

```bash
cd /opt/erp-qa && ./deploy.sh   # pull + up -d --wait + prune
```

## Backup

`./backup.sh` gera dump local e mantém sete dias. Em disco de 10 GB, copie o
arquivo diariamente para Object Storage; backup no mesmo disco não protege
contra perda da VM.

Exemplo de cron:

```cron
15 3 * * * cd /opt/erp-qa && ./backup.sh >> /var/log/erp-qa-backup.log 2>&1
```

## Verificação

```bash
curl -I https://qa.seudominio.com
docker compose ps
docker stats --no-stream
df -h /
free -h
```

MySQL e `core-api` não publicam portas no host. Somente Caddy expõe `80/443`.
