# Tests UI E2E (test/UI)

Tests de haut niveau qui lancent plusieurs instances Godot (Xvfb), automatisent l’UI avec xdotool et vérifient le comportement via captures et fichiers de sync.

## Exécution en ligne de commande

```bash
# Coffre (1 instance)
./test/UI/test_inventory_chest_ui.sh [OUT_DIR]

# Transfert multijoueur (serveur + client_a + client_b)
./test/UI/test_inventory_transfer_multiplayer_ui.sh [OUT_DIR]
```

Prérequis : Linux, Xvfb, xdotool, ImageMagick (`import`), python3, PIL.

## Intégration à la suite GUT

Les tests E2E sont appelés depuis GUT via le script **`test/test_ui_e2e.gd`** :

- **Sans variable d’environnement** : les deux tests (coffre, transfert multijoueur) sont ignorés (retour immédiat, succès).
- **Avec `RUN_UI_E2E=1`** (et Linux) : GUT exécute `test_inventory_chest_ui.sh` et `test_inventory_transfer_multiplayer_ui.sh` et vérifie que le code de sortie est 0.

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
