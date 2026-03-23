# Architecture du projet

## Vue d'ensemble

- Nom du projet: `MutliplayerTemplate`
- Scène principale: `res://main/main.tscn`
- Type de projet: jeu Godot multijoueur coopératif en 3D, avec UI en jeu, inventaire, ennemis, VOIP et logique de partie.

Le point d'entrée réel est la scène [`main/main.tscn`](/home/camillej/godotProjects/godot-multiplayer/main/main.tscn). Elle compose les systèmes réseau, UI, match, spawn des joueurs, niveau et services annexes.

## Arborescence logique

- `main/`: orchestration globale de la partie, réseau, spawns, match, bombe, chutes.
- `player/`: scène joueur, contrôles, caméra, combat, inventaire local, synchronisation réseau.
- `player/components/`: sous-composants du joueur pour découper la logique métier.
- `ui/`: HUD, menus, panneaux d'inventaire, liste des joueurs.
- `inventory/`: composant d'inventaire, coffre, items monde.
- `levels/`: scènes de niveau et zones interactives.
- `enemies/`: ennemis et leurs comportements.
- `user_data/`: données utilisateur réseau/répliquées.
- `voip/`: voix en jeu.
- `test/`: tests GUT et E2E UI.

## Scène racine

### `main/main.tscn`

Rôle: assembler le jeu.

Noeuds principaux:

- `Connection` -> [`main/connection.gd`](/home/camillej/godotProjects/godot-multiplayer/main/connection.gd)
- `UserDataManager` -> [`user_data/user_data_manager.tscn`](/home/camillej/godotProjects/godot-multiplayer/user_data/user_data_manager.tscn)
- `VoipManager` -> [`voip/voip_manager.gd`](/home/camillej/godotProjects/godot-multiplayer/voip/voip_manager.gd)
- `UI` -> [`ui/ui.tscn`](/home/camillej/godotProjects/godot-multiplayer/ui/ui.tscn)
- `Players` -> conteneur des joueurs spawnés
- `PlayerSpawner` -> [`main/player_spawner.gd`](/home/camillej/godotProjects/godot-multiplayer/main/player_spawner.gd)
- `FallChecker` -> [`main/fall_checker.gd`](/home/camillej/godotProjects/godot-multiplayer/main/fall_checker.gd)
- `MatchDirector` -> [`main/match_director.gd`](/home/camillej/godotProjects/godot-multiplayer/main/match_director.gd)
- `HubLevel` -> [`levels/hub_level.tscn`](/home/camillej/godotProjects/godot-multiplayer/levels/hub_level.tscn)

Le `HubLevel` contient notamment:

- le décor et les plateformes
- les points de spawn
- les ennemis (`bee_bot`)
- les interactifs (`Coin`, `ApplePickup`, `WoodPickup`, `Chest`, `BombDoor`)

## Systèmes principaux

### Réseau

#### `main/connection.gd`

Classe: `Connection`

Responsabilité:

- démarrer le serveur ENet
- connecter un client
- suivre les connexions/déconnexions
- publier un état texte du serveur pour l'UI
- fermer proprement une session serveur/client

Grandes fonctions:

- `start_server()`: crée le peer ENet serveur et branche les signaux réseau
- `start_client()`: crée le peer ENet client et branche les callbacks de connexion
- `disconnect_peer()`: coupe la session locale
- `shutdown_server()`: demande aux clients de se fermer avant arrêt
- `peer_connected()` / `peer_disconnected()`: met à jour la liste des clients
- `_print_server_status()`: produit le texte d'état affiché dans l'UI

### Partie / règles globales

#### `main/match_director.gd`

Classe: `MatchDirector`

Responsabilité:

- piloter l'état global de la partie
- suivre le timer, les vies, les scores, les morts et les objectifs
- décider victoire/défaite
- exposer un snapshot texte unique pour l'UI

Etat central:

- `MatchState`: `LOBBY`, `RUNNING`, `WON`, `LOST`, `RESETTING`
- `_score_by_peer`
- `_lives_by_peer`
- `_deaths_by_peer`
- `_team_progress`

Grandes fonctions:

