class_name GameController
extends RefCounted
## Authoritative Monopoly rules engine. Clients submit intents; only this class
## mutates money, ownership, cards, jail state or turn phases.

const PHASE_LOBBY := "lobby"
const PHASE_PLAYING := "playing"
const PHASE_ENDED := "ended"

const TURN_AWAITING_ROLL := "awaiting_roll"
const TURN_AWAITING_JAIL := "awaiting_jail"
const TURN_AWAITING_PURCHASE := "awaiting_purchase"
const TURN_AWAITING_AUCTION := "awaiting_auction"
const TURN_MANAGING_ASSETS := "managing_assets"
const TURN_ENDED := "ended"

var ruleset: Dictionary = {}
var board: BoardModel
var ledger := MoneyLedger.new()
var players: Dictionary = {}
var turn_order: Array[int] = []
var current_turn_index := 0
var phase := PHASE_LOBBY
var turn_phase := ""
var table_owner := 0
var properties: Dictionary = {}
var auction := AuctionState.new()
var chance_deck := CardDeck.new()
var treasury_deck := CardDeck.new()
var pending_purchase_index := -1
var pending_debt: Dictionary = {}
var trades: Dictionary = {}
var sequence := 0
var solo_test_mode := false
var _next_trade_id := 1
var _last_roll := 0
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()

func configure(ruleset_id: String) -> void:
	ruleset = PackRegistry.get_def("rulesets", ruleset_id)
	if ruleset.is_empty():
		var all := PackRegistry.get_all("rulesets")
		ruleset = all[0] if not all.is_empty() else {}
	board = BoardModel.build(ruleset)
	properties.clear()
	for index in board.cell_count():
		var cell := board.get_cell(index)
		if GameRules.is_purchasable(cell):
			var state := PropertyState.new()
			state.index = index
			state.cell_id = str(cell.get("full_id", cell.get("id", "")))
			properties[index] = state
	var cards := PackRegistry.get_all("cards")
	chance_deck.setup("chance", cards, _rng.randi())
	treasury_deck.setup("treasury", cards, _rng.randi())
	_touch()

# --- Lobby -------------------------------------------------------------------

func add_player(peer_id: int, join_payload: Dictionary) -> PlayerState:
	if players.has(peer_id):
		return players[peer_id]
	var player := PlayerState.new()
	player.peer_id = peer_id
	player.display_name = str(join_payload.get("name", "Player %d" % peer_id)).left(24)
	player.token_id = str(join_payload.get("token", str(ruleset.get("default_token", "core:token_hat"))))
	if not PackRegistry.has("tokens", player.token_id):
		player.token_id = str(ruleset.get("default_token", "core:token_hat"))
	var cosmetic: Dictionary = join_payload.get("customization", {})
	player.customization = {}
	if cosmetic.has("color"):
		player.customization["color"] = ColorUtil.to_color(cosmetic["color"])
	if cosmetic.has("material"):
		player.customization["material"] = str(cosmetic["material"]).left(32)
	player.role_id = str(ruleset.get("default_role", "core:normal"))
	player.board_index = board.start_index if board else 0
	player.order = players.size()
	players[peer_id] = player
	turn_order.append(peer_id)
	ledger.add_player(peer_id, int(ruleset.get("starting_cash", 1200000)))
	if table_owner == 0:
		table_owner = peer_id
	_touch()
	return player

func remove_player(peer_id: int) -> void:
	if not players.has(peer_id):
		return
	if phase == PHASE_PLAYING:
		var was_current := peer_id == current_peer()
		var player: PlayerState = players[peer_id]
		player.connected = false
		_bankrupt_player(peer_id, 0)
		for trade_id in trades.keys():
			var offer: TradeOffer = trades[trade_id]
			if offer.involves(peer_id):
				trades.erase(trade_id)
		if _active_players().size() <= 1:
			phase = PHASE_ENDED
			turn_phase = TURN_ENDED
			pending_purchase_index = -1
			pending_debt.clear()
			auction.active = false
		elif auction.active and auction.participants.has(peer_id) \
				and not auction.bids.has(peer_id) and not auction.passed.has(peer_id):
			auction.submit(peer_id, 0)
			if auction.all_responded():
				_complete_auction()
				_finish_turn()
		elif was_current:
			_finish_turn()
	else:
		players.erase(peer_id)
		ledger.remove_player(peer_id)
		turn_order.erase(peer_id)
	if table_owner == peer_id:
		var active := _active_players()
		table_owner = active[0] if not active.is_empty() else 0
	_touch()

