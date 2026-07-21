extends Node
## Local, per-client preferences chosen before/at connect time.
## These never carry authoritative game state - they are just what this client
## wants (name, token, customization, which ruleset to host).

const SETTINGS_PATH := "user://settings.cfg"

var player_name: String = "Player"
var selected_token: String = "core:token_hat"
## Free-form cosmetic overrides applied by TokenView (color, scale, ...).
var token_customization: Dictionary = {
	"color": Color(0.9, 0.2, 0.2),
	"material": "polished",
}
var selected_ruleset: String = "core:classic"

var last_host: String = "127.0.0.1"
var last_port: int = 27015
## 0 = low (no post effects), 1 = balanced, 2 = cinematic.
var effects_quality: int = 2
var reduced_motion: bool = false
var fullscreen_enabled: bool = false
var vsync_enabled: bool = true
var master_volume: float = 0.9
var music_volume: float = 0.55
var sfx_volume: float = 0.85
var ui_volume: float = 0.8
var mute_all: bool = false

func _ready() -> void:
	load_settings()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_min_size(Vector2i(1280, 720))
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen_enabled
			else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	player_name = cfg.get_value("player", "name", player_name)
	selected_token = cfg.get_value("player", "token", selected_token)
	token_customization = cfg.get_value("player", "customization", token_customization)
	token_customization.erase("scale")
	selected_ruleset = cfg.get_value("game", "ruleset", selected_ruleset)
	last_host = cfg.get_value("net", "host", last_host)
	last_port = cfg.get_value("net", "port", last_port)
	effects_quality = clampi(int(cfg.get_value("visual", "effects_quality", effects_quality)), 0, 2)
	reduced_motion = bool(cfg.get_value("visual", "reduced_motion", reduced_motion))
	fullscreen_enabled = bool(cfg.get_value("visual", "fullscreen_enabled", fullscreen_enabled))
	vsync_enabled = bool(cfg.get_value("visual", "vsync_enabled", vsync_enabled))
	master_volume = clampf(float(cfg.get_value("audio", "master", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	ui_volume = clampf(float(cfg.get_value("audio", "ui", ui_volume)), 0.0, 1.0)
	mute_all = bool(cfg.get_value("audio", "mute", mute_all))

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "token", selected_token)
	cfg.set_value("player", "customization", token_customization)
	cfg.set_value("game", "ruleset", selected_ruleset)
	cfg.set_value("net", "host", last_host)
	cfg.set_value("net", "port", last_port)
	cfg.set_value("visual", "effects_quality", effects_quality)
	cfg.set_value("visual", "reduced_motion", reduced_motion)
	cfg.set_value("visual", "fullscreen_enabled", fullscreen_enabled)
	cfg.set_value("visual", "vsync_enabled", vsync_enabled)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "ui", ui_volume)
	cfg.set_value("audio", "mute", mute_all)
	cfg.save(SETTINGS_PATH)

## Bundles this client's identity for the server on join.
func to_join_payload() -> Dictionary:
	return {
		"name": player_name,
		"token": selected_token,
		"customization": token_customization,
	}
