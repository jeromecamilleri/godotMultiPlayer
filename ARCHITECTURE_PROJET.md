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
- `UiTestScenarioServerPilot` -> [`main/ui_test_scenario_server_pilot.gd`](/home/camillej/godotProjects/godot-multiplayer/main/ui_test_scenario_server_pilot.gd)
- `HubLevel` -> [`levels/hub_level.tscn`](/home/camillej/godotProjects/godot-multiplayer/levels/hub_level.tscn)
- `ZoneScierie` -> [`levels/zones/zone_scierie.tscn`](/home/camillej/godotProjects/godot-multiplayer/levels/zones/zone_scierie.tscn)
- `ZoneVerger` -> [`levels/zones/zone_verger.tscn`](/home/camillej/godotProjects/godot-multiplayer/levels/zones/zone_verger.tscn)
- `ZoneBreche` -> [`levels/zones/zone_breche.tscn`](/home/camillej/godotProjects/godot-multiplayer/levels/zones/zone_breche.tscn)
- `ZoneReactor` -> [`levels/zones/zone_reactor.tscn`](/home/camillej/godotProjects/godot-multiplayer/levels/zones/zone_reactor.tscn)

Le `HubLevel` contient notamment:

- le décor et les plateformes
- les points de spawn
- les interactifs du hub (`Chest`, `Coin`)
- les portails de progression vers les autres zones

Le `UiTestScenarioServerPilot` ne fait pas partie du gameplay normal. Il sert uniquement aux scénarios UI complexes qui doivent préparer un état de monde côté serveur, en restant cohérents avec l'architecture autoritaire.
Les scénarios actuellement servis par ce pilote sont `beetle_targeting`, `beetle_door_charge` et `portal_unlock`.

Les autres zones portent désormais les objectifs spécialisés:

- `ZoneScierie`: bois, caisses et scarabées de défense locale
- `ZoneVerger`: pommes et pression abeilles
- `ZoneBreche`: caisses bloqueuses + `BombDoor` + scarabées de défense locale
- `ZoneReactor`: gros cube, `CubeActivator`, scarabées de défense du réacteur

Sous-scènes mission désormais extraites depuis `main/` :

- `main/mission_cube_beetle_director.tscn` : encapsule le `BeetleDirector` et ses ancres de défense autour de l'Activator.
- `main/mission_cube_goal_zone.tscn` : encapsule la plateforme `Activator` et sa zone `CubeActivator`.
- `main/mission_hub_enemies.tscn` : encapsule le runtime `Enemies` du hub (abeilles + `BeetleDirector`).
- `main/mission_zone_verger_enemies.tscn` : encapsule les abeilles dédiées au verger.
- `main/mission_zone_breche_enemies.tscn` : encapsule le `BeetleDirector` et ses ancres de défense de la brèche.
- `main/mission_cube_physics_objects.tscn` : encapsule `PhysicsObjects` et les cubes physiques de mission.
- `main/mission_hub_interactives.tscn` : encapsule les interactifs du hub.
- `main/mission_zone_scierie_interactives.tscn` : encapsule les ressources/caisses de la scierie.
- `main/mission_zone_verger_interactives.tscn` : encapsule les ressources du verger.
- `main/mission_zone_breche_interactives.tscn` : encapsule les caisses bloqueuses et les `BombDoor` de la brèche.

Leur racine conserve les mêmes noms (`Enemies`, `PhysicsObjects`, `BeetleDirector`, `Interactives`) afin de préserver les chemins existants et les tests.

### Progression multi-zone

La progression courante de la map élargie est la suivante :

- `Hub -> Scierie` et `Hub -> Verger` actifs dès le début
- `Hub -> Breche` activé par le quota de ressources déposé dans le coffre du hub
- `Hub -> Reactor` activé après ouverture des `BombDoor` de la brèche
- chaque zone expose aussi un portail retour vers le hub

Les tests UI haut niveau s'appuient sur cette progression réelle, pas sur une scène de test séparée.

Les scénarios UI multi-zone actuellement stabilisés couvrent :