func set_ready(peer_id: int, ready: bool) -> bool:
	if phase != PHASE_LOBBY or not players.has(peer_id):
		return false
	var player: PlayerState = players[peer_id]
	player.ready = ready
	_touch()
	return true

func update_player_profile(peer_id: int, payload: Dictionary) -> bool:
	if phase != PHASE_LOBBY or not players.has(peer_id):
		return false
	var player: PlayerState = players[peer_id]
	player.display_name = str(payload.get("name", player.display_name)).left(24)
	var token_id := str(payload.get("token", player.token_id))
	if PackRegistry.has("tokens", token_id):
		player.token_id = token_id
	var cosmetic: Dictionary = payload.get("customization", {})
	player.customization = {}
	if cosmetic.has("color"):
		player.customization["color"] = ColorUtil.to_color(cosmetic["color"])
	if cosmetic.has("material"):
		player.customization["material"] = str(cosmetic["material"]).left(32)
	player.ready = false
	_touch()
	return true

func can_start() -> bool:
	if phase != PHASE_LOBBY or players.size() < int(ruleset.get("min_players", 2)):
		return false
	for peer_id in turn_order:
		var player: PlayerState = players[peer_id]
		if not player.ready:
			return false
	return true

func start_game(requester: int) -> bool:
	if requester != table_owner or not can_start():
		return false
	solo_test_mode = false
	phase = PHASE_PLAYING
	current_turn_index = 0
	_begin_current_turn()
	_touch()
	return true

func start_solo_test(requester: int) -> bool:
	if phase != PHASE_LOBBY or requester != table_owner \
			or players.size() != 1 or not players.has(requester):
		return false
	solo_test_mode = true
	var player: PlayerState = players[requester]
	player.ready = true
	phase = PHASE_PLAYING
	current_turn_index = 0
	_begin_current_turn()
	_touch()
	return true

# --- Turn flow ----------------------------------------------------------------

func current_peer() -> int:
	if turn_order.is_empty():
		return 0
	return turn_order[current_turn_index % turn_order.size()]

func is_players_turn(peer_id: int) -> bool:
	return phase == PHASE_PLAYING and current_peer() == peer_id

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

func _resolve_landing(peer_id: int, die: int, changed: Dictionary) -> Dictionary:
	var player: PlayerState = players[peer_id]
	var index := player.board_index
	var cell := board.get_cell(index)
	var type := str(cell.get("type", ""))
	if GameRules.is_purchasable(cell):
		var property: PropertyState = properties[index]
		if property.owner_peer == 0:
			pending_purchase_index = index
			turn_phase = TURN_AWAITING_PURCHASE
			return {"type": "purchase", "cell_index": index}
		if property.owner_peer != peer_id and not property.mortgaged:
			var rent := GameRules.calculate_rent(cell, property, board, properties, die)
			if not _charge(peer_id, property.owner_peer, rent, "rent", changed):
				return {"type": "debt", "cell_index": index}
			_finish_turn()
			return {"type": "rent", "cell_index": index, "owner_peer": property.owner_peer}
		_finish_turn()
		return {"type": "owned", "cell_index": index}
	match type:
		"tax":
			if not _charge(peer_id, 0, int(cell.get("amount", 100000)), "tax", changed):
				return {"type": "debt", "cell_index": index}
		"chance":
			var card := chance_deck.draw()
			return _resolve_card(peer_id, card, die, changed)
		"treasury":
			var card := treasury_deck.draw()
			return _resolve_card(peer_id, card, die, changed)
		"corner_go_to_jail":
			_send_to_jail(peer_id)
			_finish_turn()
			return {"type": "jail"}
		_:
			pass
	var hook_payload := EventBus.run_hook("on_land", {
		"peer_id": peer_id, "cell": cell, "board_index": index,
		"jail_index": board.jail_index, "effects": []})
	_apply_effects(hook_payload.get("effects", []), changed)
	if turn_phase != TURN_MANAGING_ASSETS:
		_finish_turn()
	return {"type": type}

