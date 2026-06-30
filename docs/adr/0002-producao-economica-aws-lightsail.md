# ADR-0002 — Produção econômica inicial em AWS Lightsail

**Status:** ❌ Superseded por [ADR-0003](0003-producao-aws-ecs.md) (produção AWS ECS)
**Data:** 2026-06-07
**Decisor inicial:** Gabriel Aderaldo
**Reviewers obrigatórios:** dev sênior + líder de infra

---

> ⚠️ **Nota histórica (superada).** A produção do ERP Bem Comum foi de fato
> implementada em **AWS ECS** (CodePipeline + CodeBuild + CodeDeploy + RDS + ELB +
> Secrets Manager), **não** em Lightsail. Este ADR permanece como **registro
> histórico** da alternativa econômica single-node que foi considerada e
> descartada. A decisão vigente está em [`ADR-0003 — Produção AWS ECS`](0003-producao-aws-ecs.md).
> O diretório `platform/aws-lightsail-prod/` citado abaixo **foi removido** do repo
> (nunca chegou a ser provisionado).

## Contexto

O alvo arquitetural de longo prazo prevê serviços com múltiplas réplicas, banco
gerenciado Multi-AZ, load balancer e observabilidade completa. Esse desenho é
adequado quando indisponibilidade curta gera impacto operacional maior que seu
custo mensal.

Na entrada em produção, o objetivo prioritário é reduzir o custo fixo sem
abandonar IaC, backup externo, TLS, isolamento de rede e um caminho explícito de
migração. ECS/Fargate, RDS Multi-AZ, ALB, WAF e NAT Gateway aumentariam
significativamente a conta antes de existir carga que os justifique.

## Decisão

Adotar temporariamente uma produção single-node em AWS Lightsail:

- instância Linux de 4 GB de RAM, 2 vCPUs e 80 GB SSD;
- IP estático;
- portas públicas `80/443`; SSH `22` restrito ao CIDR administrativo;
- Caddy como terminador TLS e único serviço exposto;
- `web-app`, `core-api` e MySQL 8.4 em Docker Compose;
- documentos em S3 ou Lightsail Object Storage, nunca no disco da aplicação;
- dump diário do MySQL enviado para storage externo;
- snapshots automáticos diários da instância;
- imagens construídas no CI e executadas por digest ou tag imutável;
- deploy e rollback por scripts versionados, sem compilar na VPS.

A implementação ficaria em `platform/aws-lightsail-prod/` (diretório **removido** —
nunca provisionado; ver nota histórica no topo).

Este baseline é uma exceção temporária ao alvo de alta disponibilidade descrito
em [`../topology.md`](../topology.md). Ele não pode declarar SLA de 99,9%, RPO de
15 minutos ou RTO de 30 minutos.

## Gatilhos de migração

Migrar para o alvo gerenciado, começando por RDS e depois ECS/Fargate, quando
qualquer condição ocorrer:

1. indisponibilidade de quatro horas deixar de ser aceitável;
2. perda potencial de até 24 horas de dados deixar de ser aceitável;
3. uso sustentado superar 70% de RAM, CPU ou disco;
4. houver necessidade de deploy sem interrupção ou escalabilidade horizontal;
5. operação exigir múltiplas zonas de disponibilidade;
6. receita, contrato ou requisito regulatório exigir SLA formal;
7. custo operacional humano da VPS superar a economia mensal.

## Alternativas consideradas

### ECS Fargate + RDS Multi-AZ + ALB

É o alvo recomendado para alta disponibilidade, mas foi adiado pelo custo fixo
e pela complexidade operacional prematura.

### EC2 single-node

Oferece mais flexibilidade, porém preço e cobrança são menos previsíveis. O
Lightsail inclui CPU, RAM, SSD, IP e franquia de transferência em um plano
mensal simples.

### Lightsail de 2 GB

Rejeitado para produção. MySQL, duas aplicações Node e proxy no mesmo host
deixariam pouca margem para picos, backup e atualização.

## Consequências

### Positivas

- custo previsível e baixo;
- operação semelhante ao QA atual;
- IaC e runbooks permitem reconstrução;
- migração posterior para EC2 ou serviços gerenciados continua possível;
- storage externo protege documentos contra perda da instância.

### Negativas

- a instância é ponto único de falha;
- deploy ou reboot pode causar indisponibilidade;
- MySQL compete por CPU, memória e disco com as aplicações;
- restauração é manual;
- sessões do `web-app` ainda são in-memory e são perdidas em restart;
- não existe failover automático.

## Referências

- [`../environments.md`](../environments.md)
- [`../topology.md`](../topology.md)
- `platform/aws-lightsail-prod/README.md` (removido — baseline nunca provisionado)
- [`0003-producao-aws-ecs.md`](0003-producao-aws-ecs.md) — ADR que substitui esta
- [Preços do AWS Lightsail](https://aws.amazon.com/pt/lightsail/pricing/)
- [Snapshots automáticos do Lightsail](https://docs.aws.amazon.com/lightsail/latest/userguide/amazon-lightsail-configuring-automatic-snapshots.html)