- `start_match()`: démarre une partie et initialise le timer
- `reset_to_lobby()`: remet le match à zéro
- `report_team_won()` / `report_team_lost()`: change l'état terminal
- `register_player_spawn()` / `unregister_player()`: tient à jour les peers actifs
- `report_player_fell()`: enlève une vie après chute
- `request_respawn()`: autorise et déclenche un respawn
- `report_enemy_killed()`: crédite score et progression
- `report_objective_progress()`: avance les objectifs coop

## Checklist Late Join

Pour tout objet gameplay persistant visible par les joueurs, vérifier explicitement le cas "joueur qui rejoint après changement d'état".

Règle à appliquer :
- si l'objet reste dans la scène après changement d'état, il doit exposer une resynchronisation explicite de son état courant pour les late joiners
- soit par `peer_connected` côté serveur
- soit par une RPC `request_current_state()` côté client
- idéalement les deux

Objets déjà couverts :
- `BombDoor`
- `WorldItem`
- `InventoryContainer3D`
- `BeeBot`
- `MatchDirector`
- `set_player_lives()`: point d'entrée unique pour modifier les vies
- `get_snapshot_text()`: fabrique le texte utilisé par l'UI

#### `main/fall_checker.gd`

Classe: `FallChecker`

Responsabilité:

- surveiller périodiquement si les joueurs tombent sous une hauteur donnée
- décrémenter les vies côté serveur
- déclencher respawn ou état "down" si plus de vies

Grandes fonctions:

- `player_spawned()` / `player_despawned()`: ajoute ou retire un joueur du suivi
- `check_fallen()`: boucle serveur qui applique la logique de chute
- `_sync_lives_to_player()`: pousse les vies vers l'instance joueur
- `_sync_dead_state_to_player()`: pousse l'état mort/down

### Spawn et cycle de vie des joueurs

#### `main/player_spawner.gd`

Classe: `PlayerSpawner`

Responsabilité:

- instancier les joueurs réseau
- assigner leur autorité multijoueur
- positionner les respawns

Grandes fonctions:

- `create_player(id)`: spawn serveur d'un joueur
- `destroy_player(id)`: despawn serveur
- `respawn_player(id)`: repositionne et relance le joueur
- `custom_spawn(vars)`: callback du `MultiplayerSpawner`
- `get_player_or_null(id)`: lookup d'un joueur par peer id

## Joueur

### `player/player.tscn`

Rôle: scène du joueur répliqué.

Sous-noeuds structurants:

- `CameraController`
- `PlayerCamera`
- `PullRay`
- `InteractionArea`
- `GroundShapeCast`
- `CharacterRotationRoot`
- `MeleeAttackArea`
- `CharacterSkin`
- `Inventory`
- `Nickname`
- `LivesOverlay`
- `DeathOverlay`
- `MultiplayerSynchronizer`

### `player/player.gd`

Classe: `Player`

Responsabilité:

- entrée principale du gameplay joueur
- déléguer mouvement/combat/lifecycle/netcode/interactions à des composants
- gérer l'inventaire local et les requêtes serveur liées à l'inventaire
- exposer les RPC de synchro du joueur

Grands blocs:

- input et ouverture/fermeture de l'inventaire
- physique et mouvement autoritatif
- combat et bombes
- inventaire joueur et cible d'inventaire
- RPC serveur pour pickup, drop, transferts
- dégâts, vies, revival

Grandes fonctions:

- `_unhandled_input()`: filtre l'input hors mode inventaire
- `_physics_process()`: route vers autorité locale ou interpolation distante
- `toggle_inventory_mode()`: ouvre/ferme l'inventaire et cible un conteneur proche
- `set_focused_inventory_target()`: définit coffre/joueur cible
- `request_pickup_world_item()`: pickup d'un item monde via serveur
- `request_drop_inventory_slot()`: drop d'un slot
- `request_transfer_to_target()` / `request_transfer_from_target()`: transferts sac <-> cible
- `_server_pickup_world_item()`: validation serveur du pickup
- `_server_drop_inventory_slot()`: validation serveur du drop
- `_server_transfer_inventory_to_target()` / `_server_transfer_inventory_from_target()`: validation serveur du transfert
- `damage()`: entrée dégâts
- `try_revive_with_coin()`: tentative de revive