- la logistique réelle via portails (`portal_logistics`)
- le déverrouillage du portail de la brèche par dépôt au coffre (`portal_unlock`)
- la mission finale du cube dans la zone réacteur (`cube_mission`)

Le scénario `beetle_targeting` s'appuie désormais sur une préparation autoritaire côté serveur via `UiTestScenarioServerPilot`, au lieu d'un simple repositionnement déclenché depuis les clients de test.
Le scénario `portal_unlock` suit maintenant la même règle : le serveur prépare explicitement `client_a` près du bois et `client_b` près des pommes, attend les accusés de réception clients, puis laisse les clients observer/jouer le dépôt réel au coffre.

### Identité visuelle des zones

La map multi-zone utilise maintenant deux repères visuels stables :

- chaque portail expose un libellé de destination lisible et un état visuel explicite (`BLOQUE` rouge / `OUVERT` vert)
- chaque zone principale expose un marqueur de zone simple et visible de loin (`SCIERIE`, `VERGER`, `BRECHE`, `REACTOR`)

Ces repères doivent rester purement visuels :

- aucune logique de progression ne doit dépendre de ces marqueurs
- la vérité gameplay reste portée par `MatchDirector` et les groupes de portails

## Debug réseau / gameplay

Le HUD expose un mode debug activable avec `F3` via [`ui/ui.gd`](/home/camillej/godotProjects/godot-multiplayer/ui/ui.gd).

Ce mode doit rester purement observateur :

- état du `MatchDirector`
- cibles ennemies (abeilles / scarabées)
- état et révision des objets persistants répliqués
- mesures de réplication utiles
- événements récents de synchronisation

Le nœud [`main/connection.gd`](/home/camillej/godotProjects/godot-multiplayer/main/connection.gd) sert aussi de bus local de debug via le groupe `connection_service` et l'historique `record_sync_event(...)`.

Quand possible, préférer aussi `get_recent_sync_event_entries()` pour récupérer une vue structurée (`source`, `detail`, `text`, `metadata`) exploitable par l'overlay `F3` et les tests.

Quand un nouvel objet persistant est ajouté, penser à :

- exposer des getters de debug simples si l'état est utile à lire en `F3`
- enregistrer un événement de sync sur les transitions importantes
- conserver la logique gameplay autoritaire côté serveur

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

### Groupes gameplay stables

Pour limiter les couplages aux `NodePath` fragiles dans `main/main.tscn`, préférer les groupes stables suivants :

- `mission_cube_goal_zones` : zone objectif de la mission cube (`CubeActivator`)
- `mission_cube_bomb_doors` : portes destructibles de la mission cube
- `mission_cube_blockers` : caisses qui bloquent le passage du cube
- `mission_cube_primary` : gros cube coop principal
- `mission_cube_beetle_directors` : directeur scarabées de la mission cube
- `mission_hub_chests` : coffre principal du hub
- `mission_portal_hub_scierie` : portail hub vers la scierie
- `mission_portal_hub_verger` : portail hub vers le verger
- `mission_portal_hub_breche` : portail hub vers la brèche
- `mission_portal_hub_reactor` : portail hub vers le réacteur
- `mission_breche_beetle_directors` : directeur scarabées de la brèche
- `mission_resource_pickups` : pickups de ressources visibles par les tests/scénarios
- `mission_wood_pickups` : pickups de bois utilisés par les scénarios multi-zone
- `mission_apple_pickups` : pickups de pommes utilisés par les scénarios multi-zone
- `enemy_directors` : groupe générique des directeurs d'ennemis
- `enemy_instances` : groupe générique des ennemis gérés par un directeur
- `replicated_persistent_objects` : groupe générique des objets gameplay persistants exposant le contrat de resync/debug

Les scénarios UI et le debug doivent privilégier ces groupes aux recherches récursives par nom.

Pour les scénarios UI de map élargie, éviter les recherches par noms du type `WoodPickup`, `ApplePickup`, car plusieurs zones peuvent contenir des nœuds homonymes. Préférer systématiquement les groupes gameplay stables.

