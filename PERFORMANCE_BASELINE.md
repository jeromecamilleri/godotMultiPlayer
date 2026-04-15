# Performance Baseline

Date: 2026-04-15T23:28:00+02:00
Repo commit: `98cdd3d` (worktree non clean)
Godot: `/dataSSD/Godot_v4.6.2-stable_linux.x86_64`

## Objectif
Figer des valeurs de référence pour détecter plus tard une dégradation nette sur le stress de réplication multijoueur.

## Campagne exécutée

### Stress de réplication (référence active)
Commandes:
- `bash ./test/UI/test_replication_stress_ui.sh /tmp/replication-stress-ui-fix2 2`
- `bash ./test/UI/test_replication_stress_ui.sh /tmp/replication-stress-ui-fix4 4`

Résultat:
- Le blocage `BLOCKED_MISSING_RESULT_FILES` est corrigé.
- Les fichiers `replication_stress_client_*.json` sont bien générés en 2 et 4 joueurs.
- Santé actuelle: `UNSTABLE` dès 2 joueurs.

### Baseline mesurée

#### 2 joueurs (`/tmp/replication-stress-ui-fix2/players_2/summary.txt`)
- `health=UNSTABLE`
- `incomplete_clients=2`
- `rtt_avg_p50_ms=432.4`
- `rtt_avg_p95_ms=439.1`
- `rtt_last_max_ms=435.0`
- `jitter_p95_ms=79.0`
- `chest_replication_max_ms=1108.0`
- `scenario_complete_ms=28196.0`

#### 4 joueurs (`/tmp/replication-stress-ui-fix4/players_4/summary.txt`)
- `health=UNSTABLE`
- `incomplete_clients=4`
- `rtt_avg_p50_ms=476.9`
- `rtt_avg_p95_ms=491.9`
- `rtt_last_max_ms=476.0`
- `jitter_p95_ms=61.4`
- `apple_replication_max_ms=504.0`
- `chest_replication_max_ms=1264.0`
- `apple_fanout_ms=1704.0`
- `chest_apple_fanout_ms=1933.0`
- `scenario_complete_ms=28387.0`

## Règles d'alerte pour comparaison future
- Alerte `WARN` si une métrique clé augmente de `+15%` par rapport à la baseline ci-dessus.
- Alerte `CRITIQUE` si augmentation de `+30%`.
- Alerte `CRITIQUE` immédiate si retour de `missing result files` ou hausse de `incomplete_clients`.

## Statut baseline
- `stress_replication_status = UNSTABLE`
- `blocked_missing_result_files = RESOLVED`
