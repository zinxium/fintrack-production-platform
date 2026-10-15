# Mission — FinTrack Production Platform

**Client :** FinTrack Analytics — plateforme B2B2C
**Rôle :** Consultant Data Engineer Senior / Tech Lead
**Durée :** 10 à 12 jours ouvrés (7 sprints)
**Environnement :** Snowflake + dbt Core 1.8+ + Airflow + GitHub Actions + Power BI + Elementary

---

## Contexte

FinTrack tourne maintenant à 15 tenants et ~50M transactions/mois. La pipeline
technique optimisée par vos travaux précédents (projet Perf & Scale) fait le job.

Mais un audit externe vient de tomber :

- 🚨 **Aucune isolation stricte multi-tenant** : un incident logique pourrait
  exposer les données d'un tenant à un autre
- 🚨 **PII en clair** dans les marts consommés par Power BI
- 🚨 **Aucune piste d'audit** sur les accès aux données sensibles
- 🚨 **Aucune procédure de droit à l'oubli** RGPD outillée
- 🚨 **Zéro CI/CD** : les changements dbt vont directement en prod par un
  copier-coller de branche
- 🚨 **Pipeline non observée** : les failles sont détectées par les clients
  avant l'équipe data
- 🚨 **Power BI mal configuré** : tous les analystes voient tous les tenants

Le CTO vous confie la mission :

> « On a un audit CNIL prévu dans 12 semaines. Il faut qu'on soit
> irréprochable sur la partie sécurité et gouvernance. Et il nous
> faut une plateforme qu'on puisse faire évoluer sans casser la prod.
> Vous avez 10 jours pour mettre tout ça en place. »

---

## Objectifs et livrables

À la fin de la mission :

1. **Multi-tenancy strict** — impossible qu'un tenant voie les données d'un autre
2. **PII masquées par défaut** — seuls quelques rôles peuvent démasquer, avec audit
3. **Droit à l'oubli** opérationnel — procédure documentée + DAG Airflow
4. **CI/CD complète** — pas de merge sans passer les tests, blue/green deploy
5. **Airflow production** — orchestration robuste avec SLA, retries, alerting
6. **Data Observability** — Elementary configuré, alertes Slack sur anomalies
7. **Power BI** — modèle sémantique avec RLS composable Snowflake

---

## Sprint 1 — Multi-tenancy & Isolation (Jour 1-2)

### US 1.1 — Row Access Policies
**En tant que** RSSI,
**je veux** qu'aucun utilisateur métier ne puisse voir les données d'un tenant
non autorisé,
**afin de** garantir l'étanchéité contractuelle B2B2C.

**Critères d'acceptation :**
- Table `GOVERNANCE.user_tenant_access` créée avec granularité utilisateur
- Row Access Policy `rap_tenant_isolation` appliquée sur `raw_comptes`,
  `raw_transactions`, `raw_virements`, ainsi que sur les faits/dim MARTS
- Un utilisateur test attribué à 2 tenants ne voit que ces 2 tenants dans TOUTES
  les requêtes possibles (`SELECT DISTINCT tenant_id ...`)
- Les rôles techniques (`FINTRACK_TRANSFORM_ROLE`, `_INGESTION_ROLE`) court-circuitent
  la RAP (transformation dbt fonctionne)

**Base fournie :** `scripts/snowflake/security/03_row_access_policies.sql`

### US 1.2 — Secure Views
- Créer les modèles `vw_comptes_masked` et `vw_transactions_summary`
  (déjà scaffoldés) avec `secure=true`
- Grants réservés aux rôles métier via `+grants` dbt

**Livrable :** RAP + secure views fonctionnels + test d'isolation documenté.

---

## Sprint 2 — PII & Masking (Jour 3)

### US 2.1 — Tag-based classification
Exécuter `scripts/snowflake/security/01_tag_classification.sql` et vérifier
que `SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES` liste bien tous les tags posés
(attention : latence de 2h sur cette vue).

### US 2.2 — Dynamic Masking Policies
- Exécuter `02_masking_policies.sql`
- Tester chaque policy avec 3 rôles différents (ADMIN, ANALYST, SUPPORT)
- Documenter le comportement dans `docs/adr/002-masking-approach.md`

### US 2.3 — Post-hook dbt pour propager les masking sur marts
Utiliser la macro `apply_masking_policies()` fournie dans
`dbt/macros/security/apply_masking_via_dbt.sql`. Activer sur `dim_comptes`
et vérifier que les colonnes PII sont bien masquées après un `dbt run`.

**Livrable :** matrice de test masking (10 lignes × 3 rôles) dans `docs/`.

---

## Sprint 3 — Rôles, Grants, RGPD (Jour 4-5)

### US 3.1 — Refonte de la hiérarchie de rôles
Appliquer le pattern **functional + access roles** documenté dans
`04_roles_and_grants.sql`. Migrer les utilisateurs existants (script fourni).

### US 3.2 — Grants automatisés dans dbt
- Utiliser `+grants` dans `dbt_project.yml` (déjà configuré)
- Vérifier via `SHOW GRANTS ON TABLE dim_comptes` que les grants sont bien posés
- Ajouter des tests dans `dbt/tests/security/`

