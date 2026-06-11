#!/usr/bin/env bash
# Gera os secrets locais (idempotente — não sobrescreve o que já existe).
# - MySQL root/app: 32 bytes hex aleatórios.
# - JWT auth: par EC P-256 (ES256), PKCS#8 sem cifra — formato esperado pelo módulo auth.
set -euo pipefail

cd "$(dirname "$0")"
mkdir -p secrets
umask 077

[ -s secrets/mysql-root-password ] || openssl rand -hex 32 > secrets/mysql-root-password
[ -s secrets/mysql-app-password ]  || openssl rand -hex 32 > secrets/mysql-app-password

if [ ! -s secrets/auth-jwt-private-key.pem ]; then
  openssl ecparam -name prime256v1 -genkey -noout \
    | openssl pkcs8 -topk8 -nocrypt -out secrets/auth-jwt-private-key.pem
  openssl ec -in secrets/auth-jwt-private-key.pem -pubout \
    -out secrets/auth-jwt-public-key.pem
fi

# O core-api roda non-root (uid 10001) e o Compose monta os secrets como bind mount
# preservando o modo do host. 600/owner-ubuntu → "Permission denied" para o app.
# 644 deixa o usuário do container ler. Aceitável nesta VPS de QA single-tenant.
chmod 644 secrets/*
echo "Secrets prontos em ./secrets/:"
ls -la secrets/
