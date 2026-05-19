[← Voltar para raiz](../README.md)

# 👤 `local/` — Ambiente de desenvolvimento local

> Tudo o que um dev precisa para subir a stack mínima em < 5 minutos.

## O que sobe

| Componente | Status no compose | Comentário |
|---|---|---|
| MySQL 8.4 (com databases `legacy` e `core` e 3 usuários) | ✅ Ativo | Reflete a topologia do handbook |
| phpMyAdmin | ⚙️ Opt-in (`--profile tools`) | Inspeção visual do banco |
| `bff-gateway` | 🔵 Comentado (template) | Descomentar quando o repo do serviço publicar imagem |
| `legacy-api` | 🔵 Comentado (template) | Idem |
| `core-api` | 🔵 Comentado (template) | Idem |

A ideia: hoje, o que está pronto é a camada de dados. Conforme cada serviço ganha repo + imagem publicada, descomenta a seção correspondente no `docker-compose.yml`.

## Pré-requisitos

- **Docker Desktop** (Mac/Windows) ou **Docker Engine** (Linux) — v24+
- **Docker Compose v2** (já vem com Docker Desktop)
- Porta `3306` livre no host (ou ajuste `MYSQL_PORT` em `.env`)

## Quick start

```bash
# 1. Copia variáveis
cp .env.example .env

# 2. Sobe MySQL
docker compose up -d

# 3. Verifica healthcheck
docker compose ps
# Deve mostrar mysql com STATUS = healthy depois de ~30s

# 4. Logs em tempo real (Ctrl+C para sair)
docker compose logs -f mysql

# 5. (Opcional) sobe phpMyAdmin em http://localhost:8080
docker compose --profile tools up -d
```

## Conectando ao banco

| Como | Comando / valor |
|---|---|
| CLI a partir do host | `docker compose exec mysql mysql -u root -proot_local_dev_only` |
| CLI como `core_app` | `docker compose exec mysql mysql -u core_app -pcore_local_dev_only core` |
| String de conexão (host) | `mysql://core_app:core_local_dev_only@localhost:3306/core` |
| String de conexão (container) | `mysql://core_app:core_local_dev_only@mysql:3306/core` |
| phpMyAdmin (com `--profile tools`) | http://localhost:8080 — user `root`, senha do `.env` |

## Validando o isolamento (smoke test)

O isolamento por GRANT é a regra mais importante. Validação rápida:

```bash
# Conecta como core_app — deve enxergar 'core' e NÃO enxergar 'legacy'
docker compose exec mysql mysql -u core_app -pcore_local_dev_only -e "SHOW DATABASES;"

# Tenta acessar legacy.* como core_app — deve dar ERRO
docker compose exec mysql mysql -u core_app -pcore_local_dev_only -e "USE legacy;"
# ERROR 1044 (42000): Access denied for user 'core_app'@'%' to database 'legacy'
```

Se isso passar (deu ERROR), o isolamento está funcionando.

## Reset completo

```bash
# Derruba containers MANTENDO os dados
docker compose down

# Derruba containers REMOVENDO os dados (volta ao estado inicial)
docker compose down -v

# Recria do zero
docker compose up -d
```

## Carregando dump do legado

> 🔵 **Quando o dump anonimizado estiver disponível** (responsabilidade do time de infra / migração).

```bash
# Suponha um dump em ~/dumps/legacy-anon.sql
docker compose exec -T mysql mysql -u root -proot_local_dev_only legacy < ~/dumps/legacy-anon.sql
```

> ⚠️ **Não commite dumps neste repo.** Mesmo anonimizados, são pesados e potencialmente sensíveis. Distribuição via canal interno (drive corporativo, S3 privado).

## Troubleshooting

| Sintoma | Provável causa | Solução |
|---|---|---|
| `port 3306 already in use` | Outro MySQL rodando no host | Trocar `MYSQL_PORT=3307` no `.env`, recriar |
| `mysqladmin: connect to server at 'localhost' failed` | Container ainda subindo | Aguardar 30s, conferir `docker compose ps` |
| `Access denied for user 'core_app'@'%'` ao tentar `legacy.*` | **Isolamento funcionando! ✅** | Não é um problema |
| Volume `erp-mysql-data` enorme | Acúmulo de dados de testes | `docker compose down -v` para reset |
| phpMyAdmin não responde | Não foi iniciado com `--profile tools` | `docker compose --profile tools up -d` |

## Próximos passos

Conforme os repos de serviço forem criados:

1. Descomentar a seção correspondente no `docker-compose.yml`
2. Atualizar este README com a porta e endpoint do serviço
3. Adicionar smoke test do serviço (curl no `/health`)
