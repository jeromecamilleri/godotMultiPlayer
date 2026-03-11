# Architectures d'inventaire envisagées

## 1. Inventaire central global (autoload)
- Avantage: très rapide à brancher.
- Limite: couplage fort, plus fragile en multijoueur, séparation UI/gameplay plus faible.

## 2. Inventaire par nœud avec objets en `Resource`
- Avantage: code simple, compatible avec l'éditeur Godot, UI branchée via signaux/snapshots, sérialisation directe du contenu.
- Avantage: extensible avec de nouveaux types d'objets via `ItemDefinition`.
- Avantage: s'adapte bien au multijoueur en gardant les mutations serveur-autoritatives.

## 3. Inventaire ECS/données pures
- Avantage: très flexible pour des systèmes complexes.
- Limite: surdimensionné pour ce projet, plus coûteux à relier à l'UI Godot.

## Choix retenu

L'architecture 2 a été retenue.

Raisons:
- Simplicité: un `InventoryComponent` réutilisable sur joueur/coffre.
- Extension: nouveaux objets via `ItemDefinition` sans réécrire le cœur.
- UI Godot: l'interface consomme des snapshots simples (`Array[Dictionary]`).
- Sauvegarde: le contenu est déjà sérialisable en JSON.
- Multijoueur: les demandes de pickup/drop/transfert passent par le serveur, puis l'état est diffusé à tous les pairs.
