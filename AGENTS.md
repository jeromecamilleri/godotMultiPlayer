# AGENTS.md

## Project Overview

Multiplayer Godot 3D cooperative game.

Architecture is server-authoritative with RPC-based synchronization.
Core systems include: networking, player lifecycle, inventory, UI, enemies, and VOIP.

Main entry point:

* `main/main.tscn`

---

## Core Principles

* Server is authoritative for all gameplay logic
* Clients must never diverge from server state
* All persistent gameplay elements must support late join synchronization
* Prefer modifying existing systems rather than duplicating logic
* Keep code modular (respect current component split)

---

## How to Work

When solving a task or bug:

1. Identify the subsystem:

   * network / match / player / inventory / UI / enemy / VOIP

2. Locate authoritative logic:

   * Server-side logic first (RPC endpoints, state mutation)

3. Trace data flow:

   * client → RPC → server → broadcast → clients

4. Check side effects:

   * UI updates
   * inventory consistency
   * match state

5. Check late join behavior:

   * Will a new player see correct state?

6. Only then implement changes

---

## Critical Multiplayer Rules

* Never trust client input without server validation

* All state changes must originate or be validated on server

* Any persistent object must:

  * either react to `peer_connected`
  * or implement `request_current_state()`
  * ideally both

* After modification:

  * verify synchronization across multiple clients
  * verify late join consistency

---

## Iteration Loop (MANDATORY)

After ANY code modification:

1. Run the game or tests
2. Observe logs / behavior
3. Validate expected outcome
4. If incorrect:

   * refine hypothesis
   * update code
5. Repeat until stable

Never stop after a single attempt.

---

## Commands

* Run project:
  godot --path .

* Run unit tests (GUT):
  ./run_tests.sh

* Run specific tests:
  ./run_tests.sh --filter <test_name>

* Check logs:
  tail -f logs/game.log

---

## Testing Strategy (STRICT)

### General Rule

Any code change MUST be validated with tests.

---

### 1. Unit Tests (GUT)

Location:

* `test/`

Requirements:

* ALWAYS run existing tests after modification

* If a bug is fixed:
  → add a test reproducing the bug

* If a new function is added:
  → add unit tests covering:

  * normal case
  * edge cases
  * invalid inputs

---

### 2. Integration Tests

Location:

* `test/integration/`

Required when:

* multiple systems interact (network + inventory, player + match, etc.)

Examples:

* inventory transfer between players
* respawn affecting match state
* enemy kill updating score

---

### 3. UI High-Level Tests (E2E)

Location:

* `test/UI/`

Required when:

* UI behavior changes
* visual workflows are modified
* user interactions change

Examples:

* opening inventory
* transferring items via UI
* displaying match state

Optional if change is minor, REQUIRED if UX flow changes.

---

### 4. New Feature Rule (MANDATORY)

If a modification introduces a new feature:

You MUST:

1. Add unit tests (GUT) in `test/`
2. Add integration tests in `test/integration/` if relevant
3. Add UI test in `test/UI/` if feature is visible to player
4. Ensure tests pass before considering task complete

---

### 5. Regression Safety

After changes:

* run full test suite
* ensure no existing test is broken
* if broken:
  → fix code, NOT tests (unless test is wrong)

---

## Code Modification Rules

* Modify the smallest possible surface
* Do not refactor unrelated code unless necessary
* Keep naming consistent with existing codebase
* Respect existing architecture:

  * Player = façade
  * Components = logic
  * MatchDirector = global state

---

## Performance and Stability

* Avoid unnecessary RPC calls
* Avoid duplicating state
* Prefer deterministic logic
* Ensure no desync between peers

---

## Done Criteria

A task is complete ONLY IF:

* Code compiles and runs
* Behavior matches expected result
* Multiplayer synchronization is correct
* Late join works
* All tests pass
* New tests are added if needed

---

## Anti-Patterns (FORBIDDEN)

* Fixing symptoms instead of root cause
* Adding client-side hacks to hide server bugs
* Skipping tests
* Breaking existing synchronization
* Ignoring late join consistency
* Modifying multiple systems without justification

---

## Heuristics

* Player issue → start in `player/player.gd`
* Match issue → `main/match_director.gd`
* Network issue → `main/connection.gd`
* Inventory issue → `inventory/inventory_component.gd`
* UI issue → `ui/ui.gd`
* Sync issue → `player/components/player_net_sync.gd`

---

## Final Instruction

Work incrementally, validate constantly, and prioritize correctness over speed.

This project is multiplayer and stateful:
small mistakes lead to desynchronization bugs.

Always think before modifying.