func request_buy(peer_id: int) -> Dictionary:
	if not is_players_turn(peer_id) or turn_phase != TURN_AWAITING_PURCHASE:
		return {"ok": false}
	if not properties.has(pending_purchase_index):
		return {"ok": false}
	var state: PropertyState = properties[pending_purchase_index]
	var price := GameRules.price(board.get_cell(pending_purchase_index))
	if state.owner_peer != 0 or not ledger.debit(peer_id, price):
		return {"ok": false, "reason": "Недостаточно средств"}
	state.owner_peer = peer_id
	var index := pending_purchase_index
	pending_purchase_index = -1
	_finish_turn()
	_touch()
	return {"ok": true, "event": "purchase", "cell_index": index, "changed_peers": [peer_id]}

func request_decline_purchase(peer_id: int) -> Dictionary:
	if not is_players_turn(peer_id) or turn_phase != TURN_AWAITING_PURCHASE:
		return {"ok": false}
	if not bool(ruleset.get("auction_enabled", false)):
		var declined_index := pending_purchase_index
		pending_purchase_index = -1
		_finish_turn()
		_touch()
		return {
			"ok": true, "event": "purchase_declined",
			"cell_index": declined_index}
	var participants: Array[int] = []
	for candidate in turn_order:
		var player: PlayerState = players[candidate]
		if not player.bankrupt:
			participants.append(candidate)
	auction.begin(pending_purchase_index, participants)
	pending_purchase_index = -1
	turn_phase = TURN_AWAITING_AUCTION
	_touch()
	return {"ok": true, "event": "auction_started"}

func request_auction_bid(peer_id: int, amount: int) -> Dictionary:
	if turn_phase != TURN_AWAITING_AUCTION or not auction.active:
		return {"ok": false}
	if amount > 0 and not ledger.can_afford(peer_id, amount):
		return {"ok": false, "reason": "Ставка превышает доступные средства"}
	if not auction.submit(peer_id, amount):
		return {"ok": false}
	if not auction.all_responded():
		_touch()
		return {"ok": true, "event": "auction_bid_recorded"}
	var resolution := _complete_auction()
	var winner := int(resolution["winner"])
	var property_index := int(resolution["property_index"])
	var changed: Array[int] = resolution.get("changed_peers", [])
	_finish_turn()
	_touch()
	return {
		"ok": true, "event": "auction_resolved", "winner": winner,
		"cell_index": property_index, "changed_peers": changed}

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
	if not is_players_turn(peer_id) or turn_phase != TURN_AWAITING_JAIL:
		return {"ok": false}
	var player: PlayerState = players[peer_id]
	var fine := int(ruleset.get("jail_fine", 100000))
	match action:
		"pay":
			if not ledger.debit(peer_id, fine):
				return {"ok": false, "reason": "Недостаточно средств"}
			player.in_jail = false
			player.jail_turns = 0
			turn_phase = TURN_AWAITING_ROLL
			_touch()
			return {"ok": true, "changed_peers": [peer_id]}
		"card":
			if player.get_out_cards <= 0:
				return {"ok": false}
			player.get_out_cards -= 1
			player.in_jail = false
			player.jail_turns = 0
			turn_phase = TURN_AWAITING_ROLL
			_touch()
			return {"ok": true}
		"wait":
			player.jail_turns += 1
			if player.jail_turns >= int(ruleset.get("jail_max_turns", 3)):
				if ledger.debit(peer_id, fine):
					player.in_jail = false
					player.jail_turns = 0
					turn_phase = TURN_AWAITING_ROLL
					_touch()
					return {"ok": true, "changed_peers": [peer_id]}
				pending_debt = {
					"peer": peer_id, "creditor": 0, "amount": fine,
					"reason": "jail", "resume": "jail_release"}
				turn_phase = TURN_MANAGING_ASSETS
				_touch()
				return {"ok": true, "event": "debt"}
			_finish_turn()
			_touch()
			return {"ok": true}
	return {"ok": false}

