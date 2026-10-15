# FinTrack Production Platform

Projet avancé 2 de la série FinTrack Analytics — Sécurité, Gouvernance, CI/CD, Observabilité, Power BI.

Voir [`MISSION.md`](./MISSION.md) pour le briefing métier sprinté.

---

## Prérequis

- **Projet FinTrack Perf & Scale (Avancé 1) terminé** — base Snowflake `FINTRACK_PROD` avec données chargées et modèles dbt fonctionnels
- Python 3.11+
- dbt-snowflake >= 1.8
- Airflow 2.9+ (Astronomer / MWAA / self-hosted)
- Compte GitHub avec Actions activées
- Power BI Desktop
- Compte Elementary Cloud (optionnel — free tier suffit)

---

## Intégration avec l'Avancé 1 — étape indispensable

Ce projet **étend** le projet Perf & Scale, il ne le remplace pas. Vous devez fusionner les deux projets dbt en un seul avant de démarrer, sinon les références (`ref('dim_comptes')`, `ref('fct_transactions')`) échoueront.

### Option recommandée — Fusion en un seul projet dbt

Partez de votre dossier `fintrack-perf-scale/` et ajoutez-y le contenu de `fintrack-production-platform/` :

```bash
# À la racine de votre repo Avancé 1
cd fintrack-perf-scale

# Copier les nouveaux modèles dbt
cp -r ../fintrack-production-platform/dbt/models/marts/secure_views/ dbt/models/marts/
cp -r ../fintrack-production-platform/dbt/models/exposures.yml dbt/models/

# Copier les nouvelles macros
cp    ../fintrack-production-platform/dbt/macros/drop_schema.sql dbt/macros/
cp    ../fintrack-production-platform/dbt/macros/generate_schema_name.sql dbt/macros/
cp -r ../fintrack-production-platform/dbt/macros/grants/   dbt/macros/
cp -r ../fintrack-production-platform/dbt/macros/security/ dbt/macros/

# Copier le test sécurité
cp -r ../fintrack-production-platform/dbt/tests/security/ dbt/tests/

# Copier scripts Snowflake, orchestration, observability, powerbi, docs
cp -r ../fintrack-production-platform/scripts/snowflake/security/   scripts/snowflake/
cp -r ../fintrack-production-platform/scripts/snowflake/audit/      scripts/snowflake/
cp -r ../fintrack-production-platform/scripts/snowflake/governance/ scripts/snowflake/
cp -r ../fintrack-production-platform/scripts/snowflake/maintenance/ scripts/snowflake/
cp    ../fintrack-production-platform/scripts/python/cleanup_ci_schemas.py scripts/python/
cp -r ../fintrack-production-platform/orchestration/ ./
cp -r ../fintrack-production-platform/observability/ ./
cp -r ../fintrack-production-platform/powerbi/       ./
cp -r ../fintrack-production-platform/tests/         ./

# Copier les docs (ADR, runbooks, architecture)
cp -r ../fintrack-production-platform/docs/adr/          docs/
cp -r ../fintrack-production-platform/docs/runbooks/     docs/
cp -r ../fintrack-production-platform/docs/architecture/ docs/

# Copier les workflows GitHub Actions et la config pre-commit
cp -r ../fintrack-production-platform/.github/         ./
cp    ../fintrack-production-platform/.pre-commit-config.yaml ./

# Remplacer les fichiers de config par ceux enrichis de l'Avancé 2
cp    ../fintrack-production-platform/dbt/dbt_project.yml       dbt/    # ⚠️ merge manuel avec l'ancien si vous avez ajouté des variables
cp    ../fintrack-production-platform/dbt/packages.yml          dbt/    # idem
cp    ../fintrack-production-platform/dbt/profiles.yml.example  dbt/

# Remplacer MISSION.md et README.md (garder les anciens en archive)
mv    MISSION.md docs/MISSION_avance_1.md
mv    README.md  docs/README_avance_1.md
cp    ../fintrack-production-platform/MISSION.md ./
cp    ../fintrack-production-platform/README.md  ./
```

### Points de vigilance

1. **`dbt_project.yml`** — celui de l'Avancé 2 ajoute la section `marts/secure_views`, les `on-run-start/end` hooks, les `+grants`, et un nom de projet différent. **Si vous aviez personnalisé le vôtre, faites un merge manuel** plutôt qu'un remplacement brut. Le champ `name:` doit rester cohérent avec votre `profiles.yml`.

2. **`packages.yml`** — l'Avancé 2 ajoute `elementary-data/elementary`. Si vous aviez d'autres packages, gardez-les.

3. **Rôles Snowflake** — le script `04_roles_and_grants.sql` crée les rôles fonctionnels (`FINTRACK_ANALYST_ROLE`, `_SUPPORT_ROLE`, `_COMPLIANCE_ROLE`, etc.) qui n'existaient pas en Avancé 1. Exécutez-le **avant** les scripts de masking (02) et RAP (03) qui les référencent.

4. **Modèles marts de l'Avancé 1** — ils reçoivent les Row Access Policies via `ALTER TABLE ... ADD ROW ACCESS POLICY` dans le script 03. Assurez-vous que `dim_comptes`, `fct_transactions`, `fct_virements` existent bien avant de lancer ce script (sinon commentez temporairement les 3 lignes concernées).

