# Où modifier quoi

Guide rapide pour savoir dans quels fichiers intervenir selon le type de changement voulu.

## Si tu modifies le lancement d'une partie ou la session réseau

Fichiers à regarder:

- [`main/main.tscn`](/home/camillej/godotProjects/godot-multiplayer/main/main.tscn)
- [`main/connection.gd`](/home/camillej/godotProjects/godot-multiplayer/main/connection.gd)
- [`ui/ui.gd`](/home/camillej/godotProjects/godot-multiplayer/ui/ui.gd)

Tu touches ici pour:

- changer le port, l'adresse ou la façon de lancer serveur/client
- modifier la fermeture propre d'une session
- afficher plus ou moins d'infos de statut réseau
- changer le comportement du menu principal

Points d'entrée utiles:

- `Connection.start_server()`
- `Connection.start_client()`
- `Connection.shutdown_server()`
- `UI.start_server_emit()`
- `UI.connect_client_emit()`

## Si tu modifies les règles globales de partie

Fichiers à regarder:

- [`main/match_director.gd`](/home/camillej/godotProjects/godot-multiplayer/main/match_director.gd)
- [`main/fall_checker.gd`](/home/camillej/godotProjects/godot-multiplayer/main/fall_checker.gd)
- [`main/player_spawner.gd`](/home/camillej/godotProjects/godot-multiplayer/main/player_spawner.gd)

Tu touches ici pour:

- changer le nombre de vies initiales
- modifier les conditions de victoire/défaite
- ajuster le timer de partie
- décider quand un joueur peut respawn
- changer la logique quand un joueur tombe

Points d'entrée utiles:

- `MatchDirector.start_match()`
- `MatchDirector.report_team_won()`
- `MatchDirector.report_team_lost()`
- `MatchDirector.set_player_lives()`
- `MatchDirector.request_respawn()`
- `FallChecker.check_fallen()`
- `PlayerSpawner.respawn_player()`

## Si tu modifies le déplacement ou les contrôles du joueur

Fichiers à regarder:

- [`player/player.gd`](/home/camillej/godotProjects/godot-multiplayer/player/player.gd)
- [`player/components/player_movement.gd`](/home/camillej/godotProjects/godot-multiplayer/player/components/player_movement.gd)
- [`player/camera_controller.gd`](/home/camillej/godotProjects/godot-multiplayer/player/camera_controller.gd)
- [`player/camera.gd`](/home/camillej/godotProjects/godot-multiplayer/player/camera.gd)
- [`player/player.tscn`](/home/camillej/godotProjects/godot-multiplayer/player/player.tscn)

Tu touches ici pour:

- changer la vitesse, l'accélération, le saut
- modifier le comportement sur les pentes
- ajuster la caméra ou le raycast d'interaction
- revoir le mapping de l'input côté joueur

Règle pratique:

- logique de façade, RPC et état global du joueur: `player/player.gd`
- vrai calcul de mouvement: `player/components/player_movement.gd`
- composition des noeuds et colliders: `player/player.tscn`

## Si tu modifies le combat joueur

Fichiers à regarder:

- [`player/components/player_combat.gd`](/home/camillej/godotProjects/godot-multiplayer/player/components/player_combat.gd)
- [`player/melee_attack_area.gd`](/home/camillej/godotProjects/godot-multiplayer/player/melee_attack_area.gd)
- [`player/player.gd`](/home/camillej/godotProjects/godot-multiplayer/player/player.gd)
- [`main/bomb.gd`](/home/camillej/godotProjects/godot-multiplayer/main/bomb.gd)
- [`main/static_body_3d_bomb.tscn`](/home/camillej/godotProjects/godot-multiplayer/main/static_body_3d_bomb.tscn)

Tu touches ici pour:

- changer l'attaque melee
- modifier la portée ou les colliders d'attaque
- revoir la bombe, son fuse, son rayon, sa force
- changer comment les dégâts sont appliqués

Points d'entrée utiles:

- `Player.attack()`
- `Player.place_bomb()`
- `Bomb._explode()`
- `Bomb._apply_explosion_damage()`

## Si tu modifies les vies, la mort, le respawn ou le revive

Fichiers à regarder:

- [`player/components/player_lifecycle.gd`](/home/camillej/godotProjects/godot-multiplayer/player/components/player_lifecycle.gd)
- [`player/player.gd`](/home/camillej/godotProjects/godot-multiplayer/player/player.gd)
- [`main/fall_checker.gd`](/home/camillej/godotProjects/godot-multiplayer/main/fall_checker.gd)
- [`main/match_director.gd`](/home/camillej/godotProjects/godot-multiplayer/main/match_director.gd)