### `player/components/`

Ce dossier découpe `Player` en sous-systèmes:

- `player_movement.gd`: déplacement, pente, saut, orientation
- `player_combat.gd`: attaques et collisions de combat
- `player_lifecycle.gd`: vies, mort, respawn, overlays
- `player_net_sync.gd`: synchro/interpolation client
- `player_interactions.gd`: bombes, pickup, focus inventaire, interactions monde
- `player_ui_test_driver.gd`: scénarios dédiés aux tests UI E2E

Important: `player.gd` sert de façade et orchestre ces composants.

## Inventaire et interactifs

### `inventory/inventory_component.gd`

Classe: `InventoryComponent`

Responsabilité:

- stocker des slots d'objets
- gérer stack, ajout, retrait, sérialisation et transfert

Grandes fonctions:

- `get_contents()`: lecture sûre du contenu
- `load_contents()`: recharge depuis une version sérialisée
- `serialize_contents()`: export pour RPC/snapshot
- `can_add_payload()` / `add_payload()`: validation + insertion
- `remove_from_slot()`: retire une quantité
- `transfer_to()`: transfert atomique vers un autre inventaire
- `count_item()`: comptage total par `item_id`

### `inventory/inventory_container.tscn`

Rôle: coffre/containeur 3D dans le monde.

Composition:

- `StaticBody3D`
- `Label3D`
- `Inventory` avec [`inventory_component.gd`](/home/camillej/godotProjects/godot-multiplayer/inventory/inventory_component.gd)

### `inventory/inventory_container.gd`

Classe: `InventoryContainer3D`

Responsabilité:

- représenter un coffre synchronisé en multijoueur
- initialiser son contenu serveur
- pousser des snapshots d'inventaire aux clients

Grandes fonctions:

- `_seed_initial_contents()`: remplit le coffre au démarrage
- `_broadcast_inventory_snapshot()`: diffuse le contenu
- `request_chest_snapshot()`: permet à un client de redemander l'état actuel
- `sync_inventory_snapshot()`: applique un snapshot reçu
- `_refresh_label()`: met à jour le `Label3D`

### `inventory/world_item.tscn` / `inventory/world_item.gd`

Rôle:

- item ramassable placé dans le niveau
- conversion en payload d'inventaire
- disparition/réapparition synchronisée après pickup

## UI

### `ui/ui.tscn`

Rôle: HUD et menus.

Sous-ensembles principaux:

- `MainMenu`: boutons serveur/client
- `InGameUI`: HUD actif en jeu
- `ServerStatus`: statut serveur + snapshot match
- `MatchTimer`
- `PlayerInventoryPanel`
- `TargetInventoryPanel`
- `MarginContainer/ScrollContainer`: liste des joueurs
- `InventoryToggleButton`

### `ui/ui.gd`

Responsabilité:

- piloter le menu principal et le HUD
- afficher le statut réseau et le timer de match
- rafraîchir en continu les panneaux d'inventaire
- relayer les actions UI vers le joueur local

Grandes fonctions:

- `start_server_emit()` / `connect_client_emit()`: relai vers `Connection`
- `_refresh_server_status_visibility()`: visibilité du HUD
- `_update_server_status_label()` / `_update_match_timer_label()`: rendu texte
- `_refresh_inventory_panels()`: remplit les panneaux sac/cible
- `_on_player_inventory_action_requested()`: `drop` ou `give`
- `_on_external_inventory_action_requested()`: `take`
- `_on_inventory_toggle_button_pressed()`: ouvre/ferme le sac

### `ui/inventory_panel.tscn` / `ui/inventory_panel.gd`

Rôle:

- widget de panneau d'inventaire réutilisable
- affiche slots, actions et hint
- remonte les clics via signaux

## Ennemis et combat

### `enemies/bee_bot.tscn`

Rôle: ennemi volant.

Composition notable:

- `RigidBody3D` racine
- `PlayerDetectionArea`
- `ReactionLabel`
- `MeshRoot`
- animations de réaction et de flottement

### `enemies/bee_bot.gd`

Responsabilité:

- détection du joueur
- patrouille / poursuite
- tir de projectiles
- dégâts, mort et score
- réplication de l'état vivant/supprimé