### US 3.3 — Procédure droit à l'oubli
- Déployer la procédure `rgpd_purge_compte` (`06_rgpd_purge_procedure.sql`)
- Créer le DAG Airflow `fintrack_rgpd_purge` (fourni)
- **Rédiger** le runbook `docs/runbooks/rgpd_purge_procedure.md`
- Simuler une purge sur un compte de test et vérifier via `rgpd_purge_log`

**Livrable :** DAG RGPD fonctionnel + runbook validé compliance.

---

## Sprint 4 — CI/CD (Jour 6-7)

### US 4.1 — Slim CI GitHub Actions
- Configurer les secrets GitHub (`SNOWFLAKE_*`)
- Créer une PR de test qui modifie 1 modèle
- Vérifier que la CI ne rebuild QUE ce modèle + downstream
- Cleanup automatique du schéma CI après la PR

### US 4.2 — Blue/Green production deploy
- Configurer les secrets prod (clé RSA)
- Adapter `dbt_prod_deploy.yml` à votre topologie de schémas
- Faire un dry-run sans le swap final
- Documenter les critères de smoke-test dans `tests/integration/`

### US 4.3 — Pre-commit hooks et security scan
- Installer les hooks (`pre-commit install`)
- Résoudre les issues remontées
- Configurer Gitleaks (le workflow est fourni)

**Livrable :** CI verte + un blue/green deploy réussi + rollback documenté.

---

## Sprint 5 — Airflow Production (Jour 8-9)

### US 5.1 — DAG quotidien production
- Déployer `fintrack_daily_pipeline` (fourni)
- Configurer les connections Airflow (Snowflake, Slack)
- Tester le ExternalTaskSensor sur un DAG amont fictif
- Vérifier les SLA callbacks

### US 5.2 — DAG RGPD
Déployé au Sprint 3, à re-tester end-to-end ici.

### US 5.3 — Callbacks Slack standardisés
Utiliser le plugin `slack_callbacks.py`. Documenter la matrice
sévérité × canal dans `observability/alerts/slack_alerting.md`.

**Livrable :** DAG en prod avec 1 semaine de runs verts consécutifs.

---

## Sprint 6 — Observability (Jour 10)

### US 6.1 — Installer Elementary
```bash
cd dbt && dbt deps
dbt run --select elementary
```

### US 6.2 — Configurer les monitors
Ajouter les tests `elementary.volume_anomalies`, `freshness_anomalies`,
`column_anomalies` sur les modèles critiques.

### US 6.3 — Report HTML + Slack
```bash
edr monitor
edr send-report --slack-channel '#data-quality-alerts'
```

Automatiser dans le DAG Airflow (déjà fait dans le DAG fourni).

**Livrable :** premier rapport Elementary avec au moins 1 anomalie détectée
(vous pouvez la simuler en modifiant des données).

---

## Sprint 7 — Power BI & Activation (Jour 11-12)

### US 7.1 — Modèle sémantique
Suivre `powerbi/model/semantic_model.md` pour construire le modèle dans Power BI Desktop.

### US 7.2 — Bibliothèque DAX
Importer les mesures de `powerbi/measures/dax_library.md`.

### US 7.3 — Composable RLS
Configurer selon `powerbi/guides/02_composable_rls.md`. Tester avec 2
utilisateurs de tenants différents que le rapport affiche des données isolées.

### US 7.4 — Incremental refresh
Configurer sur `f_transactions` selon `03_incremental_refresh.md`.

### US 7.5 — Reverse ETL
Configurer un sync Hightouch (compte trial) vers un HubSpot sandbox
ou simuler avec un webhook. Documenter dans une exposure dbt.

**Livrable :** un `.pbit` fonctionnel + rapport publié sur un workspace Power BI.

---

## Livrables finaux

1. **Le repo complet** avec tous les scripts, modèles, DAGs, workflows
2. **`docs/adr/`** — 5 ADRs formels
3. **`docs/runbooks/`** — runbooks incident + RGPD
4. **`docs/architecture/`** — diagrammes de flux, sécurité, deployment
5. **Preuve d'exécution :**
   - Screenshot RAP en action
   - Matrice masking testée
   - Rapport Elementary
   - PR mergée avec CI verte
   - Screenshot dashboard Power BI avec RLS

6. **Rapport de mission** (3-4 pages) :
   - Audit CNIL : suis-je prêt ? liste des risques résiduels
   - Comparaison avant/après : sécurité, vélocité, MTTD (mean time to detect)
   - 3 propositions d'évolution 6 mois

---

## Ressources

- [Snowflake — Row Access Policies](https://docs.snowflake.com/en/user-guide/security-row)
- [Snowflake — Dynamic Data Masking](https://docs.snowflake.com/en/user-guide/security-column-ddm)
- [dbt — Grants config](https://docs.getdbt.com/reference/resource-configs/grants)
- [dbt — Model access](https://docs.getdbt.com/docs/collaborate/govern/model-access)
- [Elementary Data](https://docs.elementary-data.com/)
- [Airflow — Slack provider](https://airflow.apache.org/docs/apache-airflow-providers-slack/)
- [Power BI — Composite models](https://learn.microsoft.com/power-bi/transform-model/desktop-composite-models)
- [Power BI — Composable RLS](https://learn.microsoft.com/power-bi/enterprise/service-admin-rls)