Tu touches ici pour:

- changer l'affichage des vies
- modifier l'état mort/down
- revoir le respawn
- ajuster la revive avec pièce

Points d'entrée utiles:

- `Player.set_dead_state()`
- `Player.set_lives()`
- `Player.try_revive_with_coin()`
- `MatchDirector.set_player_lives()`

## Si tu modifies l'inventaire

Fichiers à regarder:

- [`inventory/inventory_component.gd`](/home/camillej/godotProjects/godot-multiplayer/inventory/inventory_component.gd)
- [`player/player.gd`](/home/camillej/godotProjects/godot-multiplayer/player/player.gd)
- [`player/components/player_interactions.gd`](/home/camillej/godotProjects/godot-multiplayer/player/components/player_interactions.gd)
- [`inventory/inventory_container.gd`](/home/camillej/godotProjects/godot-multiplayer/inventory/inventory_container.gd)
- [`inventory/world_item.gd`](/home/camillej/godotProjects/godot-multiplayer/inventory/world_item.gd)
- [`inventory/item_definition.gd`](/home/camillej/godotProjects/godot-multiplayer/inventory/item_definition.gd)

Tu touches ici pour:

- changer le format des slots
- modifier le stacking
- ajuster pickup, drop, transfert
- changer la synchro des coffres
- créer de nouveaux types d'items

Règle pratique:

- structure interne de l'inventaire: `inventory_component.gd`
- actions du joueur sur l'inventaire: `player.gd` et `player_interactions.gd`
- coffre monde: `inventory_container.gd`
- item ramassable dans le monde: `world_item.gd`

Points d'entrée utiles:

- `InventoryComponent.add_payload()`
- `InventoryComponent.remove_from_slot()`
- `InventoryComponent.transfer_to()`
- `Player.request_pickup_world_item()`
- `Player.request_drop_inventory_slot()`
- `Player.request_transfer_to_target()`
- `Player.request_transfer_from_target()`

## Si tu modifies l'UI ou le HUD

Fichiers à regarder:

- [`ui/ui.tscn`](/home/camillej/godotProjects/godot-multiplayer/ui/ui.tscn)
- [`ui/ui.gd`](/home/camillej/godotProjects/godot-multiplayer/ui/ui.gd)
- [`ui/inventory_panel.tscn`](/home/camillej/godotProjects/godot-multiplayer/ui/inventory_panel.tscn)
- [`ui/inventory_panel.gd`](/home/camillej/godotProjects/godot-multiplayer/ui/inventory_panel.gd)
- [`ui/player_panel.tscn`](/home/camillej/godotProjects/godot-multiplayer/ui/player_panel.tscn)
- [`ui/player_panel.gd`](/home/camillej/godotProjects/godot-multiplayer/ui/player_panel.gd)

Tu touches ici pour:

- changer le layout du HUD
- revoir les panneaux d'inventaire
- modifier les boutons serveur/client
- afficher d'autres infos de match ou de réseau
- changer la liste des joueurs

Règle pratique:

- structure visuelle: `.tscn`
- logique d'affichage et callbacks: `.gd`

Points d'entrée utiles:

- `UI._refresh_inventory_panels()`
- `UI._update_server_status_label()`
- `UI._update_match_timer_label()`
- `UI._on_player_inventory_action_requested()`
- `UI._on_external_inventory_action_requested()`

## Si tu modifies les ennemis

Fichiers à regarder:

- [`enemies/bee_bot.tscn`](/home/camillej/godotProjects/godot-multiplayer/enemies/bee_bot.tscn)
- [`enemies/bee_bot.gd`](/home/camillej/godotProjects/godot-multiplayer/enemies/bee_bot.gd)
- [`player/bullet.tscn`](/home/camillej/godotProjects/godot-multiplayer/player/bullet.tscn)
- [`player/bullet.gd`](/home/camillej/godotProjects/godot-multiplayer/player/bullet.gd)

Tu touches ici pour:

- changer la détection du joueur
- modifier la patrouille
- revoir le tir ou le projectile
- ajuster les dégâts ou la mort
- changer comment le kill remonte au `MatchDirector`

Points d'entrée utiles:

- `bee_bot._physics_process()`
- `bee_bot._update_target_from_overlaps()`
- `bee_bot._spawn_bee_bullet()`
- `bee_bot._apply_damage()`
- `bee_bot._report_score_for_kill()`

