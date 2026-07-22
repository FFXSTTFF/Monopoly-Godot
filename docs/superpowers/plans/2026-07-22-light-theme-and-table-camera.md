# Light Theme & Table Camera Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recolor the entire game (menus, HUD, 3D board/table) from the current dark "casino-luxury" theme to a light theme while keeping the existing structure, and replace the single fixed orthographic camera with a perspective camera that starts at the local player's seat and orbits horizontally around the table on drag.

**Architecture:** The light theme is achieved almost entirely by repointing color *values* behind existing named constants/helpers (`UiPalette.gd`, `LuxuryTheme.gd`) plus a handful of literal dark colors discovered inline in several `ui/*.gd` files that bypass those constants — no structural UI changes. The 3D board/table gets matching light material colors via shader `uniform` parameters that already exist (no `.gdshader` edits needed). The camera is a new self-contained `render/TableCamera.gd` (`class_name TableCamera extends Camera3D`) that `render/GameScene.gd` instantiates in place of its old inline camera code.

**Tech Stack:** Godot 4.6, GDScript.

## Global Constraints

- Purely a `render/`/`ui/` visual change — no edits to `core/`, `autoload/`, packs, or content JSON.
- Applies globally (both `classic` and `megapolis` rulesets look the same structurally, just recolored) — nothing pack-specific.
- Camera: perspective projection; starts at the local player's seat (from `PlayerState.order`, same value `BoardRenderer._token_world_pos` already uses); horizontal-drag-to-rotate only, at a **fixed height and radius** — no zoom, no tilt, no free movement, no auto-return-to-seat after dragging.
- Camera state is 100% local/client-side — never touches `public_snapshot`/`private_state`/`NetworkManager` RPCs.
- Spec source of truth: `docs/superpowers/specs/2026-07-22-light-theme-and-table-camera-design.md`.

---

### Task 1: `UiPalette.gd` + `LuxuryTheme.gd` — core palette recolor

**Files:**
- Modify: `ui/UiPalette.gd`
- Modify: `ui/LuxuryTheme.gd`

**Interfaces:**
- Produces: `UiPalette.INK/FELT_DARK/FELT/FELT_LIGHT/MAHOGANY/MAHOGANY_LIGHT/GOLD_DARK/GOLD/GOLD_LIGHT/IVORY/MUTED/GLASS` — same names, new light-theme values, consumed by every other UI file automatically (no changes needed in files that only use these named constants, e.g. `render/MenuBackdrop.gd`).

- [ ] **Step 1: Recolor the palette constants**

In `D:\MonopolyGodot\monopolia\ui\UiPalette.gd`, find:

```gdscript
const INK := Color("#090d0b")
const FELT_DARK := Color("#071d14")
const FELT := Color("#0d3a27")
const FELT_LIGHT := Color("#18563b")
const MAHOGANY := Color("#2b120d")
const MAHOGANY_LIGHT := Color("#4a2116")
const GOLD_DARK := Color("#7d5d20")
const GOLD := Color("#d1a94a")
const GOLD_LIGHT := Color("#f1d98b")
const IVORY := Color("#f5efd9")
const MUTED := Color("#b5aa8d")
const DANGER := Color("#c9574f")
const SUCCESS := Color("#55bd7b")
const GLASS := Color(0.025, 0.055, 0.042, 0.92)
```

Replace with:

```gdscript
const INK := Color("#eef1f5")
const FELT_DARK := Color("#dfe4ea")
const FELT := Color("#f3f5f8")
const FELT_LIGHT := Color("#ffffff")
const MAHOGANY := Color("#c9762f")
const MAHOGANY_LIGHT := Color("#e0a05a")
const GOLD_DARK := Color("#b8933a")
const GOLD := Color("#c9a54a")
const GOLD_LIGHT := Color("#e6cf8f")
const IVORY := Color("#1e2430")
const MUTED := Color("#6c7688")
const DANGER := Color("#c9574f")
const SUCCESS := Color("#55bd7b")
const GLASS := Color(1.0, 1.0, 1.0, 0.92)
```

`DANGER`/`SUCCESS` are unchanged — both already have enough contrast on a light background (design spec §1). `IVORY` is now dark text (used everywhere as the default label/button font color) — the name no longer literally matches its value; this is a deliberate choice (see spec) to avoid a 40+ site rename for no functional gain in a solo project.

- [ ] **Step 2: Recolor the hardcoded darks inside `line_edit()`**

In the same file, find:

```gdscript
static func line_edit(focused: bool = false) -> StyleBoxFlat:
	var border := GOLD if focused else Color(0.48, 0.39, 0.20, 0.65)
	var style := panel(Color(0.018, 0.05, 0.038, 0.96), border, 7, 1, 10)
	style.shadow_size = 2
	return style
```

Replace with:

```gdscript
static func line_edit(focused: bool = false) -> StyleBoxFlat:
	var border := GOLD if focused else Color(0.75, 0.70, 0.55, 0.55)
	var style := panel(Color(1.0, 1.0, 1.0, 0.96), border, 7, 1, 10)
	style.shadow_size = 2
	return style
```

This function is used by `LuxuryTheme.create()` for every `LineEdit`/`OptionButton`/`ItemList` in the game (all screens) — its background/border were hardcoded dark literals, not routed through the constants from Step 1, so it needed a separate fix. `panel()` itself (further down in the file) is left untouched — its `shadow_color = Color(0, 0, 0, 0.55)` is a drop shadow under panels, which stays black/low-alpha even in light UIs (standard elevation convention) and does not need to change.

- [ ] **Step 3: Fix the disabled-button colors and label shadow in `LuxuryTheme.gd`**

In `D:\MonopolyGodot\monopolia\ui\LuxuryTheme.gd`, find:

```gdscript
	theme.set_color("font_color", "Label", UiPalette.IVORY)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.7))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 2)
```

Replace with:

```gdscript
	theme.set_color("font_color", "Label", UiPalette.IVORY)
	theme.set_color("font_shadow_color", "Label", Color(1, 1, 1, 0.55))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 2)
```

