extends Node
## Event-driven audio facade. Packs map logical event ids to files or
## procedural fallback tones, so DLC can replace sounds without changing code.

const POOL_SIZE := 12
var _events: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _last_balance := -1
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	_rng.randomize()
	_ensure_buses()
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "Voice%02d" % i
		add_child(player)
		_players.append(player)
	EventBus.packs_loaded.connect(_rebuild_index)
	EventBus.dice_rolled.connect(func(_peer: int, _values: Array): play_event("game.dice_roll"))
	EventBus.turn_changed.connect(func(peer: int):
		if peer == NetworkManager.get_local_peer_id():
			play_event("game.turn_local")
	)
	EventBus.player_moved.connect(func(_peer: int, _from: int, _to: int): play_event("game.token_move"))
	EventBus.local_balance_changed.connect(_on_balance_changed)
	EventBus.connection_succeeded.connect(func(): play_event("net.connected"))
	EventBus.connection_failed.connect(func(_reason: String): play_event("net.error"))
	EventBus.game_action.connect(_on_game_action)
	get_tree().node_added.connect(_on_node_added)
	apply_settings()

func _rebuild_index(_signature: String = "") -> void:
	_events.clear()
	for definition in PackRegistry.get_all("sounds"):
		var event_id := str(definition.get("event", ""))
		if event_id != "":
			_events[event_id] = definition

func play_event(event_id: String, context: Dictionary = {}) -> void:
	if process_mode == Node.PROCESS_MODE_DISABLED or GameConfig.mute_all:
		return
	var definition: Dictionary = _events.get(event_id, {})
	if definition.is_empty():
		return
	var stream := _resolve_stream(definition)
	if stream == null:
		return
	var player := _claim_player()
	player.stream = stream
	player.bus = str(definition.get("bus", "SFX"))
	player.volume_db = float(definition.get("volume_db", 0.0))
	player.pitch_scale = _rng.randf_range(
		float(definition.get("pitch_min", 1.0)),
		float(definition.get("pitch_max", 1.0)))
	if context.has("pitch"):
		player.pitch_scale *= float(context["pitch"])
	player.play()

func apply_settings() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_set_bus("Master", GameConfig.master_volume, GameConfig.mute_all)
	_set_bus("Music", GameConfig.music_volume, false)
	_set_bus("SFX", GameConfig.sfx_volume, false)
	_set_bus("UI", GameConfig.ui_volume, false)

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		var button := node as BaseButton
		if not button.pressed.is_connected(_play_ui_click):
			button.pressed.connect(_play_ui_click)

func _play_ui_click() -> void:
	play_event("ui.click")

func _on_balance_changed(amount: int) -> void:
	if _last_balance >= 0 and amount != _last_balance:
		play_event("game.money_credit" if amount > _last_balance else "game.money_debit")
	_last_balance = amount

func _on_game_action(event_name: String, _data: Dictionary) -> void:
	match event_name:
		"purchase", "build", "unmortgage":
			play_event("game.purchase")
		"auction_started", "auction_resolved":
			play_event("game.auction")
		"jail":
			play_event("game.jail")
		"bankruptcy":
			play_event("game.money_debit")

func _claim_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	return _players[0]

func _resolve_stream(definition: Dictionary) -> AudioStream:
	var paths: Array = definition.get("streams", [])
	if not paths.is_empty():
		var path := str(paths[_rng.randi_range(0, paths.size() - 1)])
		if not path.begins_with("res://") and not path.begins_with("user://"):
			path = _pack_relative_path(str(definition.get("pack_id", "")), path)
		if ResourceLoader.exists(path):
			var resource := load(path)
			if resource is AudioStream:
				return resource
	var tone: Dictionary = definition.get("tone", {})
	if not tone.is_empty():
		return _generate_tone(tone)
	return null

func _pack_relative_path(pack_id: String, relative_path: String) -> String:
	for manifest in PackRegistry.loaded_packs:
		if manifest.id == pack_id:
			return "%s/%s" % [manifest.root_path, relative_path]
	return relative_path

func _generate_tone(tone: Dictionary) -> AudioStreamWAV:
	var duration := clampf(float(tone.get("duration", 0.12)), 0.025, 2.0)
	var frequency := float(tone.get("frequency", 440.0))
	var end_frequency := float(tone.get("end_frequency", frequency))
	var gain := clampf(float(tone.get("gain", 0.32)), 0.0, 0.9)
	var waveform := str(tone.get("wave", "sine"))
	var sample_rate := 44100
	var sample_count := maxi(1, int(duration * sample_rate))
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	var phase := 0.0
	for index in sample_count:
		var t := float(index) / float(sample_count)
		var hz := lerpf(frequency, end_frequency, t)
		phase += TAU * hz / float(sample_rate)
		var value := sin(phase)
		if waveform == "square":
			value = 1.0 if value >= 0.0 else -1.0
		elif waveform == "noise":
			value = _rng.randf_range(-1.0, 1.0)
		var envelope := pow(1.0 - t, float(tone.get("decay", 2.0)))
		var sample := int(clampf(value * gain * envelope, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(index * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = bytes
	return stream

func _ensure_buses() -> void:
	for bus_name in ["Music", "SFX", "UI"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)

func _set_bus(bus_name: String, linear: float, muted: bool) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(index, muted)
