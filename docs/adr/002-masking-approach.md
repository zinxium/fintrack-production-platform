# ADR 002 — Approche de masking des PII

**Status:** Accepted

## Context

Les analystes doivent pouvoir travailler sur des données réelles sans
voir les PII en clair. La CNIL exige un principe de minimisation.

## Options

### Option A : Vues avec CASE WHEN CURRENT_ROLE()
- ❌ Duplique la logique dans chaque vue
- ❌ Facile d'oublier une colonne

### Option B : Masking Policies Snowflake (retenue)
- ✅ Déclaratif
- ✅ S'applique automatiquement aux nouvelles requêtes
- ✅ Combinable avec tag-based

### Option C : Anonymisation à l'ingestion
- ❌ Perd de la valeur analytique
- ❌ Impossible de démasquer pour la conformité

## Décision

**Option B** avec deux niveaux :
1. Application explicite colonne par colonne sur les tables RAW critiques
2. Application via post-hook dbt sur les marts (pour ne pas oublier)

## Rôles et niveaux de démasquage

| Rôle | Nom | Email | IBAN | DoB | IP |
|------|-----|-------|------|-----|-----|
| ADMIN | ✅ clair | ✅ clair | ✅ clair | ✅ clair | ✅ clair |
| PII_UNMASK | ✅ clair | ✅ clair | ✅ clair | ✅ clair | ✅ clair |
| SUPPORT | Init.*** | ***@... | 4 first + 4 last | ❌ | ❌ |
| COMPLIANCE | *** | *** | 4 first + 4 last | ❌ | /24 |
| ANALYST | *** | hash | *** | Année seule | /24 |
| FRAUD | *** | hash | *** | ❌ | ✅ clair |

Le rôle PII_UNMASK doit être audité manuellement chaque mois.

## Preuve d'exécution

### Application des policies

Les masking policies sont appliquées à deux niveaux :

1. **Niveau RAW (Snowflake direct)** — `scripts/snowflake/security/02_masking_policies.sql`
   - 7 policies créées dans `GOVERNANCE` : `mask_email`, `mask_name`, `mask_phone`, `mask_iban`, `mask_date_of_birth`, `mask_address`, `mask_ip_address`, `mask_device_id`
   - Attachées colonne par colonne sur `RAW.raw_comptes` et `RAW.raw_transactions`

2. **Niveau MARTS (dbt post-hook)** — `dbt/macros/security/apply_masking_via_dbt.sql`
   - La macro `apply_masking_policies()` est appelée en `post_hook` sur `dim_comptes`
   - Elle inspecte `INFORMATION_SCHEMA.COLUMNS` et applique la policy correspondante selon le nom de colonne
   - 10 colonnes couvertes : `email`, `nom_client`, `prenom_client`, `telephone`, `iban`, `ip_address`, `device_id`, `date_naissance`, `adresse_ligne1`, `adresse_ligne2`

### Vérification rapide

```sql
-- Vérifier que les policies sont attachées sur dim_comptes
SELECT column_name, policy_name
FROM FINTRACK_PROD.information_schema.policy_references
WHERE ref_entity_name = 'DIM_COMPTES'
  AND ref_schema_name = 'MARTS_CORE'
  AND policy_kind = 'MASKING_POLICY'
ORDER BY column_name;
-- Attendu : 8 lignes (email, nom_client, prenom_client, telephone,
--           iban, date_naissance, adresse_ligne1, adresse_ligne2)

-- Test comportement ANALYST
USE ROLE FINTRACK_ANALYST_ROLE;
SELECT compte_id, nom_client, email, iban, date_naissance
FROM FINTRACK_PROD.MARTS_CORE.DIM_COMPTES
LIMIT 3;
-- Attendu : nom_client='***', email=SHA256(...), iban='****',
--           date_naissance=année seule (ex: 1985-01-01)
```

### Matrice de validation complète

Voir `docs/masking_test_matrix.md` — 10 colonnes × 6 rôles avec résultats attendus.