func _begin_current_turn() -> void:
	if phase != PHASE_PLAYING or turn_order.is_empty():
		return
	var player: PlayerState = players[current_peer()]
	turn_phase = TURN_AWAITING_JAIL if player.in_jail else TURN_AWAITING_ROLL

func _finish_turn() -> void:
	pending_purchase_index = -1
	pending_debt.clear()
	var active_count := _active_players().size()
	if active_count == 0 or (active_count == 1 and not solo_test_mode):
		phase = PHASE_ENDED
		turn_phase = TURN_ENDED
		return
	for i in turn_order.size():
		current_turn_index = (current_turn_index + 1) % turn_order.size()
		var player: PlayerState = players[current_peer()]
		if not player.bankrupt:
			break
	_begin_current_turn()

# --- Assets / solvency --------------------------------------------------------

func request_build(peer_id: int, index: int) -> Dictionary:
	if not _can_invest(peer_id) or not GameRules.can_build(peer_id, index, board, properties):
		return {"ok": false}
	var cost := int(board.get_cell(index).get("house_cost", 0))
	if not ledger.debit(peer_id, cost):
		return {"ok": false, "reason": "Недостаточно средств"}
	var state: PropertyState = properties[index]
	state.improvements += 1
	_touch()
	return {"ok": true, "event": "build", "cell_index": index, "changed_peers": [peer_id]}

func request_sell_building(peer_id: int, index: int) -> Dictionary:
	if not _can_liquidate(peer_id) or not properties.has(index):
		return {"ok": false}
	var state: PropertyState = properties[index]
	if state.owner_peer != peer_id or not GameRules.can_sell_building(index, board, properties):
		return {"ok": false}
	state.improvements -= 1
	ledger.credit(peer_id, int(board.get_cell(index).get("house_cost", 0)) / 2)
	_try_resolve_debt(peer_id)
	_touch()
	return {"ok": true, "event": "sell_building", "changed_peers": [peer_id]}

func request_sell_property(peer_id: int, index: int) -> Dictionary:
	if not _can_liquidate(peer_id) or not properties.has(index):
		return {"ok": false}
	var state: PropertyState = properties[index]
	var cell := board.get_cell(index)
	if state.owner_peer != peer_id or state.mortgaged \
			or GameRules.group_has_buildings(index, board, properties):
		return {"ok": false}
	var value := GameRules.sale_value(
		cell, float(ruleset.get("property_sale_multiplier", 0.5)))
	state.owner_peer = 0
	state.improvements = 0
	ledger.credit(peer_id, value)
	_try_resolve_debt(peer_id)
	_touch()
	return {
		"ok": true, "event": "sell_property",
		"cell_index": index, "changed_peers": [peer_id]}

func request_mortgage(peer_id: int, index: int) -> Dictionary:
	if not _can_liquidate(peer_id) or not properties.has(index):
		return {"ok": false}
	var state: PropertyState = properties[index]
	if state.owner_peer != peer_id or state.mortgaged or GameRules.group_has_buildings(index, board, properties):
		return {"ok": false}
	state.mortgaged = true
	ledger.credit(peer_id, GameRules.mortgage_value(board.get_cell(index)))
	_try_resolve_debt(peer_id)
	_touch()
	return {"ok": true, "event": "mortgage", "changed_peers": [peer_id]}

func request_unmortgage(peer_id: int, index: int) -> Dictionary:
	if not _can_invest(peer_id) or not properties.has(index):
		return {"ok": false}
	var state: PropertyState = properties[index]
	var cost := roundi(GameRules.mortgage_value(board.get_cell(index)) * float(ruleset.get("unmortgage_multiplier", 1.1)))
	if state.owner_peer != peer_id or not state.mortgaged or not ledger.debit(peer_id, cost):
		return {"ok": false}
	state.mortgaged = false
	_touch()
	return {"ok": true, "event": "unmortgage", "changed_peers": [peer_id]}

