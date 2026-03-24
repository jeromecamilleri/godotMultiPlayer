# Tests UI E2E (test/UI)

Tests de haut niveau qui lancent plusieurs instances Godot (Xvfb), automatisent l’UI avec xdotool et vérifient le comportement via captures et fichiers de sync.

## Conventions de test stables

L’UI écrit maintenant un snapshot de layout de test quand `UI_TEST_SYNC_DIR` ou `UI_TEST_CHEST_SYNC_DIR` est défini :

- `ui_layout_<role>.json`

Chaque entrée contient notamment :

- `test_id`
- `visible`
- `disabled`
- `text`
- `x`, `y`, `width`, `height`
- `center_x`, `center_y`

Exemples de `test_id` stables :

- `start_server_button`
- `start_client_button`
- `server_ip_input`
- `server_port_input`
- `inventory_toggle_button`
- `player_inventory_panel`
- `player_inventory_panel_slot_0`
- `player_inventory_panel_action_drop`
- `external_inventory_panel_slot_0`
- `external_inventory_panel_action_take`

Pour les tests, il faut privilégier ces identifiants et des assertions tolérantes :

- chercher `start_server_button` au lieu d’un clic fixe `x=... y=...`
- vérifier `cube_on_goal_visual == true` ou “dans la zone cible” plutôt qu’une position exacte
- vérifier qu’un inventaire contient l’objet attendu plutôt qu’un ordre pixel-perfect

## Exécution en ligne de commande

```bash
# Coffre (1 instance)
./test/UI/test_inventory_chest_ui.sh [OUT_DIR]

# Transfert multijoueur (serveur + client_a + client_b)
./test/UI/test_inventory_transfer_multiplayer_ui.sh [OUT_DIR]

# Late join après bombe + pickup bois (serveur + client_a, puis client_b en retard)
./test/UI/test_late_join_bomb_wood_ui.sh [OUT_DIR]

# Mission cube coop (serveur + client_a + client_b)
./test/UI/test_cube_mission_ui.sh [OUT_DIR]

# Mission cube coop avec lock L simulé sur client_a
./test/UI/test_cube_mission_lock_ui.sh [OUT_DIR]

# Campagne de charge réplication (par défaut 10 joueurs, ou liste "2,4,6,8,10")
./test/UI/test_replication_stress_ui.sh [OUT_DIR] [PLAYER_COUNTS]
```

Prérequis : Linux, Xvfb, xdotool, ImageMagick (`import`), python3, PIL.

## Intégration à la suite GUT

Les tests E2E sont appelés depuis GUT via le script **`test/test_ui_e2e.gd`** :

- **Sans variable d’environnement** : les deux tests (coffre, transfert multijoueur) sont ignorés (retour immédiat, succès).
- **Avec `RUN_UI_E2E=1`** (et Linux) : GUT exécute `test_inventory_chest_ui.sh`, `test_inventory_transfer_multiplayer_ui.sh`, `test_late_join_bomb_wood_ui.sh`, `test_cube_mission_ui.sh` et `test_cube_mission_lock_ui.sh` et vérifie que le code de sortie est 0.

Le test de charge `test_replication_stress_ui.sh` n’est pas branché dans `RUN_UI_E2E=1` par défaut, car il est volontairement plus lourd.

### Charge réplication multijoueur

Par défaut, le script écrit dans :

```bash
/tmp/replication-stress-ui
```

Il lance un serveur + `N` clients sous `Xvfb`, enchaîne un scénario réel :

- ouverture du mur à la bombe
- collecte d’objets
- transferts vers le coffre
- observation de la propagation sur tous les clients

Sorties utiles :

- `players_<N>/01_grid_before_roles.png`
- `players_<N>/02_grid_after_roles.png`
- `players_<N>/03_grid_stress_done.png`
- `players_<N>/summary.txt`

Le résumé donne notamment :

- `door_replication_max_ms`
- `chest_replication_max_ms`
- `door_fanout_ms`
- `chest_wood_fanout_ms`
- `chest_apple_fanout_ms`
- `scenario_complete_ms`

## Sorties utiles

### Mission cube coop

Par défaut, le script écrit dans :

```bash
/tmp/cube-mission-ui
```

Captures principales :

- `01_before_cube_mission.png` : vue initiale des 3 fenêtres
- `02_client_a_cube_mission_won.png` : écran joueur A montrant `WON`
- `03_client_b_cube_mission_won.png` : écran joueur B montrant `WON`
- `04_after_cube_mission.png` : vue globale finale

Fichiers de synchro gameplay :

- `cube_mission_client_a.json`
- `cube_mission_client_b.json`
- `cube_mission_server.json`

Le test valide maintenant la vraie mécanique réseau/physique :

- les deux clients tirent réellement le cube
- le cube atteint l’activateur
- le serveur et les deux clients observent `state = WON`
- `cube_goal = true` sur les trois vues synchronisées

### Mission cube coop avec lock

Par défaut, le script écrit dans :

```bash
/tmp/cube-mission-lock-ui
```

Ce scénario couvre le cas manuel `L` :

- `client_a` ouvre le mur, commence la traction puis active un lock de position
- `client_b` continue la poussée
- la mission doit quand même aboutir

Pour lancer la suite GUT en incluant les tests UI E2E :

```bash
RUN_UI_E2E=1 godot --path . --headless -s addons/gut/gut_cmdln.gd -gdir=test -gfile=test_ui_e2e.gd
```

### Lancer Godot avec `RUN_UI_E2E=1` pour exécuter les E2E depuis l’éditeur

Pour que GUT exécute vraiment les tests E2E (et non les « ignorer »), la variable doit être définie **avant** le démarrage de Godot. Deux possibilités :

1. **Démarrer Godot depuis un terminal** (recommandé) :
   ```bash
   cd /chemin/vers/godot-multiplayer
   RUN_UI_E2E=1 godot .
   ```
   Puis dans l’éditeur : GUT → lancer les tests (Run All ou uniquement `test_ui_e2e.gd`). Les scripts `test/UI/*.sh` seront exécutés.

2. **Exporter la variable dans la session, puis lancer Godot** :
   ```bash
   export RUN_UI_E2E=1
   godot .
   ```

Si Godot est lancé sans `RUN_UI_E2E=1` (icône, menu système, etc.), la variable n’est pas définie et les deux tests E2E sont marqués comme ignorés (avec un assert explicite pour éviter « Did not assert »).