Grandes fonctions:

- `_physics_process()`: comportement principal
- `_update_target_from_overlaps()`: acquisition de cible
- `_update_patrol_circle()`: patrouille circulaire
- `_spawn_bee_bullet()`: tir
- `damage()` / `_apply_damage()`: réception des dégâts
- `_finalize_death()`: fin de vie
- `_report_score_for_kill()`: notification au `MatchDirector`

### `main/bomb.gd`

Classe: `Bomb`

Responsabilité:

- compter le fuse
- exploser localement
- appliquer les dégâts côté serveur
- notifier les objets réactifs à une explosion

Grandes fonctions:

- `_update_countdown_label()`
- `_explode()`
- `_apply_explosion_damage()`
- `_notify_bomb_reactives()`

## User data et VOIP

### `user_data/user_data_manager.gd`

Classe: `UserDataManager`

Responsabilité:

- suivre les `UserData` répliquées par peer
- exposer `my_user_data`
- relayer spawn/despawn au bus `UserDataEvents`

Grandes fonctions:

- `user_data_spawned()`
- `user_data_despawned()`
- `try_get_user_data()`

### `voip/voip_manager.gd`

Responsabilité:

- capturer et envoyer des chunks Opus côté client
- créer/supprimer les `VoipUser` distants
- ancrer chaque flux audio au joueur correspondant

Grandes fonctions:

- `peer_connected()` / `peer_disconnected()`
- `player_spawned()`
- `_process()`: collecte et envoi audio
- `opus_data_received()`: réception et dispatch

## Flux général d'exécution

### Démarrage

1. `main/main.tscn` charge les systèmes.
2. `Connection` décide serveur/client selon la ligne de commande.
3. `UI` affiche ou masque le menu.
4. Le serveur crée les joueurs via `PlayerSpawner`.
5. `MatchDirector` suit les peers et publie un snapshot de match.

### Boucle de jeu

1. Le joueur local pilote `Player`.
2. `Player` délègue aux composants de mouvement/combat/interactions.
3. Les interactions d'inventaire passent toujours par des RPC serveur.
4. `UI` lit l'état du joueur local et du match pour afficher le HUD.
5. `FallChecker` et `MatchDirector` pilotent vies, respawns et fin de partie.

### Interactions d'inventaire

1. Le joueur ouvre son sac.
2. `PlayerInteractionsComponent` choisit une cible proche: item, coffre, parfois joueur.
3. `Player` envoie une requête serveur.
4. `InventoryComponent` applique l'opération.
5. Les snapshots du coffre et du sac sont renvoyés vers l'UI.

## Points d'entrée utiles selon le besoin

- gameplay joueur: [`player/player.gd`](/home/camillej/godotProjects/godot-multiplayer/player/player.gd)
- règles de partie: [`main/match_director.gd`](/home/camillej/godotProjects/godot-multiplayer/main/match_director.gd)
- réseau/session: [`main/connection.gd`](/home/camillej/godotProjects/godot-multiplayer/main/connection.gd)
- HUD/inventaire UI: [`ui/ui.gd`](/home/camillej/godotProjects/godot-multiplayer/ui/ui.gd)
- système d'inventaire: [`inventory/inventory_component.gd`](/home/camillej/godotProjects/godot-multiplayer/inventory/inventory_component.gd)
- coffre synchronisé: [`inventory/inventory_container.gd`](/home/camillej/godotProjects/godot-multiplayer/inventory/inventory_container.gd)
- ennemi principal: [`enemies/bee_bot.gd`](/home/camillej/godotProjects/godot-multiplayer/enemies/bee_bot.gd)

## Remarques d'architecture

- L'architecture est fortement orientée scène Godot + scripts spécialisés.
- `main/main.tscn` joue le rôle de composition root.
- `Player` est la classe métier la plus dense, mais une partie importante a déjà été découpée dans `player/components/`.
- `MatchDirector` centralise bien les règles globales et simplifie l'UI en exposant un snapshot texte unique.
- Le système d'inventaire est proprement séparé entre stockage (`InventoryComponent`), représentation monde (`world_item`) et conteneur (`InventoryContainer3D`).