func request_bankruptcy(peer_id: int) -> Dictionary:
	if turn_phase != TURN_MANAGING_ASSETS or int(pending_debt.get("peer", 0)) != peer_id:
		return {"ok": false}
	var creditor := int(pending_debt.get("creditor", 0))
	_bankrupt_player(peer_id, creditor)
	pending_debt.clear()
	if phase == PHASE_PLAYING:
		_finish_turn()
	_touch()
	return {"ok": true, "event": "bankruptcy", "peer_id": peer_id}

func _charge(peer_id: int, creditor: int, amount: int, reason: String, changed: Dictionary) -> bool:
	if amount <= 0:
		return true
	var paid := ledger.transfer(peer_id, creditor, amount) if creditor != 0 else ledger.debit(peer_id, amount)
	if paid:
		changed[peer_id] = true
		if creditor != 0:
			changed[creditor] = true
		return true
	pending_debt = {
		"peer": peer_id, "creditor": creditor, "amount": amount,
		"reason": reason, "resume": "end_turn"}
	turn_phase = TURN_MANAGING_ASSETS
	return false

func _try_resolve_debt(peer_id: int) -> bool:
	if pending_debt.is_empty() or int(pending_debt.get("peer", 0)) != peer_id:
		return false
	var amount := int(pending_debt["amount"])
	var creditor := int(pending_debt["creditor"])
	var paid := ledger.transfer(peer_id, creditor, amount) if creditor != 0 else ledger.debit(peer_id, amount)
	if not paid:
		return false
	var resume := str(pending_debt.get("resume", "end_turn"))
	pending_debt.clear()
	if resume == "jail_release":
		var player: PlayerState = players[peer_id]
		player.in_jail = false
		player.jail_turns = 0
		turn_phase = TURN_AWAITING_ROLL
	else:
		_finish_turn()
	return true

func _bankrupt_player(peer_id: int, creditor: int) -> void:
	if not players.has(peer_id):
		return
	var player: PlayerState = players[peer_id]
	player.bankrupt = true
	player.ready = false
	var remaining := ledger.get_balance(peer_id)
	if creditor != 0 and remaining > 0:
		ledger.transfer(peer_id, creditor, remaining)
	for state_value in properties.values():
		var state: PropertyState = state_value
		if state.owner_peer != peer_id:
			continue
		state.owner_peer = creditor
		if creditor == 0:
			state.improvements = 0
			state.mortgaged = false
	ledger.set_balance(peer_id, 0)

func _can_liquidate(peer_id: int) -> bool:
	if turn_phase == TURN_MANAGING_ASSETS and int(pending_debt.get("peer", 0)) == peer_id:
		return true
	return phase == PHASE_PLAYING and players.has(peer_id) \
		and turn_phase == TURN_AWAITING_ROLL

func _can_invest(peer_id: int) -> bool:
	return is_players_turn(peer_id) and turn_phase == TURN_AWAITING_ROLL

# --- Cards -------------------------------------------------------------------

func _resolve_card(peer_id: int, card: Dictionary, die: int, changed: Dictionary) -> Dictionary:
	var moved := _apply_card(peer_id, card, changed)
	var action := {"type": "card", "card": _public_card(card)}
	if turn_phase == TURN_MANAGING_ASSETS:
		return action
	var player: PlayerState = players[peer_id]
	if player.in_jail:
		_finish_turn()
		return action
	if moved:
		action["followup"] = _resolve_landing(peer_id, die, changed)
	else:
		_finish_turn()
	return action

