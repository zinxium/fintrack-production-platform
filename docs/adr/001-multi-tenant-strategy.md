# ADR 001 — Stratégie multi-tenant

**Status:** Accepted
**Date:** À dater à la mise en œuvre
**Decision-makers:** Data Platform Team + RSSI

## Context

FinTrack devient une plateforme B2B2C. Chaque tenant (banque partenaire)
doit être strictement isolé — un incident chez un tenant ne doit jamais
exposer les données d'un autre.

## Options évaluées

### Option A : Base Snowflake par tenant
- ✅ Isolation absolue
- ❌ Explosion de la maintenance (15 pipelines dbt)
- ❌ Coûts × 15 (warehouses par base)
- ❌ Impossible d'agréger cross-tenant

### Option B : Schéma par tenant, base unique
- ✅ Isolation forte
- ❌ 15 schémas RAW à alimenter
- ❌ Union dbt lourde à maintenir

### Option C : Table unique + Row Access Policy (retenue)
- ✅ Simple à maintenir
- ✅ Aggregation cross-tenant possible (via rôle admin)
- ✅ Policies évoluent sans migration de données
- ⚠️ Une erreur de policy = fuite immédiate — tests obligatoires

## Décision

**Option C** avec les garanties :
1. Table `GOVERNANCE.user_tenant_access` comme source de vérité
2. Row Access Policy testée dans CI (jeu de test isolé par PR)
3. Alerting sur toute modification de `user_tenant_access`
4. Audit mensuel de `ACCESS_HISTORY` pour détecter des cross-tenant leaks

## Conséquences

- Rôle `FINTRACK_TRANSFORM_ROLE` doit être court-circuité (accès total nécessaire pour dbt)
- Consommateurs BI (Power BI) doivent utiliser SSO (voir ADR 005)
- La CNIL considère cette approche acceptable si les audits sont documentés

## Preuve d'exécution

### Vérification CI (statique)

Le test `tests/security/test_rap_tenant_isolation.sql` vérifie via
`INFORMATION_SCHEMA.POLICY_REFERENCES` que la policy `RAP_TENANT_ISOLATION`
est bien attachée aux 5 tables sensibles :

| Table              | Schéma      |
|--------------------|-------------|
| RAW_COMPTES        | RAW         |
| RAW_TRANSACTIONS   | RAW         |
| RAW_VIREMENTS      | RAW         |
| DIM_COMPTES        | MARTS_CORE  |
| FCT_TRANSACTIONS   | MARTS_CORE  |

Le test renvoie 0 ligne si tout est en place (pass), ou les tables
manquantes (fail). Il s'exécute à chaque PR via `dbt test`.

### Test runtime (isolation effective)

Pour valider que la RAP filtre réellement les lignes :

```sql
-- En tant que rôle consultant lié au tenant ALPHA_BANK
USE ROLE CONSULTANT_ALPHA_BANK;

SELECT DISTINCT tenant_id
FROM FINTRACK_PROD.MARTS_CORE.FCT_TRANSACTIONS;
-- Attendu : une seule valeur — l'id du tenant ALPHA_BANK
-- Si > 1 valeur → fuite cross-tenant → incident P0

-- Vérification explicite : aucune ligne d'un autre tenant ne doit remonter
SELECT COUNT(*) AS lignes_autres_tenants
FROM FINTRACK_PROD.MARTS_CORE.FCT_TRANSACTIONS
WHERE tenant_id != (
    SELECT tenant_id FROM GOVERNANCE.user_tenant_access
    WHERE snowflake_user = CURRENT_USER()
);
-- Attendu : 0
```

Ce test runtime doit être rejoué manuellement :
- Lors de toute modification de `GOVERNANCE.user_tenant_access`
- Lors de chaque ajout de table dans le scope de la RAP
- En cas d'alerte Snowflake `ACCESS_HISTORY` détectant un cross-tenant read