## Si tu modifies le niveau ou les objets placés

Fichiers à regarder:

- [`levels/hub_level.tscn`](/home/camillej/godotProjects/godot-multiplayer/levels/hub_level.tscn)
- [`main/main.tscn`](/home/camillej/godotProjects/godot-multiplayer/main/main.tscn)
- [`levels/fall_respawn_zone.tscn`](/home/camillej/godotProjects/godot-multiplayer/levels/fall_respawn_zone.tscn)
- [`levels/fall_respawn_zone.gd`](/home/camillej/godotProjects/godot-multiplayer/levels/fall_respawn_zone.gd)
- [`main/bomb_door.gd`](/home/camillej/godotProjects/godot-multiplayer/main/bomb_door.gd)

Tu touches ici pour:

- déplacer les spawns
- ajouter ou retirer des pickups/coffres/ennemis
- modifier la géométrie du hub
- revoir les interactions d'objets de niveau

Règle pratique:

- placement global du monde joué: `main/main.tscn`
- détail du décor et du hub: `levels/hub_level.tscn`

## Si tu modifies la VOIP

Fichiers à regarder:

- [`voip/voip_manager.gd`](/home/camillej/godotProjects/godot-multiplayer/voip/voip_manager.gd)
- [`voip/voip_user.gd`](/home/camillej/godotProjects/godot-multiplayer/voip/voip_user.gd)
- [`voip/voip_user.tscn`](/home/camillej/godotProjects/godot-multiplayer/voip/voip_user.tscn)
- [`voip/microphone.gd`](/home/camillej/godotProjects/godot-multiplayer/voip/microphone.gd)

Tu touches ici pour:

- changer la capture micro
- ajuster l'envoi Opus
- ancrer différemment la voix dans le monde
- ajouter des indicateurs vocaux

## Si tu modifies les données utilisateur répliquées

Fichiers à regarder:

- [`user_data/user_data_manager.gd`](/home/camillej/godotProjects/godot-multiplayer/user_data/user_data_manager.gd)
- [`user_data/user_data.gd`](/home/camillej/godotProjects/godot-multiplayer/user_data/user_data.gd)
- [`user_data/user_data_spawner.gd`](/home/camillej/godotProjects/godot-multiplayer/user_data/user_data_spawner.gd)
- [`user_data/user_data_events.gd`](/home/camillej/godotProjects/godot-multiplayer/user_data/user_data_events.gd)

Tu touches ici pour:

- stocker le pseudo, couleur, préférences ou autres métadonnées joueur
- brancher des réactions UI quand un user data arrive ou disparaît

## Si tu modifies les tests

Fichiers à regarder:

- [`test/`](/home/camillej/godotProjects/godot-multiplayer/test)
- [`test/UI/`](/home/camillej/godotProjects/godot-multiplayer/test/UI)
- [`player/components/player_ui_test_driver.gd`](/home/camillej/godotProjects/godot-multiplayer/player/components/player_ui_test_driver.gd)

Tu touches ici pour:

- ajouter des tests unitaires GUT
- ajouter des tests d'intégration
- maintenir les scénarios E2E UI

Règle pratique:

- logique de test GUT: `test/*.gd`
- orchestration UI E2E: `test/UI/*`
- comportement spécial côté runtime pour les tests UI: `player_ui_test_driver.gd`

## Heuristique rapide

Si tu veux modifier:

- un comportement visible du personnage: commence par [`player/player.gd`](/home/camillej/godotProjects/godot-multiplayer/player/player.gd)
- une règle de partie: commence par [`main/match_director.gd`](/home/camillej/godotProjects/godot-multiplayer/main/match_director.gd)
- un panneau ou bouton: commence par [`ui/ui.tscn`](/home/camillej/godotProjects/godot-multiplayer/ui/ui.tscn) puis [`ui/ui.gd`](/home/camillej/godotProjects/godot-multiplayer/ui/ui.gd)
- un problème de coffre ou de stack: commence par [`inventory/inventory_component.gd`](/home/camillej/godotProjects/godot-multiplayer/inventory/inventory_component.gd)
- un souci de synchro joueur: commence par [`player/components/player_net_sync.gd`](/home/camillej/godotProjects/godot-multiplayer/player/components/player_net_sync.gd)
- un problème de spawn/respawn: commence par [`main/player_spawner.gd`](/home/camillej/godotProjects/godot-multiplayer/main/player_spawner.gd) et [`main/fall_checker.gd`](/home/camillej/godotProjects/godot-multiplayer/main/fall_checker.gd)