func _apply_card(peer_id: int, card: Dictionary, changed: Dictionary) -> bool:
	var moved := false
	for effect_value in card.get("effects", []):
		var effect: Dictionary = effect_value
		var type := str(effect.get("type", ""))
		var amount := int(effect.get("amount", 0))
		match type:
			"credit":
				ledger.credit(peer_id, amount)
				changed[peer_id] = true
			"debit":
				_charge(peer_id, 0, amount, "card", changed)
			"move_to":
				var player: PlayerState = players[peer_id]
				var target := int(effect.get("index", board.start_index))
				if bool(effect.get("collect_start", false)) and target < player.board_index:
					ledger.credit(peer_id, int(ruleset.get("pass_start_reward", 200000)))
					changed[peer_id] = true
				player.board_index = target
				moved = true
			"move_relative":
				var player: PlayerState = players[peer_id]
				player.board_index = posmod(player.board_index + int(effect.get("steps", 0)), board.cell_count())
				moved = true
			"send_to_jail":
				_send_to_jail(peer_id)
			"get_out_of_jail":
				var player: PlayerState = players[peer_id]
				player.get_out_cards += 1
			"collect_each":
				for other in _active_players():
					if other != peer_id and not _charge(other, peer_id, amount, "card", changed):
						break
			"pay_each":
				for other in _active_players():
					if other != peer_id and not _charge(peer_id, other, amount, "card", changed):
						break
			"repairs":
				var total := 0
				for state_value in properties.values():
					var state: PropertyState = state_value
					if state.owner_peer == peer_id:
						total += mini(state.improvements, 4) * int(effect.get("per_house", 0))
						if state.improvements == 5:
							total += int(effect.get("per_hotel", 0))
				_charge(peer_id, 0, total, "repairs", changed)
	return moved

func _send_to_jail(peer_id: int) -> void:
	var player: PlayerState = players[peer_id]
	player.board_index = board.jail_index
	player.in_jail = true
	player.jail_turns = 0

func _public_card(card: Dictionary) -> Dictionary:
	return {
		"id": str(card.get("full_id", card.get("id", ""))),
		"title": str(card.get("title", "Карточка")),
		"text": str(card.get("text", "")),
		"deck": str(card.get("deck", "")),
	}

func _apply_effects(effects: Array, changed: Dictionary) -> void:
	for effect_value in effects:
		var effect: Dictionary = effect_value
		var peer := int(effect.get("peer", 0))
		match str(effect.get("type", "")):
			"credit":
				ledger.credit(peer, int(effect.get("amount", 0)))
				changed[peer] = true
			"debit":
				_charge(peer, 0, int(effect.get("amount", 0)), "mod", changed)
			"move_to":
				if players.has(peer):
					var player: PlayerState = players[peer]
					player.board_index = int(effect.get("index", 0))
			"send_to_jail":
				if players.has(peer):
					_send_to_jail(peer)

# --- Private trades -----------------------------------------------------------

func propose_trade(sender: int, data: Dictionary) -> Dictionary:
	var receiver := int(data.get("to_peer", 0))
	if phase != PHASE_PLAYING or turn_phase != TURN_AWAITING_ROLL \
			or sender == receiver or not players.has(receiver):
		return {"ok": false}
	var receiver_state: PlayerState = players[receiver]
	if receiver_state.bankrupt:
		return {"ok": false}
	var offer := TradeOffer.new()
	offer.setup(_next_trade_id, sender, receiver, data)
	if not _validate_trade(offer):
		return {"ok": false, "reason": "Некорректные условия сделки"}
	trades[_next_trade_id] = offer
	_next_trade_id += 1
	_touch()
	return {"ok": true, "trade": offer}

func respond_trade(peer_id: int, trade_id: int, accept: bool) -> Dictionary:
	if not trades.has(trade_id):
		return {"ok": false}
	var offer: TradeOffer = trades[trade_id]
	if peer_id != offer.to_peer or offer.state != "proposed":
		return {"ok": false}
	if not accept:
		offer.state = "rejected"
		trades.erase(trade_id)
		_touch()
		return {"ok": true, "accepted": false}
	if not _validate_trade(offer):
		trades.erase(trade_id)
		return {"ok": false, "reason": "Условия сделки изменились"}
	if not ledger.transfer(offer.from_peer, offer.to_peer, offer.offer_cash):
		return {"ok": false}
	if not ledger.transfer(offer.to_peer, offer.from_peer, offer.request_cash):
		ledger.transfer(offer.to_peer, offer.from_peer, offer.offer_cash)
		return {"ok": false}
	_transfer_trade_assets(offer)
	offer.state = "accepted"
	trades.erase(trade_id)
	_touch()
	return {"ok": true, "accepted": true, "changed_peers": [offer.from_peer, offer.to_peer]}

