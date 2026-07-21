# Mods / DLC

Drop a pack folder here (or into `user://mods` for an installed build) and it
will be discovered automatically by the `ModLoader` at startup.

## Pack layout

```
my_pack/
  pack.json
  content/
	cells/*.json
	tokens/*.json
	roles/*.json
	rulesets/*.json
	cards/*.json
	sounds/*.json
  scripts/
	main.gd        (optional entry point)
  models/
	*.glb / *.gltf / *.tscn   (optional, see "Custom 3D models" below)
```

## pack.json

```json
{
  "id": "my_pack",
  "name": "My Expansion",
  "version": "1.0.0",
  "api_version": 2,
  "dependencies": ["core"],
  "load_after": ["core"],
  "replaces": [],
  "entry": "scripts/main.gd",
  "scene_overrides": {
	"main_menu": "scenes/MyMenu.tscn",
	"waiting_room": "scenes/MyLobby.tscn",
	"game": "scenes/MyGame.tscn",
	"settings": "scenes/MySettings.tscn",
	"server": "scenes/MyServer.tscn"
  },
  "resources": ["scenes", "scripts", "assets", "models"],
  "content": {
	"cells": "content/cells",
	"tokens": "content/tokens",
	"roles": "content/roles",
	"rulesets": "content/rulesets",
	"cards": "content/cards",
	"sounds": "content/sounds"
  }
}
```

## Key rules

- Every content id becomes namespaced: `packId:localId` (e.g. `my_pack:cell_casino`).
- Packs loaded later override content with the same full id. To fully convert
  the base game, redefine `core:*` ids or ship your own ruleset.
- The entry script's `setup(pack_id)` runs on the server after all content is
  loaded. Register gameplay via `EventBus.add_hook(name, callable, priority)`.
- `scene_overrides` replaces any major application entry point. A full
  conversion can therefore replace the menu, lobby, game renderer/UI, settings
  and dedicated server instead of patching vanilla scenes.
- `resources` lists pack-owned directories included recursively in the
  multiplayer signature (scenes, scripts, shaders, audio and other assets).
- Entry scripts are trusted code with normal Godot access. They may register
  hooks, autoload-like child nodes, custom networking and entirely new rules.
  Only install mods from trusted sources.
- Server and client must load an identical set of packs. On connect the server
  sends its pack signature; a mismatch disconnects the client with a diff so
  there is never a silent version desync.

## api_version

The engine advertises a single `ModLoader.API_VERSION`. A pack that targets a
different value is skipped, so incompatible packs fail loudly instead of
corrupting a session.

Sound definitions bind logical events (for example `game.dice_roll`) to one or
more audio streams. A later DLC can override the same sound id; if no stream is
provided, vanilla supports a procedural `tone` fallback.

## Property rent growth and icons

Property cells (`type: "property"`) may set:

- `"rent_growth"` (float, default `1.0`) - rent for that property scales by
  `rent_growth ^ (owned_in_group - 1)` once the owner holds more than one
  property of the same `group`, before any houses are built (once houses/hotel
  are built, the property's own `rent_table` tier is used as-is). This replaces
  a single lump "own the whole group" bonus with a smooth ramp, so partial
  ownership of a group already charges a bit more, without spiking the moment
  the last property is bought. `1.0` (the default) disables growth entirely.
- `"icon"` (string, optional) - path to a texture (relative to the pack root)
  shown on the board tile. If omitted or unresolvable, a generic placeholder
  emblem is shown instead, so every property tile always reserves the same
  visual slot for a logo even before one is supplied.

The board tile shows the property's name, price, and a rent preview ladder
(rent at 1, 2, 3, ... up to owning the whole group) computed from
`rent_growth`, so players can see the payoff of building a monopoly before
they commit to buying.

## Custom 3D models

By default tokens, board tiles, dice and the table are built procedurally out
of primitives. A pack may instead supply its own model by adding one of these
optional fields to its content JSON. The path is relative to the pack root
(e.g. `"models/token_top_hat.glb"`); `.glb`/`.gltf` and Godot `.tscn` scenes are
both accepted.

| Content file | Field | Replaces |
|---|---|---|
| `content/tokens/*.json` | `model` | The whole token body (base + shape). |
| `content/cells/*.json` | `decor_model` | Nothing existing - purely additive decor placed on top of the tile. |
| `content/rulesets/*.json` | `dice_model` | The procedural die box (the rolled number is still overlaid as a label). |
| `content/rulesets/*.json` | `board_model` | The board's foundation slab, gold trim and center seal (tiles/tokens/labels are unaffected and still positioned by the engine). |
| `content/rulesets/*.json` | `table_model` | The whole procedural table/rails in the game scene. |

Any folder holding model files must be listed under `pack.json` →
`"resources"` (e.g. `"resources": ["models"]`) so the files are included in the
multiplayer desync signature like any other pack-owned asset.

Notes:
- Custom token models are **static** - the player's color/finish customization
  is not applied to them; the model's own materials are used as-is.
- If a referenced model is missing or fails to load, the engine logs a warning
  and falls back to the normal procedural rendering - a broken model can never
  crash the game.
- `resolve_path` rejects any path containing `..`, so a model reference cannot
  escape its own pack folder.
- `.glb`/`.gltf` only ever contains geometry, materials and animations - no
  executable code. A `.tscn` scene, however, can carry an attached GDScript
  just like any Godot scene. That is **not** a new trust boundary: pack entry
  scripts are already fully trusted GDScript with normal engine access (see
  above), so the same rule applies - only install mods from trusted sources.