5. **Snapshots** — le snapshot `snapshot_comptes` de l'Avancé 1 reste actif. L'Avancé 2 n'y touche pas mais s'appuie dessus pour `dim_comptes_scd2`.

---

## Ordre d'exécution après fusion

```bash
# Une fois les fichiers fusionnés :

# 1. Rôles Snowflake (nouveau — dépendance de tout le reste)
snowsql -f scripts/snowflake/security/04_roles_and_grants.sql

# 2. Gouvernance : tags + masking + RAP
snowsql -f scripts/snowflake/security/01_tag_classification.sql
snowsql -f scripts/snowflake/security/02_masking_policies.sql
snowsql -f scripts/snowflake/security/03_row_access_policies.sql

# 3. Audit + RGPD + métriques
snowsql -f scripts/snowflake/audit/05_access_history_views.sql
snowsql -f scripts/snowflake/governance/06_rgpd_purge_procedure.sql
snowsql -f scripts/snowflake/maintenance/07_pipeline_metrics.sql

# 4. dbt — installer le nouveau package Elementary et re-run
cd dbt
dbt deps
dbt run --select tag:marts   # applique les +grants aux tables existantes
dbt run --select secure_views  # crée les nouvelles vues sécurisées
dbt test --exclude tag:todo

# 5. Elementary (première synchro)
edr monitor

# 6. Airflow — copier les DAGs
cp -r orchestration/airflow/dags/*     $AIRFLOW_HOME/dags/
cp -r orchestration/airflow/plugins/*  $AIRFLOW_HOME/plugins/

# 7. GitHub Actions — pousser sur GitHub avec les secrets configurés

# 8. Power BI — suivre powerbi/guides/01_connection_snowflake.md
```

---

## Structure du repo après fusion

```
fintrack-perf-scale/                    (dossier racine — nom conservé de l'Avancé 1)
├── MISSION.md                          Avancé 2 (nouveau briefing)
├── README.md                           Ce fichier
├── docs/
│   ├── MISSION_avance_1.md             Archive de la Mission Perf & Scale
│   ├── README_avance_1.md              Archive du README Perf & Scale
│   ├── adr/                            5 ADR nouveaux
│   ├── runbooks/                       Runbooks incident + RGPD
│   └── architecture/                   Diagrammes flux, sécurité, deployment
├── dbt/                                Fusion des deux projets
│   ├── dbt_project.yml                 Version Avancé 2 (avec hooks + grants)
│   ├── packages.yml                    + Elementary
│   ├── models/
│   │   ├── staging/                    Avancé 1
│   │   ├── intermediate/               Avancé 1
│   │   └── marts/
│   │       ├── core/                   Avancé 1
│   │       ├── finance/                Avancé 1
│   │       ├── analytics/              Avancé 1
│   │       └── secure_views/           Avancé 2 (nouveau)
│   ├── macros/                         Fusion
│   ├── snapshots/                      Avancé 1
│   ├── tests/                          Fusion (+ security/)
│   └── unit_tests/                     Avancé 1
├── scripts/
│   ├── python/                         Fusion (générateur + cleanup)
│   └── snowflake/                      Fusion (7 dossiers thématiques)
├── orchestration/                      Avancé 2
├── observability/                      Avancé 2
├── powerbi/                            Avancé 2
├── tests/integration/                  Avancé 2
├── .github/workflows/                  Avancé 2
├── .pre-commit-config.yaml             Avancé 2
├── .sqlfluff                           Avancé 1 (conserver)
└── .gitignore                          Fusion
```

---

## Suivi de mission

Cocher au fur et à mesure :

- [ ] **Étape 0** — Fusion Avancé 1 + Avancé 2 réussie, `dbt debug` OK
- [ ] Sprint 1 — Multi-tenancy & Isolation
- [ ] Sprint 2 — PII & Masking
- [ ] Sprint 3 — Rôles, Grants, RGPD
- [ ] Sprint 4 — CI/CD
- [ ] Sprint 5 — Airflow Production
- [ ] Sprint 6 — Observability
- [ ] Sprint 7 — Power BI & Activation

Chaque sprint doit produire un livrable listé dans `MISSION.md`.

---

## Commandes utiles

```bash
# Recompiler les modèles avec les grants après changement de rôle
dbt run --select tag:marts

# Tester uniquement la sécurité
dbt test --select tag:security tag:marts

# Simuler une PR CI en local
DBT_CI_PR_ID=999 dbt build --target ci --select state:modified+ --defer --state target-prod/

# Purger un compte RGPD (Airflow)
airflow dags trigger fintrack_rgpd_purge --conf '{"compte_id": 42, "reason": "RGPD-1234", ...}'

# Voir les coûts par projet (audit)
snowsql -q "SELECT * FROM FINTRACK_PROD.AUDIT.vw_costs_by_project_7d"
```

---

## En cas de problème

- **Erreur `Object not found`** sur un modèle de l'Avancé 1 → la fusion est incomplète, vérifier que `dbt list --resource-type model` liste bien les modèles Perf & Scale
- **Erreur de grant** sur un rôle inexistant → exécuter `04_roles_and_grants.sql` d'abord
- **RAP bloque le `dbt run`** → vérifier que `FINTRACK_TRANSFORM_ROLE` est bien dans la liste des rôles bypass de la RAP
- **Elementary ne trouve pas ses tables** → `dbt run --select elementary` doit être lancé une première fois manuellement