func _validate_trade(offer: TradeOffer) -> bool:
	if not ledger.can_afford(offer.from_peer, offer.offer_cash) or not ledger.can_afford(offer.to_peer, offer.request_cash):
		return false
	for index in offer.offer_properties:
		if not _tradeable_property(index, offer.from_peer):
			return false
	for index in offer.request_properties:
		if not _tradeable_property(index, offer.to_peer):
			return false
	var sender: PlayerState = players[offer.from_peer]
	var receiver: PlayerState = players[offer.to_peer]
	return sender.get_out_cards >= offer.offer_cards and receiver.get_out_cards >= offer.request_cards

func _tradeable_property(index: int, owner: int) -> bool:
	return properties.has(index) and properties[index].owner_peer == owner \
		and not properties[index].mortgaged \
		and not GameRules.group_has_buildings(index, board, properties)

func _transfer_trade_assets(offer: TradeOffer) -> void:
	for index in offer.offer_properties:
		properties[index].owner_peer = offer.to_peer
	for index in offer.request_properties:
		properties[index].owner_peer = offer.from_peer
	var sender: PlayerState = players[offer.from_peer]
	var receiver: PlayerState = players[offer.to_peer]
	sender.get_out_cards += offer.request_cards - offer.offer_cards
	receiver.get_out_cards += offer.offer_cards - offer.request_cards

# --- Replication --------------------------------------------------------------

func public_snapshot() -> Dictionary:
	var player_dicts: Array = []
	for peer_id in turn_order:
		if players.has(peer_id):
			player_dicts.append(players[peer_id].to_public_dict())
	var property_dicts: Array = []
	var indices := properties.keys()
	indices.sort()
	for index in indices:
		property_dicts.append(properties[index].to_dict())
	var pending_action := {}
	if turn_phase == TURN_AWAITING_PURCHASE:
		pending_action = {"type": "purchase", "peer_id": current_peer(), "cell_index": pending_purchase_index}
	elif turn_phase == TURN_MANAGING_ASSETS:
		pending_action = {
			"type": "debt", "peer_id": int(pending_debt.get("peer", 0)),
			"reason": str(pending_debt.get("reason", ""))}
	elif turn_phase == TURN_AWAITING_JAIL:
		pending_action = {"type": "jail", "peer_id": current_peer()}
	return {
		"sequence": sequence,
		"ruleset_id": str(ruleset.get("full_id", ruleset.get("id", ""))),
		"phase": phase,
		"turn_phase": turn_phase,
		"current_peer": current_peer(),
		"turn_order": turn_order.duplicate(),
		"players": player_dicts,
		"properties": property_dicts,
		"pending_action": pending_action,
		"auction": auction.public_dict(),
		"table_owner": table_owner,
		"min_players": int(ruleset.get("min_players", 2)),
		"can_start": can_start(),
		"solo_test_mode": solo_test_mode,
		"winner_peer": _winner_peer(),
	}

func private_state(peer_id: int) -> Dictionary:
	var private_trades: Array = []
	for offer_value in trades.values():
		var offer: TradeOffer = offer_value
		if offer.involves(peer_id):
			private_trades.append(offer.to_private_dict())
	var debt := {}
	if int(pending_debt.get("peer", 0)) == peer_id:
		debt = pending_debt.duplicate(true)
	return {
		"sequence": sequence,
		"balance": ledger.get_balance(peer_id),
		"debt": debt,
		"auction_bid": int(auction.bids.get(peer_id, 0)),
		"auction_responded": auction.bids.has(peer_id) or auction.passed.has(peer_id),
		"trades": private_trades,
		"get_out_cards": players[peer_id].get_out_cards if players.has(peer_id) else 0,
	}

func _active_players() -> Array[int]:
	var result: Array[int] = []
	for peer_id in turn_order:
		var player: PlayerState = players[peer_id]
		if not player.bankrupt:
			result.append(peer_id)
	return result

func _winner_peer() -> int:
	var active := _active_players()
	return active[0] if phase == PHASE_ENDED and active.size() == 1 else 0

func _touch() -> void:
	sequence += 1
