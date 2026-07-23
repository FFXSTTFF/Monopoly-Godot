class_name UiPalette
extends RefCounted
## Shared luxury palette and style factories for every vanilla screen.

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

static func panel(
		background: Color = GLASS,
		border: Color = GOLD_DARK,
		radius: int = 12,
		border_width: int = 1,
		padding: int = 18
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 5)
	return style

static func button(background: Color, border: Color, raised: bool = false) -> StyleBoxFlat:
	var style := panel(background, border, 7, 1, 8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.shadow_size = 8 if raised else 3
	style.shadow_offset = Vector2(0, 4 if raised else 1)
	return style

static func line_edit(focused: bool = false) -> StyleBoxFlat:
	var border := GOLD if focused else Color(0.75, 0.70, 0.55, 0.55)
	var style := panel(Color(1.0, 1.0, 1.0, 0.96), border, 7, 1, 10)
	style.shadow_size = 2
	return style