A black drop-shadow behind now-dark (`IVORY`) label text would look muddy; a soft white shadow reads as a subtle highlight instead, which is the light-UI equivalent of the old effect.

Then find:

```gdscript
	theme.set_stylebox("disabled", "Button", UiPalette.button(Color(0.04, 0.055, 0.05, 0.78), Color(0.2, 0.2, 0.18, 0.5)))
```

Replace with:

```gdscript
	theme.set_stylebox("disabled", "Button", UiPalette.button(Color(0.88, 0.89, 0.91, 0.78), Color(0.75, 0.76, 0.78, 0.5)))
```

The old near-black disabled-button colors were hardcoded literals (not routed through Step 1's constants) and would otherwise leave a black button floating among the new light buttons whenever something is disabled (e.g. the "Сделка" button outside your turn).

- [ ] **Step 4: Verify the file still parses**

Run:
```bash
cd "D:/MonopolyGodot/monopolia"
"/d/MonopolyGodot/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64_console.exe" --headless --path "D:/MonopolyGodot/monopolia" --quit
```
Expected: process exits without any `SCRIPT ERROR` mentioning `UiPalette.gd` or `LuxuryTheme.gd`.

- [ ] **Step 5: Commit**

```bash
cd "D:/MonopolyGodot/monopolia"
git add ui/UiPalette.gd ui/LuxuryTheme.gd
git commit -m "Recolor UiPalette/LuxuryTheme to a light theme"
```

---

### Task 2: `Hud.gd` — hardcoded panel colors

**Files:**
- Modify: `ui/Hud.gd`

**Interfaces:**
- Consumes: `UiPalette.GLASS`/`GOLD_DARK`/`GOLD` from Task 1 (already light-theme values by the time this task runs).

`Hud.gd` calls `UiPalette.panel(...)` four times with a hardcoded dark `Color(r, g, b, a)` literal as the background argument instead of a named constant — these four literals are invisible to Task 1's recolor and must be fixed here so the in-game HUD (toast, turn panel, context panel, balance/turn/players cards) isn't still dark while the rest of the game turns light.

- [ ] **Step 1: Recolor the toast background**

In `D:\MonopolyGodot\monopolia\ui\Hud.gd`, find:

```gdscript
	_toast = Label.new()
	_toast.visible = false
	_toast.add_theme_font_size_override("font_size", 20)
	_toast.add_theme_stylebox_override("normal", UiPalette.panel(
		Color(0.015, 0.05, 0.035, 0.95), UiPalette.GOLD_DARK, 8, 1, 12))
	middle.add_child(_toast)
```

Replace with:

```gdscript
	_toast = Label.new()
	_toast.visible = false
	_toast.add_theme_font_size_override("font_size", 20)
	_toast.add_theme_stylebox_override("normal", UiPalette.panel(
		Color(UiPalette.GLASS, 0.95), UiPalette.GOLD_DARK, 8, 1, 12))
	middle.add_child(_toast)
```

- [ ] **Step 2: Recolor the context panel background**

Find:

```gdscript
	_context_panel = PanelContainer.new()
	_context_panel.custom_minimum_size = Vector2(520, 0)
	_context_panel.add_theme_stylebox_override("panel", UiPalette.panel(
		Color(0.018, 0.07, 0.048, 0.96), UiPalette.GOLD, 10, 1, 12))
	bottom.add_child(_context_panel)
```

Replace with:

```gdscript
	_context_panel = PanelContainer.new()
	_context_panel.custom_minimum_size = Vector2(520, 0)
	_context_panel.add_theme_stylebox_override("panel", UiPalette.panel(
		Color(UiPalette.GLASS, 0.96), UiPalette.GOLD, 10, 1, 12))
	bottom.add_child(_context_panel)
```

- [ ] **Step 3: Recolor the turn panel background**

Find:

```gdscript
func _build_turn(parent: HBoxContainer) -> void:
	var panel := _card(Vector2(310, 0))
	panel.add_theme_stylebox_override("panel", UiPalette.panel(
		Color(0.02, 0.09, 0.06, 0.94), UiPalette.GOLD, 11, 1, 12))
	parent.add_child(panel)
```

Replace with:

```gdscript
func _build_turn(parent: HBoxContainer) -> void:
	var panel := _card(Vector2(310, 0))
	panel.add_theme_stylebox_override("panel", UiPalette.panel(
		Color(UiPalette.GLASS, 0.94), UiPalette.GOLD, 11, 1, 12))
	parent.add_child(panel)
```

- [ ] **Step 4: Recolor the shared `_card()` background**

Find:

```gdscript
func _card(minimum: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = minimum
	panel.add_theme_stylebox_override("panel", UiPalette.panel(
		Color(0.012, 0.035, 0.026, 0.92), Color(UiPalette.GOLD_DARK, 0.75), 10, 1, 11))
	return panel
```

Replace with:

```gdscript
func _card(minimum: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = minimum
	panel.add_theme_stylebox_override("panel", UiPalette.panel(
		Color(UiPalette.GLASS, 0.92), Color(UiPalette.GOLD_DARK, 0.75), 10, 1, 11))
	return panel
```

`_card()` is used by `_build_balance`, `_build_turn`, and `_build_players`, so this one fix covers the balance and players cards too.

- [ ] **Step 5: Verify and commit**

```bash
cd "D:/MonopolyGodot/monopolia"
"/d/MonopolyGodot/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64_console.exe" --headless --path "D:/MonopolyGodot/monopolia" --quit
git add ui/Hud.gd
git commit -m "Recolor Hud panel backgrounds for light theme"
```
Expected: no `SCRIPT ERROR` mentioning `Hud.gd`.

---

### Task 3: `MainMenu.gd` + `WaitingRoom.gd` + `SettingsScreen.gd` — hardcoded panel colors

**Files:**
- Modify: `ui/MainMenu.gd`
- Modify: `ui/WaitingRoom.gd`
- Modify: `ui/SettingsScreen.gd`

**Interfaces:**
- Consumes: `UiPalette.GLASS`/`GOLD_DARK` from Task 1.

Same issue as Task 2 (Hud.gd) — each of these three screens has its own hardcoded dark panel-background literal(s) that bypass the Task 1 constants.

- [ ] **Step 1: `MainMenu.gd` — the join-form card**

In `D:\MonopolyGodot\monopolia\ui\MainMenu.gd`, find:

```gdscript
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(430, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UiPalette.panel(
		Color(0.018, 0.048, 0.035, 0.74),
		Color(UiPalette.GOLD_DARK, 0.58), 14, 1, 22))
	right_column.add_child(card)
```

Replace with:

```gdscript
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(430, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UiPalette.panel(
		Color(UiPalette.GLASS, 0.74),
		Color(UiPalette.GOLD_DARK, 0.58), 14, 1, 22))
	right_column.add_child(card)
```

- [ ] **Step 2: `WaitingRoom.gd` — the main panel**

In `D:\MonopolyGodot\monopolia\ui\WaitingRoom.gd`, find:

```gdscript
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(980, 610)
	panel.add_theme_stylebox_override("panel", UiPalette.panel(
		Color(0.014, 0.042, 0.030, 0.82),
		Color(UiPalette.GOLD_DARK, 0.62), 15, 1, 26))
	center.add_child(panel)
```

Replace with:

```gdscript
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(980, 610)
	panel.add_theme_stylebox_override("panel", UiPalette.panel(
		Color(UiPalette.GLASS, 0.82),
		Color(UiPalette.GOLD_DARK, 0.62), 15, 1, 26))
	center.add_child(panel)
```

- [ ] **Step 3: `WaitingRoom.gd` — each player row**

In the same file, find:

```gdscript
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UiPalette.panel(
			Color(0.02, 0.065, 0.045, 0.58),
			Color(UiPalette.GOLD_DARK, 0.35), 8, 1, 9))
```

Replace with:

```gdscript
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UiPalette.panel(
			Color(UiPalette.GLASS, 0.58),
			Color(UiPalette.GOLD_DARK, 0.35), 8, 1, 9))
```

- [ ] **Step 4: `SettingsScreen.gd` — the main panel**

In `D:\MonopolyGodot\monopolia\ui\SettingsScreen.gd`, find:

```gdscript
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(590, 640)
	panel.add_theme_stylebox_override("panel", UiPalette.panel(
		Color(0.015, 0.043, 0.031, 0.84),
		Color(UiPalette.GOLD_DARK, 0.65), 14, 1, 26))
	center.add_child(panel)
```

Replace with:

```gdscript
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(590, 640)
	panel.add_theme_stylebox_override("panel", UiPalette.panel(
		Color(UiPalette.GLASS, 0.84),
		Color(UiPalette.GOLD_DARK, 0.65), 14, 1, 26))
	center.add_child(panel)
```

- [ ] **Step 5: Verify and commit**

```bash
cd "D:/MonopolyGodot/monopolia"
"/d/MonopolyGodot/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64_console.exe" --headless --path "D:/MonopolyGodot/monopolia" --quit
git add ui/MainMenu.gd ui/WaitingRoom.gd ui/SettingsScreen.gd
git commit -m "Recolor MainMenu/WaitingRoom/SettingsScreen panels for light theme"
```
Expected: no `SCRIPT ERROR` mentioning any of the three files.

---

### Task 4: `AssetDialog.gd` + `TokenCustomizer.gd` — hardcoded panel colors + preview environment

**Files:**
- Modify: `ui/AssetDialog.gd`
- Modify: `ui/TokenCustomizer.gd`

**Interfaces:**
- Consumes: `UiPalette.GLASS`/`GOLD_DARK`/`GOLD` from Task 1.

Same pattern again. `TokenCustomizer.gd` additionally has its own separate 3D `Environment` (for the live token preview `SubViewport`, independent of the main game's `GameScene.gd` environment) that needs the same light treatment. `TradeDialog.gd` needs **no changes** — it has no `UiPalette.panel(...)` call with a hardcoded color (its dialog panel uses the theme's default `PanelContainer` styling, already fixed by Task 1). `render/MenuBackdrop.gd` also needs **no changes** — every color it uses is a named `UiPalette` constant already.

- [ ] **Step 1: `AssetDialog.gd` — each property row**

In `D:\MonopolyGodot\monopolia\ui\AssetDialog.gd`, find:

```gdscript
	row.add_theme_stylebox_override("panel", UiPalette.panel(
		Color(0.02, 0.06, 0.043, 0.7), Color(UiPalette.GOLD_DARK, 0.4), 7, 1, 8))
```

Replace with:

```gdscript
	row.add_theme_stylebox_override("panel", UiPalette.panel(
		Color(UiPalette.GLASS, 0.7), Color(UiPalette.GOLD_DARK, 0.4), 7, 1, 8))
```

- [ ] **Step 2: `TokenCustomizer.gd` — the main panel and preview card**

In `D:\MonopolyGodot\monopolia\ui\TokenCustomizer.gd`, find:

```gdscript
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(880, 590)
	_panel.add_theme_stylebox_override("panel", UiPalette.panel(Color(0.018, 0.045, 0.033, 0.985), UiPalette.GOLD, 16, 1, 26))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
```

Replace with:

```gdscript
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(880, 590)
	_panel.add_theme_stylebox_override("panel", UiPalette.panel(Color(UiPalette.GLASS, 0.985), UiPalette.GOLD, 16, 1, 26))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
```

Then find:

```gdscript
	var preview_card := PanelContainer.new()
	preview_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_card.add_theme_stylebox_override("panel", UiPalette.panel(Color(0.01, 0.025, 0.019, 0.9), UiPalette.GOLD_DARK, 12, 1, 8))
```

Replace with:

```gdscript
	var preview_card := PanelContainer.new()
	preview_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_card.add_theme_stylebox_override("panel", UiPalette.panel(Color(UiPalette.GLASS, 0.9), UiPalette.GOLD_DARK, 12, 1, 8))
```

Do **not** change the `dim` `ColorRect` (`Color(0.005, 0.012, 0.009, 0.84)`) near the top of `_build_ui()` — that darkens everything *behind* this modal dialog and should stay dark/near-black regardless of theme, the same convention `TradeDialog.gd`/`AssetDialog.gd` already use for their own dim overlays.

- [ ] **Step 3: `TokenCustomizer.gd` — the 3D preview environment**

In the same file, find:

```gdscript
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.008, 0.02, 0.014)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.22, 0.28, 0.24)
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.35
```

Replace with:

```gdscript
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.90, 0.92, 0.95)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.97, 0.97, 0.96)
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.35
```

This is the small live-rotating token preview shown while picking a figure — separate from the main game's 3D environment (Task 5 handles that one).

- [ ] **Step 4: Verify and commit**

```bash
cd "D:/MonopolyGodot/monopolia"
"/d/MonopolyGodot/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64_console.exe" --headless --path "D:/MonopolyGodot/monopolia" --quit
git add ui/AssetDialog.gd ui/TokenCustomizer.gd
git commit -m "Recolor AssetDialog/TokenCustomizer panels and preview environment for light theme"
```
Expected: no `SCRIPT ERROR` mentioning either file.

---

### Task 5: `GameScene.gd` — light 3D environment

**Files:**
- Modify: `render/GameScene.gd`

**Interfaces:** none beyond the file itself.

- [ ] **Step 1: Recolor the world environment**

In `D:\MonopolyGodot\monopolia\render\GameScene.gd`, find:

```gdscript
func _setup_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#050806")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#385346")
	environment.ambient_light_energy = 0.44
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.15
	environment.glow_enabled = GameConfig.effects_quality > 0
	environment.glow_intensity = 0.26
	environment.glow_bloom = 0.10
	environment.glow_hdr_threshold = 1.05
	environment.ssao_enabled = GameConfig.effects_quality > 0
	environment.ssao_radius = 1.25
	environment.ssao_intensity = 0.72
	environment.fog_enabled = GameConfig.effects_quality > 1
	environment.fog_light_color = Color("#17271f")
	environment.fog_density = 0.006
	environment.fog_height = 1.0
	environment.fog_height_density = 0.18
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
```

Replace with:

```gdscript
func _setup_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#e9edf2")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#fbfbfa")
	environment.ambient_light_energy = 0.44
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.15
	environment.glow_enabled = GameConfig.effects_quality > 0
	environment.glow_intensity = 0.26
	environment.glow_bloom = 0.10
	environment.glow_hdr_threshold = 1.05
	environment.ssao_enabled = GameConfig.effects_quality > 0
	environment.ssao_radius = 1.25
	environment.ssao_intensity = 0.72
	environment.fog_enabled = GameConfig.effects_quality > 1
	environment.fog_light_color = Color("#e9edf2")
	environment.fog_density = 0.006
	environment.fog_height = 1.0
	environment.fog_height_density = 0.18
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
```

Only the three color values change (`background_color`, `ambient_light_color`, `fog_light_color`); glow/SSAO/tonemap/fog density stay as-is (lighting technique, not theme color).

- [ ] **Step 2: Verify and commit**

```bash
cd "D:/MonopolyGodot/monopolia"
"/d/MonopolyGodot/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64_console.exe" --headless --path "D:/MonopolyGodot/monopolia" --quit
git add render/GameScene.gd
git commit -m "Light-theme the game's 3D world environment"
```
Expected: no `SCRIPT ERROR` mentioning `GameScene.gd`.

---

### Task 6: `GameScene.gd` + `BoardRenderer.gd` — light felt/wood shader parameters

**Files:**
- Modify: `render/GameScene.gd`
- Modify: `render/BoardRenderer.gd`

**Interfaces:** none beyond the two files.

`render/shaders/felt.gdshader` and `render/shaders/wood.gdshader` already declare their colors as `uniform vec3 ... : source_color` with dark defaults baked into the shader — no `.gdshader` edits are needed, only passing lighter values via `ShaderMaterial.set_shader_parameter(...)` where these shaders are instantiated. `render/shaders/gold.gdshader` needs no change (its `gold_color` already reads fine on both dark and light backgrounds — confirmed by inspection during design).

- [ ] **Step 1: Add light-theme shader parameter constants and extend the material helper**

In `D:\MonopolyGodot\monopolia\render\GameScene.gd`, find:

```gdscript
const FELT_SHADER := preload("res://render/shaders/felt.gdshader")
const WOOD_SHADER := preload("res://render/shaders/wood.gdshader")
const GOLD_SHADER := preload("res://render/shaders/gold.gdshader")
const VIGNETTE_SHADER := preload("res://render/shaders/vignette.gdshader")

var _camera: Camera3D
var _table_size := 15.0 * BOARD_RENDERER.TILE_SIZE + BOARD_RENDERER.CARD_MARGIN
```

Replace with:

```gdscript
const FELT_SHADER := preload("res://render/shaders/felt.gdshader")
const WOOD_SHADER := preload("res://render/shaders/wood.gdshader")
const GOLD_SHADER := preload("res://render/shaders/gold.gdshader")
const VIGNETTE_SHADER := preload("res://render/shaders/vignette.gdshader")
## Light-theme overrides for felt.gdshader/wood.gdshader's dark shader defaults.
const LIGHT_FELT_PARAMS := {"base_color": Color(0.95, 0.96, 0.98), "fiber_color": Color(0.90, 0.92, 0.95)}
const LIGHT_WOOD_PARAMS := {"dark_wood": Color(0.45, 0.30, 0.20), "light_wood": Color(0.68, 0.50, 0.34)}

var _camera: Camera3D
var _table_size := 15.0 * BOARD_RENDERER.TILE_SIZE + BOARD_RENDERER.CARD_MARGIN
```

Then find:

```gdscript
func _shader_material(shader: Shader) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	return material
```

Replace with:

```gdscript
func _shader_material(shader: Shader, params: Dictionary = {}) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	for key in params:
		material.set_shader_parameter(key, params[key])
	return material
```

- [ ] **Step 2: Pass the light params at the table's felt/wood call sites**

Find:

```gdscript
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(_table_size + 2.2, 0.72, _table_size + 2.2)
	base.mesh = base_mesh
	base.position.y = -0.52
	base.material_override = _shader_material(WOOD_SHADER)
	table.add_child(base)

	var felt := MeshInstance3D.new()
	var felt_mesh := PlaneMesh.new()
	felt_mesh.size = Vector2(_table_size, _table_size)
	felt.mesh = felt_mesh
	felt.position.y = -0.145
	felt.material_override = _shader_material(FELT_SHADER)
	table.add_child(felt)
```

Replace with:

```gdscript
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(_table_size + 2.2, 0.72, _table_size + 2.2)
	base.mesh = base_mesh
	base.position.y = -0.52
	base.material_override = _shader_material(WOOD_SHADER, LIGHT_WOOD_PARAMS)
	table.add_child(base)

	var felt := MeshInstance3D.new()
	var felt_mesh := PlaneMesh.new()
	felt_mesh.size = Vector2(_table_size, _table_size)
	felt.mesh = felt_mesh
	felt.position.y = -0.145
	felt.material_override = _shader_material(FELT_SHADER, LIGHT_FELT_PARAMS)
	table.add_child(felt)
```

Then find:

```gdscript
func _add_rail(parent: Node3D, position: Vector3, size: Vector3) -> void:
	var rail := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	rail.mesh = mesh
	rail.position = position
	rail.material_override = _shader_material(WOOD_SHADER)
	parent.add_child(rail)
```

Replace with:

```gdscript
func _add_rail(parent: Node3D, position: Vector3, size: Vector3) -> void:
	var rail := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	rail.mesh = mesh
	rail.position = position
	rail.material_override = _shader_material(WOOD_SHADER, LIGHT_WOOD_PARAMS)
	parent.add_child(rail)
```

- [ ] **Step 3: Pass matching light felt params to the board foundation slab**

In `D:\MonopolyGodot\monopolia\render\BoardRenderer.gd`, find:

```gdscript
	var slab := MeshInstance3D.new()
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(board_world_size, 0.22, board_world_size)
	slab.mesh = slab_mesh
	slab.position.y = -0.03
	var slab_material := ShaderMaterial.new()
	slab_material.shader = FELT_SHADER
	slab.material_override = slab_material
	_decor_root.add_child(slab)
```

Replace with:

```gdscript
	var slab := MeshInstance3D.new()
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(board_world_size, 0.22, board_world_size)
	slab.mesh = slab_mesh
	slab.position.y = -0.03
	var slab_material := ShaderMaterial.new()
	slab_material.shader = FELT_SHADER
	slab_material.set_shader_parameter("base_color", Color(0.95, 0.96, 0.98))
	slab_material.set_shader_parameter("fiber_color", Color(0.90, 0.92, 0.95))
	slab.material_override = slab_material
	_decor_root.add_child(slab)
```

`BoardRenderer.gd` builds this `ShaderMaterial` directly rather than through `GameScene`'s `_shader_material()` helper (different class, no shared helper between them), so the same two color literals are duplicated here rather than referencing `GameScene.LIGHT_FELT_PARAMS` — an accepted, intentional small duplication (two color literals, not worth introducing a shared module for).

- [ ] **Step 4: Verify and commit**

```bash
cd "D:/MonopolyGodot/monopolia"
"/d/MonopolyGodot/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64_console.exe" --headless --path "D:/MonopolyGodot/monopolia" --quit
git add render/GameScene.gd render/BoardRenderer.gd
git commit -m "Light-theme the felt/wood shader materials"
```
Expected: no `SCRIPT ERROR` mentioning either file.

---

### Task 7: `BoardRenderer.gd` — recolor property cards, tiles, labels, center seal

**Files:**
- Modify: `render/BoardRenderer.gd`

**Interfaces:** none beyond the file itself.

- [ ] **Step 1: Recolor the tile base material's blend target**

In `D:\MonopolyGodot\monopolia\render\BoardRenderer.gd`, find:

```gdscript
	var material := StandardMaterial3D.new()
	var accent := ColorUtil.to_color(cell.get("color", "#c7b998"))
	material.albedo_color = accent.lerp(Color("#e8dfc7"), 0.72 if not is_corner else 0.35)
	material.roughness = 0.62
	material.metallic = 0.06
	tile.material_override = material
```

Replace with:

```gdscript
	var material := StandardMaterial3D.new()
	var accent := ColorUtil.to_color(cell.get("color", "#c7b998"))
	material.albedo_color = accent.lerp(Color("#eef1f5"), 0.72 if not is_corner else 0.35)
	material.roughness = 0.62
	material.metallic = 0.06
	tile.material_override = material
```

- [ ] **Step 2: Recolor the property card row (border/fill/label)**

Find:

```gdscript
	var border := MeshInstance3D.new()
	var border_mesh := BoxMesh.new()
	border_mesh.size = bar_size
	border.mesh = border_mesh
	border.position = center + Vector3(0, lift + 0.01, 0)
	var border_material := StandardMaterial3D.new()
	border_material.albedo_color = Color("#2a2a2a")
	border.material_override = border_material
	_tiles_root.add_child(border)

	var fill := MeshInstance3D.new()
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = bar_size - inset * 2.0
	fill.mesh = fill_mesh
	fill.position = center + Vector3(0, lift + 0.018, 0)
	var fill_material := StandardMaterial3D.new()
	fill_material.albedo_color = Color("#d9d9d9")
	fill.material_override = fill_material
	_tiles_root.add_child(fill)

	var label := Label3D.new()
	label.text = text
	label.font_size = 44
	label.pixel_size = 0.0042 * TILE_SIZE
	label.modulate = Color("#1a1a1a")
	label.no_depth_test = true
	label.render_priority = 2
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.rotation_degrees = Vector3(-90, rotation_y, 0)
	label.position = center + Vector3(0, lift + 0.03, 0)
	_tiles_root.add_child(label)
```

Replace with:

```gdscript
	var border := MeshInstance3D.new()
	var border_mesh := BoxMesh.new()
	border_mesh.size = bar_size
	border.mesh = border_mesh
	border.position = center + Vector3(0, lift + 0.01, 0)
	var border_material := StandardMaterial3D.new()
	border_material.albedo_color = Color("#c7cdd6")
	border.material_override = border_material
	_tiles_root.add_child(border)

	var fill := MeshInstance3D.new()
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = bar_size - inset * 2.0
	fill.mesh = fill_mesh
	fill.position = center + Vector3(0, lift + 0.018, 0)
	var fill_material := StandardMaterial3D.new()
	fill_material.albedo_color = Color("#ffffff")
	fill.material_override = fill_material
	_tiles_root.add_child(fill)

	var label := Label3D.new()
	label.text = text
	label.font_size = 44
	label.pixel_size = 0.0042 * TILE_SIZE
	label.modulate = Color("#1e2430")
	label.no_depth_test = true
	label.render_priority = 2
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.rotation_degrees = Vector3(-90, rotation_y, 0)
	label.position = center + Vector3(0, lift + 0.03, 0)
	_tiles_root.add_child(label)
```

- [ ] **Step 3: Recolor the non-property tile label (corners/special cells)**

Find:

```gdscript
	label.text = name
	label.font_size = 58 if is_corner else (44 if not ladder.is_empty() else 52)
	label.pixel_size = (0.0048 if is_corner else 0.0045) * TILE_SIZE
	label.modulate = Color("#100b08")
	label.outline_size = 10
	label.outline_modulate = Color(1.0, 0.97, 0.86, 0.96)
```

Replace with:

```gdscript
	label.text = name
	label.font_size = 58 if is_corner else (44 if not ladder.is_empty() else 52)
	label.pixel_size = (0.0048 if is_corner else 0.0045) * TILE_SIZE
	label.modulate = Color("#1e2430")
	label.outline_size = 10
	label.outline_modulate = Color(1.0, 1.0, 1.0, 0.96)
```

- [ ] **Step 4: Recolor the center seal**

Find:

```gdscript
	var seal_material := StandardMaterial3D.new()
	seal_material.albedo_color = Color("#092f20")
	seal_material.roughness = 0.76
	seal_material.metallic = 0.12
	seal.material_override = seal_material
```

Replace with:

```gdscript
	var seal_material := StandardMaterial3D.new()
	seal_material.albedo_color = Color("#2a3550")
	seal_material.roughness = 0.76
	seal_material.metallic = 0.12
	seal.material_override = seal_material
```

The center seal is kept as a deliberately darker slate-blue accent (a small focal detail), rather than blended into the light board — the gold ring and "MONOPOLIS" logotype around/on it are unchanged and already read fine against either color (design judgment call; revisit in Task 11's playtest if it looks out of place).

- [ ] **Step 5: Verify and commit**

```bash
cd "D:/MonopolyGodot/monopolia"
"/d/MonopolyGodot/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64_console.exe" --headless --path "D:/MonopolyGodot/monopolia" --quit
git add render/BoardRenderer.gd
git commit -m "Light-theme property card rows, tile labels and center seal"
```
Expected: no `SCRIPT ERROR` mentioning `BoardRenderer.gd`.

---

### Task 8: `BoardRenderer.gd` — increase tile size

**Files:**
- Modify: `render/BoardRenderer.gd`

**Interfaces:**
- Produces: `BoardRenderer.TILE_SIZE = 2.2` (was `1.6`) — `CARD_MARGIN` (`TILE_SIZE * 1.4`) and every other proportion in the file are already computed from `TILE_SIZE`, so they scale automatically; `GameScene.gd`'s `_table_size` (`15.0 * BOARD_RENDERER.TILE_SIZE + BOARD_RENDERER.CARD_MARGIN`) also scales automatically without further changes.

- [ ] **Step 1: Bump `TILE_SIZE`**

In `D:\MonopolyGodot\monopolia\render\BoardRenderer.gd`, find:

```gdscript
## World-unit footprint of one board cell. Bumped up from the original 1.0 so
## tiles are big enough to read their card (icon/name/price/rent ladder)
## instead of looking like a small block of overlapping text.
const TILE_SIZE := 1.6
```

Replace with:

```gdscript
## World-unit footprint of one board cell. Bumped up from the original 1.0,
## then again to 2.2 for the light-theme redesign so tiles are big enough to
## read their card (icon/name/price/rent ladder) instead of looking like a
## small block of overlapping text - especially for longer company names.
const TILE_SIZE := 2.2
```

- [ ] **Step 2: Verify and commit**

```bash
cd "D:/MonopolyGodot/monopolia"
"/d/MonopolyGodot/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64_console.exe" --headless --path "D:/MonopolyGodot/monopolia" --quit
git add render/BoardRenderer.gd
git commit -m "Increase board tile size for readability"
```
Expected: no `SCRIPT ERROR` mentioning `BoardRenderer.gd`. Final visual confirmation (does the board still fit the screen well at this size) happens in Task 11 — if it doesn't, that task's manual step calls out adjusting this constant.

---

### Task 9: `render/TableCamera.gd` — new perspective seat camera

**Files:**
- Create: `render/TableCamera.gd`

**Interfaces:**
- Produces: `TableCamera.set_table_size(size: float) -> void`, `TableCamera.reset_to_seat(order: int, player_count: int) -> void` — both consumed by Task 10.

- [ ] **Step 1: Create the camera script**

Create `D:\MonopolyGodot\monopolia\render\TableCamera.gd`:

```gdscript
class_name TableCamera
extends Camera3D
## Perspective camera anchored to the local player's seat around the table.
##
## Starts looking at the table from that seat (see reset_to_seat, called once
## by GameScene after the local player's seat is known). Dragging rotates it
## horizontally around the table's vertical axis at a fixed height and
## radius - no zoom, no tilt, no free movement, and no auto-return to the
## seat once the player has dragged it elsewhere.

const FOV_DEGREES := 60.0
const HEIGHT_RATIO := 0.55
const RADIUS_RATIO := 0.85
const LOOK_AT_HEIGHT := 0.3
const DRAG_SENSITIVITY := 0.006

var _table_size := 15.0
var _angle := 0.0
var _dragging := false
var _drag_last_x := 0.0

func _ready() -> void:
	projection = Camera3D.PROJECTION_PERSPECTIVE
	fov = FOV_DEGREES
	current = true
	_update_position()

## Called whenever the active ruleset's board size changes (e.g. switching
## between classic's 15 and megapolis's 11). Keeps the orbit radius/height
## matched to the table without resetting the angle the player rotated to.
func set_table_size(size: float) -> void:
	_table_size = size
	_update_position()

## Called once, when the local player's seat is first known - sets the
## starting angle at that seat. Never called again on later snapshots, so it
## never fights the player's own dragging.
func reset_to_seat(order: int, player_count: int) -> void:
	_angle = TAU * float(order) / float(maxi(player_count, 1))
	_update_position()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_drag_last_x = event.position.x
	elif event is InputEventMouseMotion and _dragging:
		var delta_x := event.position.x - _drag_last_x
		_drag_last_x = event.position.x
		_angle -= delta_x * DRAG_SENSITIVITY
		_update_position()

func _update_position() -> void:
	var radius := _table_size * RADIUS_RATIO
	var height := _table_size * HEIGHT_RATIO
	position = Vector3(sin(_angle) * radius, height, cos(_angle) * radius)
	look_at(Vector3(0, LOOK_AT_HEIGHT, 0), Vector3.UP)
```

Dragging is implemented with `_unhandled_input` (not `_input`), so a click that lands on an actual HUD `Button` (which stops the event via Godot's normal GUI input propagation) never reaches this handler and never gets misread as a camera drag — no special "ignore clicks on UI" logic is needed here. Godot's `Camera3D` with the default `keep_aspect` (`KEEP_HEIGHT`) already adapts its horizontal field of view to the viewport's aspect ratio on its own, so no window-resize handling is needed either.

- [ ] **Step 2: Verify the file parses**

Run:
```bash
cd "D:/MonopolyGodot/monopolia"
"/d/MonopolyGodot/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64_console.exe" --headless --path "D:/MonopolyGodot/monopolia" --quit
```
Expected: no `SCRIPT ERROR` mentioning `TableCamera.gd`. (It isn't wired into anything yet — Task 10 does that — so this only confirms the script compiles standalone.)

- [ ] **Step 3: Commit**

```bash
cd "D:/MonopolyGodot/monopolia"
git add render/TableCamera.gd
git commit -m "Add TableCamera: perspective seat-anchored orbit camera"
```

---

### Task 10: `GameScene.gd` — wire `TableCamera` in

**Files:**
- Modify: `render/GameScene.gd`

**Interfaces:**
- Consumes: `TableCamera.set_table_size`/`reset_to_seat` from Task 9.

- [ ] **Step 1: Preload `TableCamera` and retype the `_camera` field**

In `D:\MonopolyGodot\monopolia\render\GameScene.gd`, find:

```gdscript
const BOARD_RENDERER := preload("res://render/BoardRenderer.gd")
const HUD_SCRIPT := preload("res://ui/Hud.gd")
const FELT_SHADER := preload("res://render/shaders/felt.gdshader")
const WOOD_SHADER := preload("res://render/shaders/wood.gdshader")
const GOLD_SHADER := preload("res://render/shaders/gold.gdshader")
const VIGNETTE_SHADER := preload("res://render/shaders/vignette.gdshader")
## Light-theme overrides for felt.gdshader/wood.gdshader's dark shader defaults.
const LIGHT_FELT_PARAMS := {"base_color": Color(0.95, 0.96, 0.98), "fiber_color": Color(0.90, 0.92, 0.95)}
const LIGHT_WOOD_PARAMS := {"dark_wood": Color(0.45, 0.30, 0.20), "light_wood": Color(0.68, 0.50, 0.34)}

var _camera: Camera3D
var _table_size := 15.0 * BOARD_RENDERER.TILE_SIZE + BOARD_RENDERER.CARD_MARGIN
```

Replace with:

```gdscript
const BOARD_RENDERER := preload("res://render/BoardRenderer.gd")
const HUD_SCRIPT := preload("res://ui/Hud.gd")
const TABLE_CAMERA := preload("res://render/TableCamera.gd")
const FELT_SHADER := preload("res://render/shaders/felt.gdshader")
const WOOD_SHADER := preload("res://render/shaders/wood.gdshader")
const GOLD_SHADER := preload("res://render/shaders/gold.gdshader")
const VIGNETTE_SHADER := preload("res://render/shaders/vignette.gdshader")
## Light-theme overrides for felt.gdshader/wood.gdshader's dark shader defaults.
const LIGHT_FELT_PARAMS := {"base_color": Color(0.95, 0.96, 0.98), "fiber_color": Color(0.90, 0.92, 0.95)}
const LIGHT_WOOD_PARAMS := {"dark_wood": Color(0.45, 0.30, 0.20), "light_wood": Color(0.68, 0.50, 0.34)}

var _camera: TableCamera
var _table_size := 15.0 * BOARD_RENDERER.TILE_SIZE + BOARD_RENDERER.CARD_MARGIN
```

- [ ] **Step 2: Replace `_setup_camera`/`_fit_camera` with the `TableCamera`-based equivalents**

Find:

```gdscript
func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.position = Vector3(0, 18.5, 10.0)
	_camera.rotation_degrees = Vector3(-62.0, 0, 0)
	_camera.current = true
	add_child(_camera)

func _fit_camera() -> void:
	if _camera == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.y <= 0:
		return
	var aspect := viewport_size.x / viewport_size.y
	var board_extent := float(NetworkManager.local_board.size if NetworkManager.local_board != null else 15) \
			* BOARD_RENDERER.TILE_SIZE + BOARD_RENDERER.CARD_MARGIN
	# The camera looks down at a steep -62 degree pitch, so the board's depth
	# is heavily foreshortened on screen - fitting to the raw board_extent (as
	# if viewed from straight above) left the whole board looking tiny with a
	# huge unused margin. These tighter factors zoom in close to the actual
	# foreshortened silhouette while still leaving the HUD's screen corners clear.
	var vertical_fit := board_extent * 0.72
	var horizontal_fit := (board_extent * 0.95) / maxf(aspect, 0.75)
	_camera.size = maxf(vertical_fit, horizontal_fit)
	_camera.position = Vector3(0, board_extent * 1.25, board_extent * 0.66)
```

Replace with:

```gdscript
func _setup_camera() -> void:
	_camera = TABLE_CAMERA.new()
	add_child(_camera)
	_camera.set_table_size(_table_size)

## Sets the local player's starting camera angle from their table seat.
## Deferred so NetworkManager.local_players (populated from earlier lobby
## snapshots) is settled before we read it.
func _init_camera_seat() -> void:
	if _camera == null:
		return
	_camera.reset_to_seat(_local_seat_order(), maxi(NetworkManager.local_players.size(), 1))

func _local_seat_order() -> int:
	var peer := NetworkManager.get_local_peer_id()
	for player in NetworkManager.local_players:
		if player.peer_id == peer:
			return player.order
	return 0
```

- [ ] **Step 3: Update `_ready()` and `_on_game_state_changed()`**

Find:

```gdscript
func _ready() -> void:
	_setup_environment()
	_setup_table()
	_setup_lights()
	_setup_camera()
	_setup_particles()
	var board := BOARD_RENDERER.new()
	board.name = "Board"
	add_child(board)
	_setup_vignette()
	_setup_hud()
	EventBus.game_state_changed.connect(_on_game_state_changed)
	get_viewport().size_changed.connect(_fit_camera)
	call_deferred("_fit_camera")

func _on_game_state_changed(_snapshot: Dictionary) -> void:
	if NetworkManager.local_board != null:
		_table_size = maxf(
			15.0 * BOARD_RENDERER.TILE_SIZE + BOARD_RENDERER.CARD_MARGIN,
			float(NetworkManager.local_board.size) * BOARD_RENDERER.TILE_SIZE + BOARD_RENDERER.CARD_MARGIN)
	_fit_camera()
```

Replace with:

```gdscript
func _ready() -> void:
	_setup_environment()
	_setup_table()
	_setup_lights()
	_setup_camera()
	_setup_particles()
	var board := BOARD_RENDERER.new()
	board.name = "Board"
	add_child(board)
	_setup_vignette()
	_setup_hud()
	EventBus.game_state_changed.connect(_on_game_state_changed)
	call_deferred("_init_camera_seat")

func _on_game_state_changed(_snapshot: Dictionary) -> void:
	if NetworkManager.local_board != null:
		_table_size = maxf(
			15.0 * BOARD_RENDERER.TILE_SIZE + BOARD_RENDERER.CARD_MARGIN,
			float(NetworkManager.local_board.size) * BOARD_RENDERER.TILE_SIZE + BOARD_RENDERER.CARD_MARGIN)
	if _camera != null:
		_camera.set_table_size(_table_size)
```

`Camera3D`'s perspective projection auto-adapts to viewport aspect changes on its own (see Task 9), so the `get_viewport().size_changed` connection and the old `_fit_camera` polling are removed rather than ported.

- [ ] **Step 4: Verify and commit**

```bash
cd "D:/MonopolyGodot/monopolia"
"/d/MonopolyGodot/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64_console.exe" --headless --path "D:/MonopolyGodot/monopolia" --quit
git add render/GameScene.gd
git commit -m "Wire TableCamera into GameScene, replacing the fixed top-down camera"
```
Expected: no `SCRIPT ERROR` mentioning `GameScene.gd`.

---

### Task 11: Manual verification playtest

**Files:** none (verification only)

**Interfaces:** none — this exercises everything from Tasks 1-10 end-to-end in the running game.

- [ ] **Step 1: Launch and check every screen is light**

Run:
```bash
cd "D:/MonopolyGodot/monopolia"
"/d/MonopolyGodot/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64.exe" --path "D:/MonopolyGodot/monopolia"
```

Walk through: main menu → "Фигурка" (token customizer) → "Настройки" (settings) → back → host a solo test game → in-game HUD → "Активы" (asset dialog) → propose a trade with a second local peer if possible, or at least open the trade dialog UI. Every panel/card/background across all of these should read as light (white/light-gray backgrounds, dark text), not the old near-black theme. The token customizer's live 3D preview background should also be light, not dark green-black.

- [ ] **Step 2: Check the 3D board and table**

In a solo test game: confirm the table surface (felt) and table base/rails (wood) are a light neutral tone rather than dark green/mahogany, the board slab under the tiles is light, and property cards (icon + name + price + rent rows) are white/light-bordered with dark readable text. Compare against the brainstorm mockup style (light card, similar structure to before). Confirm tiles are noticeably larger than before (Task 8) and that long property names (e.g. any long entries if `megapolis` ruleset is available) fit on one line without obvious crowding — if they still look cramped, increase `BoardRenderer.TILE_SIZE` further and re-verify.

- [ ] **Step 3: Check the camera**

Still in the solo test game: confirm the camera is now a perspective view (near objects visibly larger than far ones, not the old flat top-down look) positioned at your own seat. Click-drag left and right on empty board area (not on a HUD button) and confirm the camera orbits horizontally around the table smoothly, staying at a constant height (doesn't tilt up/down, doesn't zoom in/out). Release the drag and confirm the camera stays where you left it (does not spring back to the seat). Click and drag starting **on** a HUD button (e.g. "Активы") and confirm it performs the button's action instead of rotating the camera.

- [ ] **Step 4: Check with 2+ seats if possible**

If you can run a second local client (or host + join from the same machine), confirm each client's camera starts at a **different** angle (their own seat), not all clustered at the same spot.

- [ ] **Step 5: Regression-check `classic`**

Confirm all of the above (light theme, tile size, camera) apply identically when playing the `classic` ruleset, not just `megapolis` — this feature is deliberately ruleset-agnostic.

- [ ] **Step 6: Final push**

```bash
cd "D:/MonopolyGodot/monopolia"
git status
git push origin feature/light-theme-camera
```
Expected: `git status` shows a clean tree (everything from Tasks 1-10 was already committed per-task); push succeeds.