## Checklist Late Join

Pour tout objet gameplay persistant visible par les joueurs, vérifier explicitement le cas "joueur qui rejoint après changement d'état".

Règle à appliquer :
- si l'objet reste dans la scène après changement d'état, il doit exposer une resynchronisation explicite de son état courant pour les late joiners
- soit par `peer_connected` côté serveur
- soit par une RPC `request_current_state()` côté client
- idéalement les deux

### Convention objet persistant répliqué

Pour homogénéiser les systèmes et les tests, tout objet gameplay persistant visible par les joueurs doit tendre vers l'API publique suivante :

- `request_current_state_from_server()`
- `push_current_state_to_peer(peer_id)`
- `get_state_revision()`
- `get_debug_sync_summary()`

Interprétation :

- `request_current_state_from_server()` : point d'entrée client unique pour demander un resync au serveur
- `push_current_state_to_peer(peer_id)` : point d'entrée serveur unique pour pousser l'état courant à un peer
- `get_state_revision()` : entier monotone ou révision équivalente permettant de savoir si l'état durable a changé
- `get_debug_sync_summary()` : résumé texte court utilisable dans l'overlay `F3` et les tests

Règles de mise en oeuvre :

- l'autorité serveur reste la seule source de vérité
- toute transition durable doit incrémenter ou mettre à jour `get_state_revision()`
- toute transition durable importante doit idéalement appeler `record_sync_event(...)` via `Connection`
- les tests GUT doivent vérifier au minimum la présence de ce contrat sur les objets persistants majeurs

Objets déjà couverts :
- `BombDoor`
- `WorldItem`
- `InventoryContainer3D`
- `Coin`
- `BeeBot`
- `BeetleBot`
- `PullableCube`
- `Box`
- `BeeDirector`
- `BeetleDirector`
- `MatchDirector`

Remarques d'audit :
- `CubeActivator` ne porte pas d'état visuel persistant indépendant ; il délègue l'état durable au `PullableCube` et au `MatchDirector`.
- `Portal` ne conserve pas d'état de monde persistant visible entre joueurs ; son cooldown local n'a pas besoin d'une resynchronisation late join dédiée.
- pour les directeurs d'ennemis, préférer des `NodePath` explicites (zone de défense, graines/anchors) à un scan implicite de la scène, afin de garder un comportement déterministe quand la map évolue.
- `set_player_lives()`: point d'entrée unique pour modifier les vies
- `get_snapshot_text()`: fabrique le texte utilisé par l'UI

### Conventions directeurs / ennemis

Contrat minimal désormais attendu pour les ennemis gérés par un directeur :

- `set_director_active(active)`
- `apply_director_config(config)`
- `get_current_target_peer_id()`
- `get_assigned_target_peer_id()`
- appartenance au groupe `replicated_persistent_objects`

Contrat minimal désormais attendu pour les directeurs :

- appartenance au groupe `enemy_directors`
- appartenance au groupe `replicated_persistent_objects`
- push explicite de l'état courant aux late joiners
- configuration explicite des graines/anchors quand la scène le permet
- héritage préféré depuis `EnemyDirectorBase` pour mutualiser groupes, révision, debug et helpers de scène

Pour les instances d'ennemis, préférer l'héritage depuis `EnemyInstanceBase` afin de mutualiser :

- le groupe `enemy_instances`
- le groupe `replicated_persistent_objects`
- la révision d'état
- le contrat public de resynchronisation/debug

L'objectif est de garder des flux homogènes entre abeilles et scarabées sans multiplier les variantes de debug ou de resynchronisation.

### Réplication du coffre

`InventoryContainer3D` conserve un snapshot complet comme source de vérité pour :

- le late join
- la récupération après trou de révision
- le push sur `peer_connected`

Pendant le jeu, le coffre diffuse maintenant de préférence des deltas de slots modifiés quand ils sont plus compacts qu'un snapshot complet. En cas de trou de révision ou de payload invalide, le client redemande automatiquement un snapshot complet au serveur.

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
