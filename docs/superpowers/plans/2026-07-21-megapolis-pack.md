# Megapolis Pack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new selectable ruleset — a business-themed board ("Мегаполия") with its own Tax Office / Vacation / Exchange corner mechanics — as an independent pack (`packs/megapolis`) that does not modify `classic.json` or break existing gameplay.

**Architecture:** Three generic engine mechanics are added to `core/GameController.gd`/`core/GameRules.gd`/`core/PlayerState.gd` (cell types `tax_office`, `vacation`, `exchange`, plus a ruleset-configurable card-deck id so a pack's own "Шанс"/"Деньги" cards don't mix with `core`'s). A new pack `packs/megapolis` then supplies content only (cells, ruleset, cards) using those generic mechanics — no pack-specific code in `core`.

**Tech Stack:** Godot 4.6, GDScript, JSON content packs (existing `ModLoader`/`PackRegistry` system).

## Global Constraints

- Do not modify `packs/core/content/rulesets/classic.json` or any `classic` behavior — this must be purely additive.
- Every new cell type must be resolvable by any future ruleset, not hardcoded to `megapolis` — implement via cell `type` strings and ruleset config fields, the same pattern `core` already uses.
- No jail mechanic on the new board: `in_jail`/`jail_turns`/`get_out_cards` are not triggered anywhere in the new content.
- Tax Office rate: 20 000 per owned property (spec §4). Exchange stake: 100 000 win/lose (spec §4).
- Spec source of truth: `docs/superpowers/specs/2026-07-21-megapolis-pack-design.md`.

---

### Task 1: `GameRules.portfolio_tax` + ruleset-configurable card deck ids

**Files:**
- Modify: `core/GameRules.gd` (append after line 158, end of file)
- Modify: `core/GameController.gd:56-58` (`configure`)
- Test: `tests/portfolio_tax_test.gd` (new)

**Interfaces:**
- Produces: `GameRules.portfolio_tax(peer_id: int, states: Dictionary, tax_per_business: int) -> int` — used by Task 3.
- Produces: `ruleset["chance_deck_id"]` / `ruleset["treasury_deck_id"]` (optional ruleset JSON fields, default `"chance"`/`"treasury"`) — used by Task 9's `business.json`.

- [ ] **Step 1: Write the failing test**

Create `D:\MonopolyGodot\monopolia\tests\portfolio_tax_test.gd`:

```gdscript
extends SceneTree

func _init() -> void:
	var failures := 0
	failures += _check(GameRules.portfolio_tax(1, {}, 20000) == 0, "no properties -> 0 tax")
	var props := {
		0: _owned_by(1),
		1: _owned_by(1),
		2: _owned_by(2),
	}
	failures += _check(GameRules.portfolio_tax(1, props, 20000) == 40000, "2 owned by peer 1 -> 40000")
	failures += _check(GameRules.portfolio_tax(2, props, 20000) == 20000, "1 owned by peer 2 -> 20000")
	failures += _check(GameRules.portfolio_tax(3, props, 20000) == 0, "peer 3 owns nothing -> 0")
	if failures == 0:
		print("ALL PASS")
	else:
		print("%d FAILURE(S)" % failures)
	quit(1 if failures > 0 else 0)

func _owned_by(peer: int) -> PropertyState:
	var state := PropertyState.new()
	state.owner_peer = peer
	return state

func _check(condition: bool, label: String) -> int:
	if condition:
		print("PASS: %s" % label)
		return 0
	print("FAIL: %s" % label)
	return 1
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
"/d/MonopolyGodot/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64_console.exe" --headless --path "D:/MonopolyGodot/monopolia" --script res://tests/portfolio_tax_test.gd
```

Expected: A block of `SCRIPT ERROR: Compile Error: ...` lines followed by an error mentioning `portfolio_tax` (function does not exist yet) — this noisy compile-error preamble is a known quirk of `--script` mode on this project (autoloads referenced by `BoardModel.gd` aren't ready yet at parse time) and appears even on a passing run later; the thing to check here is that the run does NOT print `ALL PASS`, and exits non-zero.

- [ ] **Step 3: Implement `portfolio_tax`**

In `D:\MonopolyGodot\monopolia\core\GameRules.gd`, the file currently ends with:

```gdscript
static func group_has_buildings(index: int, board: BoardModel, states: Dictionary) -> bool:
	var group := str(board.get_cell(index).get("group", ""))
	for group_index in group_indices(board, group):
		if states.has(group_index) and states[group_index].improvements > 0:
			return true
	return false
```

Append this new function after it:

```gdscript

## Sum of `tax_per_business` for every property `peer_id` currently owns,
## regardless of group - used by "tax_office" cells (see GameController).
static func portfolio_tax(peer_id: int, states: Dictionary, tax_per_business: int) -> int:
	var count := 0
	for state_value in states.values():
		var state: PropertyState = state_value
		if state.owner_peer == peer_id:
			count += 1
	return count * tax_per_business
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2.
Expected output ends with `ALL PASS` and the process exits 0 (ignore the `SCRIPT ERROR` preamble as noted in Step 2).

- [ ] **Step 5: Make the card deck id configurable per ruleset**

In `D:\MonopolyGodot\monopolia\core\GameController.gd`, find (around line 56-58):

```gdscript
	var cards := PackRegistry.get_all("cards")
	chance_deck.setup("chance", cards, _rng.randi())
	treasury_deck.setup("treasury", cards, _rng.randi())
	_touch()
```

Replace with:

```gdscript
	var cards := PackRegistry.get_all("cards")
	chance_deck.setup(str(ruleset.get("chance_deck_id", "chance")), cards, _rng.randi())
	treasury_deck.setup(str(ruleset.get("treasury_deck_id", "treasury")), cards, _rng.randi())
	_touch()
```

This is backward compatible: `classic.json` has no `chance_deck_id`/`treasury_deck_id` fields, so it keeps using the shared `"chance"`/`"treasury"` deck ids exactly as before. A pack that wants an isolated card pool (like `megapolis`, Task 9) sets its own deck ids so `core`'s cards (which include jail-related effects) never get pooled into its draws.

- [ ] **Step 6: Commit**

```bash
cd "D:/MonopolyGodot/monopolia"
git add core/GameRules.gd core/GameController.gd tests/portfolio_tax_test.gd
git commit -m "Add GameRules.portfolio_tax and per-ruleset card deck ids"
```

---

### Task 2: `PlayerState.skip_next_turn`

**Files:**
- Modify: `core/PlayerState.gd`

**Interfaces:**
- Produces: `PlayerState.skip_next_turn: bool` — read/written by Task 3/4's `GameController` changes.

- [ ] **Step 1: Add the field and wire it into serialization**

In `D:\MonopolyGodot\monopolia\core\PlayerState.gd`, find:

```gdscript
var board_index: int = 0
var in_jail: bool = false
var jail_turns: int = 0
var get_out_cards: int = 0
var ready: bool = false
```

Replace with:

```gdscript
var board_index: int = 0
var in_jail: bool = false
var jail_turns: int = 0
var get_out_cards: int = 0
## Set by "vacation"-type cells; consumed once by GameController._begin_current_turn.
var skip_next_turn: bool = false
var ready: bool = false
```

Then find `to_public_dict`:

```gdscript
func to_public_dict() -> Dictionary:
	## Everything here is broadcast to all clients. No money.
	return {
		"peer_id": peer_id,
		"name": display_name,
		"token_id": token_id,
		"customization": customization,
		"role_id": role_id,
		"board_index": board_index,
		"in_jail": in_jail,
		"jail_turns": jail_turns,
		"ready": ready,
		"bankrupt": bankrupt,
		"connected": connected,
		"order": order,
	}
```

Replace with:

```gdscript
func to_public_dict() -> Dictionary:
	## Everything here is broadcast to all clients. No money.
	return {
		"peer_id": peer_id,
		"name": display_name,
		"token_id": token_id,
		"customization": customization,
		"role_id": role_id,
		"board_index": board_index,
		"in_jail": in_jail,
		"jail_turns": jail_turns,
		"skip_next_turn": skip_next_turn,
		"ready": ready,
		"bankrupt": bankrupt,
		"connected": connected,
		"order": order,
	}
```

Then find `from_public_dict`:

```gdscript
static func from_public_dict(data: Dictionary) -> PlayerState:
	var p := PlayerState.new()
	p.peer_id = int(data.get("peer_id", 0))
	p.display_name = str(data.get("name", "Player"))
	p.token_id = str(data.get("token_id", "core:token_hat"))
	p.customization = data.get("customization", {})
	p.role_id = str(data.get("role_id", "core:normal"))
	p.board_index = int(data.get("board_index", 0))
	p.in_jail = bool(data.get("in_jail", false))
	p.jail_turns = int(data.get("jail_turns", 0))
	p.ready = bool(data.get("ready", false))
	p.bankrupt = bool(data.get("bankrupt", false))
	p.connected = bool(data.get("connected", true))
	p.order = int(data.get("order", 0))
	return p
```

Replace with:

```gdscript
static func from_public_dict(data: Dictionary) -> PlayerState:
	var p := PlayerState.new()
	p.peer_id = int(data.get("peer_id", 0))
	p.display_name = str(data.get("name", "Player"))
	p.token_id = str(data.get("token_id", "core:token_hat"))
	p.customization = data.get("customization", {})
	p.role_id = str(data.get("role_id", "core:normal"))
	p.board_index = int(data.get("board_index", 0))
	p.in_jail = bool(data.get("in_jail", false))
	p.jail_turns = int(data.get("jail_turns", 0))
	p.skip_next_turn = bool(data.get("skip_next_turn", false))
	p.ready = bool(data.get("ready", false))
	p.bankrupt = bool(data.get("bankrupt", false))
	p.connected = bool(data.get("connected", true))
	p.order = int(data.get("order", 0))
	return p
```

- [ ] **Step 2: Commit**

```bash
cd "D:/MonopolyGodot/monopolia"
git add core/PlayerState.gd
git commit -m "Add PlayerState.skip_next_turn for vacation-type cells"
```

---

### Task 3: `GameController` — Tax Office pass-through/landing, Vacation, Exchange entry

**Files:**
- Modify: `core/GameController.gd`

**Interfaces:**
- Consumes: `GameRules.portfolio_tax(peer_id, states, tax_per_business)` from Task 1; `PlayerState.skip_next_turn` from Task 2.
- Produces: `GameController.TURN_AWAITING_EXCHANGE` constant, `GameController.pending_exchange: Dictionary` field — consumed by Task 4.

- [ ] **Step 1: Add the new turn-phase constant and state field**

In `D:\MonopolyGodot\monopolia\core\GameController.gd`, find:

```gdscript
const TURN_AWAITING_ROLL := "awaiting_roll"
const TURN_AWAITING_JAIL := "awaiting_jail"
const TURN_AWAITING_PURCHASE := "awaiting_purchase"
const TURN_AWAITING_AUCTION := "awaiting_auction"
const TURN_MANAGING_ASSETS := "managing_assets"
const TURN_ENDED := "ended"
```

Replace with:

```gdscript
const TURN_AWAITING_ROLL := "awaiting_roll"
const TURN_AWAITING_JAIL := "awaiting_jail"
const TURN_AWAITING_PURCHASE := "awaiting_purchase"
const TURN_AWAITING_AUCTION := "awaiting_auction"
const TURN_AWAITING_EXCHANGE := "awaiting_exchange"
const TURN_MANAGING_ASSETS := "managing_assets"
const TURN_ENDED := "ended"
```

Find:

```gdscript
var pending_purchase_index := -1
var pending_debt: Dictionary = {}
var trades: Dictionary = {}
```

Replace with:

```gdscript
var pending_purchase_index := -1
var pending_debt: Dictionary = {}
var pending_exchange: Dictionary = {}
var trades: Dictionary = {}
```

- [ ] **Step 2: Charge Tax Office for cells passed over during movement**

Find:

```gdscript
func resolve_roll(peer_id: int) -> Dictionary:
	if not is_players_turn(peer_id) or turn_phase != TURN_AWAITING_ROLL:
		return {}
	var die := _rng.randi_range(1, 6)
	_last_roll = die
	var player: PlayerState = players[peer_id]
	var from_index := player.board_index
	var raw_target := from_index + die
	var passed_start := raw_target >= board.cell_count()
	player.board_index = posmod(raw_target, board.cell_count())
	var changed: Dictionary = {}
	if passed_start:
		ledger.credit(peer_id, int(ruleset.get("pass_start_reward", 200000)))
		changed[peer_id] = true
	var action := _resolve_landing(peer_id, die, changed)
	_touch()
	return {
		"peer_id": peer_id,
		"dice": [die],
		"from_index": from_index,
		"to_index": player.board_index,
		"in_jail": player.in_jail,
		"passed_go": passed_start,
		"changed_peers": changed.keys(),
		"next_peer": current_peer(),
		"turn_phase": turn_phase,
		"action": action,
	}
```

Replace with:

```gdscript
func resolve_roll(peer_id: int) -> Dictionary:
	if not is_players_turn(peer_id) or turn_phase != TURN_AWAITING_ROLL:
		return {}
	var die := _rng.randi_range(1, 6)
	_last_roll = die
	var player: PlayerState = players[peer_id]
	var from_index := player.board_index
	var raw_target := from_index + die
	var passed_start := raw_target >= board.cell_count()
	player.board_index = posmod(raw_target, board.cell_count())
	var changed: Dictionary = {}
	if passed_start:
		ledger.credit(peer_id, int(ruleset.get("pass_start_reward", 200000)))
		changed[peer_id] = true
	_charge_passed_tax_offices(peer_id, from_index, player.board_index, changed)
	var action := _resolve_landing(peer_id, die, changed)
	_touch()
	return {
		"peer_id": peer_id,
		"dice": [die],
		"from_index": from_index,
		"to_index": player.board_index,
		"in_jail": player.in_jail,
		"passed_go": passed_start,
		"changed_peers": changed.keys(),
		"next_peer": current_peer(),
		"turn_phase": turn_phase,
		"action": action,
	}

## Charges "tax_office"-type cells crossed BETWEEN from_index and to_index
## (exclusive of the final landing cell, which _resolve_landing handles on
## its own so it isn't charged twice). A single die roll (1-6) on a board
## far larger than 6 cells can cross at most one such cell.
func _charge_passed_tax_offices(peer_id: int, from_index: int, to_index: int, changed: Dictionary) -> void:
	var count := board.cell_count()
	var steps := posmod(to_index - from_index, count)
	for step in range(1, steps):
		var index := (from_index + step) % count
		var cell := board.get_cell(index)
		if str(cell.get("type", "")) == "tax_office":
			var tax := GameRules.portfolio_tax(peer_id, properties, int(cell.get("tax_per_business", 0)))
			_charge(peer_id, 0, tax, "tax_office", changed)
```

- [ ] **Step 3: Add the three new landing behaviors**

Find:

```gdscript
		"corner_go_to_jail":
			_send_to_jail(peer_id)
			_finish_turn()
			return {"type": "jail"}
		_:
			pass
```

Replace with:

```gdscript
		"corner_go_to_jail":
			_send_to_jail(peer_id)
			_finish_turn()
			return {"type": "jail"}
		"tax_office":
			var tax := GameRules.portfolio_tax(peer_id, properties, int(cell.get("tax_per_business", 0)))
			if not _charge(peer_id, 0, tax, "tax_office", changed):
				return {"type": "debt", "cell_index": index}
		"vacation":
			player.skip_next_turn = true
		"exchange":
			pending_exchange = {"peer": peer_id, "rolls": []}
			turn_phase = TURN_AWAITING_EXCHANGE
			return {"type": "exchange", "cell_index": index}
		_:
			pass
```

`"tax_office"` and `"vacation"` deliberately don't `return` — like the existing `"tax"` case, they fall through to the generic `on_land` hook and the trailing `_finish_turn()` a few lines below. `"exchange"` must `return` early so the trailing `_finish_turn()` doesn't immediately end the turn it just paused.

- [ ] **Step 4: Manually verify the file still parses**

Run:
```bash
cd "D:/MonopolyGodot/monopolia"
"/d/MonopolyGodot/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64_console.exe" --headless --path "D:/MonopolyGodot/monopolia" --quit
```

Expected: process exits without any `SCRIPT ERROR` mentioning `GameController.gd` in the output (the `PackRegistry`-related parse noise from Task 1 Step 2 is unrelated and only appears under `--script`, not under a normal `--quit` boot). This is a compile smoke check, not a gameplay test — full behavior is covered by Task 11's manual playtest.

- [ ] **Step 5: Commit**

```bash
cd "D:/MonopolyGodot/monopolia"
git add core/GameController.gd
git commit -m "Add tax_office/vacation/exchange landing behavior to GameController"
```

---

### Task 4: `GameController` — turn skip, Exchange roll resolution, private state exposure

**Files:**
- Modify: `core/GameController.gd`
- Test: `tests/exchange_has_pair_test.gd` (new)

**Interfaces:**
- Produces: `GameController.request_exchange_roll(peer_id: int) -> Dictionary` — consumed by Task 5.
- Produces: `GameController._has_pair(rolls: Array) -> bool` (static) — consumed by Task 4's own test only.
- Produces: `private_state(peer_id)["exchange_rolls"]: Array` — consumed by Task 6.

- [ ] **Step 1: Write the failing test for the win/lose rule**

Create `D:\MonopolyGodot\monopolia\tests\exchange_has_pair_test.gd`:

```gdscript
extends SceneTree

func _init() -> void:
	var failures := 0
	failures += _check(GameController._has_pair([4, 4, 2]) == true, "two matching of three -> true")
	failures += _check(GameController._has_pair([1, 2, 3]) == false, "all different -> false")
	failures += _check(GameController._has_pair([5, 5, 5]) == true, "all matching -> true")
	failures += _check(GameController._has_pair([6, 1, 6]) == true, "first and last match -> true")
	if failures == 0:
		print("ALL PASS")
	else:
		print("%d FAILURE(S)" % failures)
	quit(1 if failures > 0 else 0)

func _check(condition: bool, label: String) -> int:
	if condition:
		print("PASS: %s" % label)
		return 0
	print("FAIL: %s" % label)
	return 1
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
"/d/MonopolyGodot/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64_console.exe" --headless --path "D:/MonopolyGodot/monopolia" --script res://tests/exchange_has_pair_test.gd
```

Expected: does not print `ALL PASS`; error mentions `_has_pair` not found (ignore the `SCRIPT ERROR` compile-noise preamble, see Task 1 Step 2).

- [ ] **Step 3: Add turn-skip handling to `_begin_current_turn`**

Find:

```gdscript
func _begin_current_turn() -> void:
	if phase != PHASE_PLAYING or turn_order.is_empty():
		return
	var player: PlayerState = players[current_peer()]
	turn_phase = TURN_AWAITING_JAIL if player.in_jail else TURN_AWAITING_ROLL
```

Replace with:

```gdscript
func _begin_current_turn() -> void:
	if phase != PHASE_PLAYING or turn_order.is_empty():
		return
	var player: PlayerState = players[current_peer()]
	if player.skip_next_turn:
		player.skip_next_turn = false
		_finish_turn()
		return
	turn_phase = TURN_AWAITING_JAIL if player.in_jail else TURN_AWAITING_ROLL
```

- [ ] **Step 4: Add the Exchange roll method and the pure win/lose helper**

Find:

```gdscript
func _complete_auction() -> Dictionary:
	var resolution := auction.resolve()
	var winner := int(resolution["winner"])
	var winning_bid := int(resolution["amount"])
	var property_index := int(resolution["property_index"])
	var changed: Array[int] = []
	if winner != 0 and properties.has(property_index) and ledger.debit(winner, winning_bid):
		var state: PropertyState = properties[property_index]
		state.owner_peer = winner
		changed.append(winner)
	resolution["changed_peers"] = changed
	return resolution

func request_jail_action(peer_id: int, action: String) -> Dictionary:
```

Replace with:

```gdscript
func _complete_auction() -> Dictionary:
	var resolution := auction.resolve()
	var winner := int(resolution["winner"])
	var winning_bid := int(resolution["amount"])
	var property_index := int(resolution["property_index"])
	var changed: Array[int] = []
	if winner != 0 and properties.has(property_index) and ledger.debit(winner, winning_bid):
		var state: PropertyState = properties[property_index]
		state.owner_peer = winner
		changed.append(winner)
	resolution["changed_peers"] = changed
	return resolution

# --- Exchange minigame ---------------------------------------------------

## One manual roll of the "exchange" minigame (see spec). The caller (the
## player standing on the exchange cell) invokes this up to 3 times; on the
## 3rd roll the outcome (2-of-3 matching -> win) is resolved and the turn
## ends. Returns {} for any invalid/out-of-turn call.
func request_exchange_roll(peer_id: int) -> Dictionary:
	if not is_players_turn(peer_id) or turn_phase != TURN_AWAITING_EXCHANGE:
		return {}
	if int(pending_exchange.get("peer", 0)) != peer_id:
		return {}
	var rolls: Array = pending_exchange.get("rolls", [])
	if rolls.size() >= 3:
		return {}
	var die := _rng.randi_range(1, 6)
	rolls.append(die)
	pending_exchange["rolls"] = rolls
	var result := {
		"peer_id": peer_id,
		"dice": [die],
		"rolls_so_far": rolls.duplicate(),
	}
	if rolls.size() < 3:
		_touch()
		return result
	var changed: Dictionary = {}
	var won := _has_pair(rolls)
	var stake := int(board.get_cell(players[peer_id].board_index).get("stake", 100000))
	if won:
		ledger.credit(peer_id, stake)
		changed[peer_id] = true
	else:
		_charge(peer_id, 0, stake, "exchange", changed)
	pending_exchange.clear()
	result["resolved"] = true
	result["won"] = won
	result["amount"] = stake
	result["changed_peers"] = changed.keys()
	if turn_phase != TURN_MANAGING_ASSETS:
		_finish_turn()
	_touch()
	return result

static func _has_pair(rolls: Array) -> bool:
	return rolls[0] == rolls[1] or rolls[0] == rolls[2] or rolls[1] == rolls[2]

func request_jail_action(peer_id: int, action: String) -> Dictionary:
```

- [ ] **Step 5: Run test to verify it passes**

Run the Step 2 command again.
Expected output ends with `ALL PASS`, exit code 0.

- [ ] **Step 6: Expose exchange state to the acting player and to spectators**

Find:

```gdscript
		elif turn_phase == TURN_AWAITING_JAIL:
			pending_action = {"type": "jail", "peer_id": current_peer()}
```

Replace with:

```gdscript
		elif turn_phase == TURN_AWAITING_JAIL:
			pending_action = {"type": "jail", "peer_id": current_peer()}
		elif turn_phase == TURN_AWAITING_EXCHANGE:
			pending_action = {"type": "exchange", "peer_id": current_peer()}
```

Find:

```gdscript
	return {
		"sequence": sequence,
		"balance": ledger.get_balance(peer_id),
		"debt": debt,
		"auction_bid": int(auction.bids.get(peer_id, 0)),
		"auction_responded": auction.bids.has(peer_id) or auction.passed.has(peer_id),
		"trades": private_trades,
		"get_out_cards": players[peer_id].get_out_cards if players.has(peer_id) else 0,
	}
```

Replace with:

```gdscript
	return {
		"sequence": sequence,
		"balance": ledger.get_balance(peer_id),
		"debt": debt,
		"auction_bid": int(auction.bids.get(peer_id, 0)),
		"auction_responded": auction.bids.has(peer_id) or auction.passed.has(peer_id),
		"trades": private_trades,
		"get_out_cards": players[peer_id].get_out_cards if players.has(peer_id) else 0,
		"exchange_rolls": pending_exchange.get("rolls", []).duplicate() if int(pending_exchange.get("peer", 0)) == peer_id else [],
	}
```

- [ ] **Step 7: Commit**

```bash
cd "D:/MonopolyGodot/monopolia"
git add core/GameController.gd tests/exchange_has_pair_test.gd
git commit -m "Add exchange minigame resolution and turn-skip to GameController"
```

---

### Task 5: `NetworkManager` — Exchange roll RPC

**Files:**
- Modify: `autoload/NetworkManager.gd`

**Interfaces:**
- Consumes: `GameController.request_exchange_roll(peer_id)` from Task 4.
- Produces: `NetworkManager.request_exchange_roll()` (no args, client-callable) — consumed by Task 6.

- [ ] **Step 1: Add the RPC pair and server handler**

In `D:\MonopolyGodot\monopolia\autoload\NetworkManager.gd`, find:

```gdscript
## On the host, a local UI action has no remote sender, so default to peer 1.
func _effective_sender(fallback: int) -> int:
	return fallback

func request_buy() -> void:
```

Replace with:

```gdscript
## On the host, a local UI action has no remote sender, so default to peer 1.
func _effective_sender(fallback: int) -> int:
	return fallback

func request_exchange_roll() -> void:
	if is_server():
		_server_resolve_exchange_roll(_effective_sender(1))
	else:
		rpc_id(1, "server_request_exchange_roll")

@rpc("any_peer", "call_remote", "reliable")
func server_request_exchange_roll() -> void:
	if is_server():
		_server_resolve_exchange_roll(multiplayer.get_remote_sender_id())

func _server_resolve_exchange_roll(sender: int) -> void:
	var res := game.request_exchange_roll(sender)
	if res.is_empty():
		return
	_broadcast_event(NetProtocol.EVENT_ROLL, {
		"peer_id": res.get("peer_id", 0), "dice": res.get("dice", [])})
	if bool(res.get("resolved", false)):
		_broadcast_event(NetProtocol.EVENT_ACTION, {
			"name": "exchange_resolved",
			"data": {
				"won": res.get("won", false),
				"amount": res.get("amount", 0),
				"peer_id": res.get("peer_id", 0),
			}})
	_publish_result(res)

func request_buy() -> void:
```

Each partial roll re-uses the existing `EVENT_ROLL` channel (so `BoardRenderer`'s die animation and `Hud`'s die label update exactly as for a normal roll, for free), and `_publish_result(res)` — since `res` never sets `"ok": false` — always broadcasts a fresh snapshot/private-state afterward, which is what updates `exchange_rolls` for the acting player's HUD (Task 6).

- [ ] **Step 2: Commit**

```bash
cd "D:/MonopolyGodot/monopolia"
git add autoload/NetworkManager.gd
git commit -m "Wire exchange roll RPC through NetworkManager"
```

---

### Task 6: `Hud.gd` — Exchange UI and new toasts

**Files:**
- Modify: `ui/Hud.gd`

**Interfaces:**
- Consumes: `NetworkManager.request_exchange_roll()` from Task 5; `NetworkManager.local_private_state["exchange_rolls"]` from Task 4.

- [ ] **Step 1: Add the "awaiting_exchange" context panel**

In `D:\MonopolyGodot\monopolia\ui\Hud.gd`, find:

```gdscript
		elif turn_phase == "managing_assets" and int(pending.get("peer_id", 0)) == me:
			var debt: Dictionary = NetworkManager.local_private_state.get("debt", {})
			_context_title.text = "Недостаточно средств"
			_context_body.text = "Нужно оплатить: %s $. Продайте постройки или заложите активы." % _money(int(debt.get("amount", 0)))
			_add_action("УПРАВЛЯТЬ АКТИВАМИ", func(): add_child(ASSET_DIALOG.new()), true)
			_add_action("БАНКРОТСТВО", NetworkManager.request_bankruptcy)
		else:
			_context_title.text = "Стол ждёт решения"
			_context_body.text = _name_of(current)
```

Replace with:

```gdscript
		elif turn_phase == "managing_assets" and int(pending.get("peer_id", 0)) == me:
			var debt: Dictionary = NetworkManager.local_private_state.get("debt", {})
			_context_title.text = "Недостаточно средств"
			_context_body.text = "Нужно оплатить: %s $. Продайте постройки или заложите активы." % _money(int(debt.get("amount", 0)))
			_add_action("УПРАВЛЯТЬ АКТИВАМИ", func(): add_child(ASSET_DIALOG.new()), true)
			_add_action("БАНКРОТСТВО", NetworkManager.request_bankruptcy)
		elif turn_phase == "awaiting_exchange" and int(pending.get("peer_id", 0)) == me:
			var rolls: Array = NetworkManager.local_private_state.get("exchange_rolls", [])
			_context_title.text = "Биржа"
			if rolls.is_empty():
				_context_body.text = "Нужно хотя бы 2 одинаковых числа из 3 бросков"
			else:
				var shown: PackedStringArray = []
				for value in rolls:
					shown.append(str(value))
				_context_body.text = "Броски: %s" % ", ".join(shown)
			_add_action("БРОСИТЬ", NetworkManager.request_exchange_roll, true)
		else:
			_context_title.text = "Стол ждёт решения"
			_context_body.text = _name_of(current)
```

- [ ] **Step 2: Add toasts for the new action names**

Find:

```gdscript
func _on_game_action(event_name: String, data: Dictionary) -> void:
	match event_name:
		"purchase": _show_toast("Собственность приобретена")
		"card":
			var card: Dictionary = data.get("card", {})
			_show_toast("%s — %s" % [str(card.get("title", "Карточка")), str(card.get("text", ""))])
		"jail": _show_toast("Игрок отправлен в тюрьму")
		"rent": _show_toast("Аренда перечислена владельцу")
		"auction_started": _show_toast("Начался закрытый аукцион")
		"auction_resolved": _show_toast("Аукцион завершён")
		"build": _show_toast("Постройка завершена")
		"sell_property": _show_toast("Собственность продана банку")
		"mortgage": _show_toast("Актив заложен")
		"bankruptcy": _show_toast("%s объявляет банкротство" % _name_of(int(data.get("peer_id", 0))))
```

Replace with:

```gdscript
func _on_game_action(event_name: String, data: Dictionary) -> void:
	match event_name:
		"purchase": _show_toast("Собственность приобретена")
		"card":
			var card: Dictionary = data.get("card", {})
			_show_toast("%s — %s" % [str(card.get("title", "Карточка")), str(card.get("text", ""))])
		"jail": _show_toast("Игрок отправлен в тюрьму")
		"rent": _show_toast("Аренда перечислена владельцу")
		"auction_started": _show_toast("Начался закрытый аукцион")
		"auction_resolved": _show_toast("Аукцион завершён")
		"build": _show_toast("Постройка завершена")
		"sell_property": _show_toast("Собственность продана банку")
		"mortgage": _show_toast("Актив заложен")
		"bankruptcy": _show_toast("%s объявляет банкротство" % _name_of(int(data.get("peer_id", 0))))
		"tax_office": _show_toast("Списан налог на Налоговой")
		"vacation": _show_toast("Пропуск хода: Отпуск")
		"exchange_resolved":
			var amount := _money(int(data.get("amount", 0)))
			_show_toast(("Биржа: выигрыш " if bool(data.get("won", false)) else "Биржа: проигрыш ") + amount + " $")
```

`"tax_office"` and `"vacation"` reach this handler "for free" — `_resolve_landing` (Task 3) returns `{"type": "tax_office", ...}` / `{"type": "vacation", ...}`, and `NetworkManager._server_resolve_roll` already broadcasts any non-empty `action.type` as an `EVENT_ACTION` name, exactly like `"purchase"`/`"jail"`/etc. today. Only `"exchange_resolved"` needed a manual broadcast (Task 5), since it's produced by `request_exchange_roll`, not by landing.

- [ ] **Step 3: Commit**

```bash
cd "D:/MonopolyGodot/monopolia"
git add ui/Hud.gd
git commit -m "Add Exchange context panel and new toasts to Hud"
```

---

### Task 7: `packs/megapolis` scaffold

**Files:**
- Create: `packs/megapolis/pack.json`
- Create: `packs/megapolis/scripts/main.gd`

**Interfaces:**
- Consumes: nothing from earlier tasks directly; `ModLoader` (existing, unmodified) discovers this pack automatically because it lives under `res://packs`.

- [ ] **Step 1: Create the pack manifest**

Create `D:\MonopolyGodot\monopolia\packs\megapolis\pack.json`:

```json
{
  "id": "megapolis",
  "name": "Мегаполия",
  "version": "1.0.0",
  "api_version": 2,
  "authors": ["Monopolis"],
  "description": "Business-company board theme: 8 company groups instead of streets, plus Tax Office, Vacation and Exchange corner mechanics.",
  "dependencies": ["core"],
  "load_after": ["core"],
  "replaces": [],
  "scene_overrides": {},
  "resources": [],
  "entry": "scripts/main.gd",
  "content": {
    "cells": "content/cells",
    "rulesets": "content/rulesets",
    "cards": "content/cards"
  }
}
```

Tokens, roles and sounds are intentionally omitted from `"content"` — this pack reuses `core`'s via the `dependencies: ["core"]` load-order guarantee, following the same pattern documented in `docs/modding.md`.

- [ ] **Step 2: Create the entry script**

Create `D:\MonopolyGodot\monopolia\packs\megapolis\scripts\main.gd`:

```gdscript
extends RefCounted
## Entry point for the "megapolis" pack.
##
## Tax Office / Vacation / Exchange behaviour is implemented directly in
## GameController (cell types "tax_office"/"vacation"/"exchange", generic to
## any ruleset) rather than through EventBus hooks, so no hook registration
## is needed here.

var _pack_id: String = "megapolis"

func setup(pack_id: String) -> void:
	_pack_id = pack_id
```

- [ ] **Step 3: Commit**

```bash
cd "D:/MonopolyGodot/monopolia"
git add packs/megapolis/pack.json packs/megapolis/scripts/main.gd
git commit -m "Scaffold packs/megapolis"
```

---

### Task 8: `packs/megapolis` cell content

**Files:**
- Create: `packs/megapolis/content/cells/business_cells.json`

**Interfaces:**
- Produces: 28 cell definitions (4 special + 24 property) referenced by Task 9's `board_cells` array as `megapolis:<id>`.

- [ ] **Step 1: Create the cell content file**

Create `D:\MonopolyGodot\monopolia\packs\megapolis\content\cells\business_cells.json`:

```json
[
  {"id":"cell_tax_office","name":"НАЛОГОВАЯ","type":"tax_office","tags":["corner","special"],"color":"#8b3a3a","tax_per_business":20000},
  {"id":"cell_vacation","name":"ОТПУСК","type":"vacation","tags":["corner","special"],"color":"#e0a83e"},
  {"id":"cell_exchange","name":"БИРЖА","type":"exchange","tags":["corner","special"],"color":"#2f8f8f","stake":100000},
  {"id":"cell_money","name":"ДЕНЬГИ","type":"treasury","tags":["special","card"],"color":"#537c75"},

  {"id":"madrock","name":"MADROCK","type":"property","tags":["property"],"group":"light_industry","color":"#8a8f5c","price":60000,"mortgage":30000,"house_cost":50000,"rent_table":[8000,40000,120000,360000,640000,896000],"rent_growth":1.1},
  {"id":"aris_sports","name":"ARIS SPORTS","type":"property","tags":["property"],"group":"light_industry","color":"#8a8f5c","price":70000,"mortgage":35000,"house_cost":50000,"rent_table":[9000,45000,135000,405000,720000,1008000],"rent_growth":1.1},
  {"id":"shu_shu","name":"SHU SHU","type":"property","tags":["property"],"group":"light_industry","color":"#8a8f5c","price":80000,"mortgage":40000,"house_cost":50000,"rent_table":[10000,50000,150000,450000,800000,1120000],"rent_growth":1.1},

  {"id":"arc","name":"ARC","type":"property","tags":["property"],"group":"tv","color":"#4f6b8f","price":90000,"mortgage":45000,"house_cost":50000,"rent_table":[12000,60000,180000,540000,960000,1344000],"rent_growth":1.1},
  {"id":"music_plus","name":"MUSIC PLUS","type":"property","tags":["property"],"group":"tv","color":"#4f6b8f","price":100000,"mortgage":50000,"house_cost":50000,"rent_table":[13000,65000,195000,585000,1040000,1456000],"rent_growth":1.1},
  {"id":"toon_up","name":"TOON UP!","type":"property","tags":["property"],"group":"tv","color":"#4f6b8f","price":110000,"mortgage":55000,"house_cost":50000,"rent_table":[14000,70000,210000,630000,1120000,1568000],"rent_growth":1.1},

  {"id":"kurt","name":"KURT","type":"property","tags":["property"],"group":"construction","color":"#b9752e","price":130000,"mortgage":65000,"house_cost":100000,"rent_table":[17000,85000,255000,765000,1360000,1904000],"rent_growth":1.1},
  {"id":"moyet","name":"moЯet","type":"property","tags":["property"],"group":"construction","color":"#b9752e","price":140000,"mortgage":70000,"house_cost":100000,"rent_table":[18000,90000,270000,810000,1440000,2016000],"rent_growth":1.1},
  {"id":"bridge","name":"BRIDGE","type":"property","tags":["property"],"group":"construction","color":"#b9752e","price":150000,"mortgage":75000,"house_cost":100000,"rent_table":[20000,100000,300000,900000,1600000,2240000],"rent_growth":1.1},

  {"id":"binko","name":"Вінко","type":"property","tags":["property"],"group":"film","color":"#7a3f8f","price":160000,"mortgage":80000,"house_cost":100000,"rent_table":[21000,105000,315000,945000,1680000,2352000],"rent_growth":1.1},
  {"id":"charge","name":"CHARGE","type":"property","tags":["property"],"group":"film","color":"#7a3f8f","price":170000,"mortgage":85000,"house_cost":100000,"rent_table":[22000,110000,330000,990000,1760000,2464000],"rent_growth":1.1},
  {"id":"cineberry","name":"CINEBERRY Pictures","type":"property","tags":["property"],"group":"film","color":"#7a3f8f","price":180000,"mortgage":90000,"house_cost":100000,"rent_table":[23000,115000,345000,1035000,1840000,2576000],"rent_growth":1.1},

  {"id":"nethound","name":"nethound","type":"property","tags":["property"],"group":"computer","color":"#3f8f7a","price":200000,"mortgage":100000,"house_cost":150000,"rent_table":[26000,130000,390000,1170000,2080000,2912000],"rent_growth":1.1},
  {"id":"not_dead_head","name":"NOT DEAD HEAD","type":"property","tags":["property"],"group":"computer","color":"#3f8f7a","price":210000,"mortgage":105000,"house_cost":150000,"rent_table":[27000,135000,405000,1215000,2160000,3024000],"rent_growth":1.1},
  {"id":"anysoft","name":"ANYSOFT","type":"property","tags":["property"],"group":"computer","color":"#3f8f7a","price":220000,"mortgage":110000,"house_cost":150000,"rent_table":[29000,145000,435000,1305000,2320000,3248000],"rent_growth":1.1},

  {"id":"hixel_finance","name":"hixel finance","type":"property","tags":["property"],"group":"financial","color":"#2f6b4f","price":230000,"mortgage":115000,"house_cost":150000,"rent_table":[30000,150000,450000,1350000,2400000,3360000],"rent_growth":1.1},
  {"id":"vollume_capital","name":"vollume capital","type":"property","tags":["property"],"group":"financial","color":"#2f6b4f","price":240000,"mortgage":120000,"house_cost":150000,"rent_table":[31000,155000,465000,1395000,2480000,3472000],"rent_growth":1.1},
  {"id":"robinson_sons","name":"Robinson & sons","type":"property","tags":["property"],"group":"financial","color":"#2f6b4f","price":250000,"mortgage":125000,"house_cost":150000,"rent_table":[33000,165000,495000,1485000,2640000,3696000],"rent_growth":1.1},

  {"id":"runair","name":"RUNAIR","type":"property","tags":["property"],"group":"airlines","color":"#5c8fbf","price":270000,"mortgage":135000,"house_cost":200000,"rent_table":[35000,175000,525000,1575000,2800000,3920000],"rent_growth":1.1},
  {"id":"aston_airlines","name":"ASTON AIRLINES","type":"property","tags":["property"],"group":"airlines","color":"#5c8fbf","price":280000,"mortgage":140000,"house_cost":200000,"rent_table":[36000,180000,540000,1620000,2880000,4032000],"rent_growth":1.1},
  {"id":"dynamic_airways","name":"DYNAMIC AIRWAYS","type":"property","tags":["property"],"group":"airlines","color":"#5c8fbf","price":300000,"mortgage":150000,"house_cost":200000,"rent_table":[39000,195000,585000,1755000,3120000,4368000],"rent_growth":1.1},

  {"id":"davison_oil","name":"Davison Standard Oil Company","type":"property","tags":["property"],"group":"oil","color":"#3a3a3a","price":330000,"mortgage":165000,"house_cost":200000,"rent_table":[43000,215000,645000,1935000,3440000,4816000],"rent_growth":1.1},
  {"id":"cosco","name":"COSCO","type":"property","tags":["property"],"group":"oil","color":"#3a3a3a","price":360000,"mortgage":180000,"house_cost":200000,"rent_table":[47000,235000,705000,2115000,3760000,5264000],"rent_growth":1.1},
  {"id":"morgan_petroleum","name":"Morgan Petroleum","type":"property","tags":["property"],"group":"oil","color":"#3a3a3a","price":400000,"mortgage":200000,"house_cost":200000,"rent_table":[52000,260000,780000,2340000,4160000,5824000],"rent_growth":1.1}
]
```

Rent tables follow the spec's formula (`r = round(price × 0.13, nearest 1000)`, tiers `[r, 5r, 15r, 45r, 80r, 112r]`); `mortgage = price / 2`; `house_cost` matches the group's tier as listed in spec §3 (50k/50k/100k/100k/150k/150k/200k/200k across the 8 groups in ring order).

- [ ] **Step 2: Commit**

```bash
cd "D:/MonopolyGodot/monopolia"
git add packs/megapolis/content/cells/business_cells.json
git commit -m "Add megapolis cell content (24 properties + 4 special cells)"
```

---

### Task 9: `packs/megapolis` ruleset (board layout)

**Files:**
- Create: `packs/megapolis/content/rulesets/business.json`

**Interfaces:**
- Consumes: cell ids from Task 8 (`megapolis:*`) and reused `core:cell_start`/`core:cell_chance`; `chance_deck_id`/`treasury_deck_id` fields from Task 1.

- [ ] **Step 1: Create the ruleset file**

Create `D:\MonopolyGodot\monopolia\packs\megapolis\content\rulesets\business.json`:

```json
{
  "id": "business",
  "name": "Мегаполия: Бизнес",
  "tags": ["megapolis", "full_game"],
  "board_size": 11,
  "starting_cash": 1200000,
  "pass_start_reward": 200000,
  "dice_count": 1,
  "min_players": 2,
  "default_role": "core:normal",
  "default_token": "core:token_hat",
  "unmortgage_multiplier": 1.1,
  "auction_enabled": false,
  "property_sale_multiplier": 0.5,
  "chance_deck_id": "megapolis_chance",
  "treasury_deck_id": "megapolis_money",
  "board_cells": [
    "core:cell_start",
    "megapolis:madrock", "megapolis:cell_money", "megapolis:aris_sports", "core:cell_chance", "megapolis:shu_shu",
    "megapolis:arc", "core:cell_chance", "megapolis:music_plus", "megapolis:toon_up",
    "megapolis:cell_tax_office",
    "megapolis:kurt", "megapolis:cell_money", "megapolis:moyet", "megapolis:cell_money", "megapolis:bridge",
    "megapolis:binko", "core:cell_chance", "megapolis:charge", "megapolis:cineberry",
    "megapolis:cell_vacation",
    "megapolis:nethound", "megapolis:cell_money", "megapolis:not_dead_head", "core:cell_chance", "megapolis:anysoft",
    "megapolis:hixel_finance", "core:cell_chance", "megapolis:vollume_capital", "megapolis:robinson_sons",
    "megapolis:cell_exchange",
    "megapolis:runair", "megapolis:cell_money", "megapolis:aston_airlines", "megapolis:cell_money", "megapolis:dynamic_airways",
    "megapolis:davison_oil", "core:cell_chance", "megapolis:cosco", "megapolis:morgan_petroleum"
  ]
}
```

No `jail_fine`/`jail_max_turns` fields — nothing on this board ever sets `in_jail`, so `GameController` never enters `TURN_AWAITING_JAIL` for this ruleset and those fields would never be read.

`board_cells` has 40 entries (`board_size: 11` → perimeter `4×(11-1) = 40`, verified: 1 start + 9 + 1 tax_office + 9 + 1 vacation + 9 + 1 exchange + 9 = 40). Side groupings match spec §2: (light_industry, tv) after СТАРТ, (construction, film) after НАЛОГОВАЯ, (computer, financial) after ОТПУСК, (airlines, oil) after БИРЖА. `core:cell_chance` is reused as-is (its stored name is already "ШАНС"); `core:cell_start` likewise. `megapolis:cell_money` is a new definition (Task 8) because its name ("ДЕНЬГИ") differs from `core:cell_treasury`'s ("КАЗНА").

- [ ] **Step 2: Reload the project and confirm the ruleset is discovered**

Run:
```bash
cd "D:/MonopolyGodot/monopolia"
"/d/MonopolyGodot/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64_console.exe" --headless --path "D:/MonopolyGodot/monopolia" --quit 2>&1 | grep -i "ModLoader\|megapolis"
```

Expected: a line like `[ModLoader] Loaded 2 pack(s), signature=...` (was previously `Loaded 1 pack(s)` with only `core`) confirming `megapolis` was discovered and its manifest/cards/cells parsed without a `[ModLoader]` or `[Packs]` error. If a `push_error` about a missing dependency or bad JSON appears, fix the referenced file before continuing.

- [ ] **Step 3: Commit**

```bash
cd "D:/MonopolyGodot/monopolia"
git add packs/megapolis/content/rulesets/business.json
git commit -m "Add megapolis business ruleset board layout"
```

---

### Task 10: `packs/megapolis` card content

**Files:**
- Create: `packs/megapolis/content/cards/chance.json`
- Create: `packs/megapolis/content/cards/money.json`

**Interfaces:**
- Consumes: `chance_deck_id`/`treasury_deck_id` values (`"megapolis_chance"`/`"megapolis_money"`) from Task 9's ruleset.

- [ ] **Step 1: Create the "Шанс" cards**

Create `D:\MonopolyGodot\monopolia\packs\megapolis\content\cards\chance.json`:

```json
[
  {"id":"chance_ipo","deck":"megapolis_chance","title":"Успешное IPO","text":"Ваши акции взлетели. Получите 150 000.","effects":[{"type":"credit","amount":150000}]},
  {"id":"chance_audit","deck":"megapolis_chance","title":"Внеплановый аудит","text":"Заплатите штраф 90 000.","effects":[{"type":"debit","amount":90000}]},
  {"id":"chance_dividend","deck":"megapolis_chance","title":"Дивиденды акционерам","text":"Получите 120 000.","effects":[{"type":"credit","amount":120000}]},
  {"id":"chance_relocation","deck":"megapolis_chance","title":"Переезд офиса","text":"Продвиньтесь на три клетки вперёд.","effects":[{"type":"move_relative","steps":3}]},
  {"id":"chance_recall","deck":"megapolis_chance","title":"Отзыв продукции","text":"Вернитесь на две клетки назад.","effects":[{"type":"move_relative","steps":-2}]},
  {"id":"chance_startup","deck":"megapolis_chance","title":"Премия за стартап","text":"Переместитесь на СТАРТ и получите 200 000.","effects":[{"type":"move_to","index":0,"collect_start":true}]},
  {"id":"chance_renovation","deck":"megapolis_chance","title":"Ремонт офисов","text":"Заплатите за каждое ваше здание.","effects":[{"type":"repairs","per_house":25000,"per_hotel":100000}]},
  {"id":"chance_conference","deck":"megapolis_chance","title":"Бизнес-конференция","text":"Получите по 30 000 от каждого игрока.","effects":[{"type":"collect_each","amount":30000}]},
  {"id":"chance_sponsorship","deck":"megapolis_chance","title":"Спонсорский взнос","text":"Заплатите каждому игроку по 20 000.","effects":[{"type":"pay_each","amount":20000}]},
  {"id":"chance_grant","deck":"megapolis_chance","title":"Государственный грант","text":"Получите 100 000.","effects":[{"type":"credit","amount":100000}]}
]
```

- [ ] **Step 2: Create the "Деньги" cards**

Create `D:\MonopolyGodot\monopolia\packs\megapolis\content\cards\money.json`:

```json
[
  {"id":"money_refund","deck":"megapolis_money","title":"Возврат переплаты","text":"Получите 100 000.","effects":[{"type":"credit","amount":100000}]},
  {"id":"money_consulting","deck":"megapolis_money","title":"Консалтинговые услуги","text":"Заплатите 50 000.","effects":[{"type":"debit","amount":50000}]},
  {"id":"money_inheritance","deck":"megapolis_money","title":"Наследство","text":"Получите 200 000.","effects":[{"type":"credit","amount":200000}]},
  {"id":"money_insurance","deck":"megapolis_money","title":"Страховая выплата","text":"Получите 75 000.","effects":[{"type":"credit","amount":75000}]},
  {"id":"money_lawsuit","deck":"megapolis_money","title":"Судебный иск","text":"Заплатите 60 000.","effects":[{"type":"debit","amount":60000}]},
  {"id":"money_bonus","deck":"megapolis_money","title":"Годовая премия","text":"Получите 90 000.","effects":[{"type":"credit","amount":90000}]},
  {"id":"money_fine","deck":"megapolis_money","title":"Штраф за просрочку","text":"Заплатите 40 000.","effects":[{"type":"debit","amount":40000}]},
  {"id":"money_birthday","deck":"megapolis_money","title":"День рождения компании","text":"Получите по 20 000 от каждого игрока.","effects":[{"type":"collect_each","amount":20000}]},
  {"id":"money_charity","deck":"megapolis_money","title":"Благотворительный взнос","text":"Заплатите каждому по 15 000.","effects":[{"type":"pay_each","amount":15000}]},
  {"id":"money_relocation_bonus","deck":"megapolis_money","title":"Городская премия","text":"Отправляйтесь на СТАРТ.","effects":[{"type":"move_to","index":0,"collect_start":true}]}
]
```

Neither file uses `send_to_jail` or `get_out_of_jail` — this ruleset has no jail (spec §6).

- [ ] **Step 3: Commit**

```bash
cd "D:/MonopolyGodot/monopolia"
git add packs/megapolis/content/cards/chance.json packs/megapolis/content/cards/money.json
git commit -m "Add megapolis chance/money card content"
```

---

### Task 11: Manual integration playtest and regression check

**Files:** none (verification only)

**Interfaces:** none — this task exercises everything from Tasks 1-10 end-to-end through the actual running game.

- [ ] **Step 1: Launch the editor and start a solo test game on the new ruleset**

Run:
```bash
cd "D:/MonopolyGodot/monopolia"
"/d/MonopolyGodot/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64.exe" --path "D:/MonopolyGodot/monopolia"
```

In the main menu: open the "РЕЖИМ ИГРЫ" dropdown and confirm **"Мегаполия: Бизнес"** is listed alongside **"Монополис: Ваниль"**. Select it, then click "ТЕСТИРОВЩИКАМ: НАЧАТЬ ОДИНОЧНУЮ ИГРУ".

Expected: the game loads into `Game.tscn` with an 11×11 board of 40 tiles showing business names (MADROCK, ARC, KURT, …) instead of classic streets, and a НАЛОГОВАЯ/ОТПУСК/БИРЖА corner instead of ТЮРЬМА/ПАРКИНГ/В ТЮРЬМУ.

- [ ] **Step 2: Verify property purchase and rent still work**

Roll until landing on any unowned business tile, buy it. Roll again on a future turn (using the solo test's single active player, ownership just accumulates) — confirm the board tile shows the correct price/rent ladder for that 3-tile group, and that `_build_property_card` renders it (no missing icon crash — placeholder emblem is expected since no `icon` field was set).

Expected: purchase succeeds, balance decreases by the tile's `price`, tile shows an owner marker.

- [ ] **Step 3: Verify Tax Office charges on both landing and pass-through**

Manually track: note your current balance and property count. Roll dice repeatedly until either (a) you land exactly on НАЛОГОВАЯ, or (b) a roll's path crosses it without landing there (e.g. starting 2 cells before it with a die of 4+).

Expected in case (a): balance drops by `20000 × (your property count)`, a "Списан налог на Налоговой" toast appears, turn ends normally.
Expected in case (b): balance drops by the same formula even though you land past it, confirmed by comparing balance before/after the roll.

- [ ] **Step 4: Verify Vacation skips the next turn**

Roll until landing exactly on ОТПУСК.

Expected: a "Пропуск хода: Отпуск" toast appears, turn passes to the next player immediately; in `solo_test_mode` (single player) confirm your OWN next turn is skipped — i.e. after landing on ОТПУСК, the very next time play returns to you, the context panel goes straight to "Бросок" as if a full extra turn passed silently (watch the `turn_order` cycle if playing with 2+ players instead, where this is easier to see as another player's turn appearing twice in a row).

- [ ] **Step 5: Verify the Exchange minigame end-to-end**

Roll until landing exactly on БИРЖА.

Expected: context panel title becomes "Биржа" with a "БРОСИТЬ" button and the hint "Нужно хотя бы 2 одинаковых числа из 3 бросков". Click "БРОСИТЬ" up to 3 times, watching the on-board 3D die animate each time (same animation as a normal roll) and the context body update to "Броски: X, Y[, Z]". After the 3rd click:
- If at least two of the three values matched: a "Биржа: выигрыш 100 000 $" toast appears and balance increases by 100 000.
- If all three differed: a "Биржа: проигрыш 100 000 $" toast appears and balance decreases by 100 000 (or the game transitions to the debt/bankruptcy panel if the balance can't cover it).

Play multiple games (or manually retry) until you've observed both outcomes at least once.

- [ ] **Step 6: Regression-check the classic ruleset**

Return to the main menu, select **"Монополис: Ваниль"**, start another solo test. Play a few turns: buy a property, land on ШАНС/КАЗНА/НАЛОГ, confirm nothing about `classic`'s behavior changed (no ОТПУСК/БИРЖА/НАЛОГОВАЯ appear, jail still works via ТЮРЬМА/В ТЮРЬМУ).

Expected: `classic` plays exactly as before Task 1 — this confirms every engine change stayed backward compatible.

- [ ] **Step 7: Final push**

```bash
cd "D:/MonopolyGodot/monopolia"
git status
git push origin master
```

Expected: `git status` shows a clean tree (everything from Tasks 1-10 was already committed per-task); `git push` fast-forwards `origin/master` with no conflicts.
