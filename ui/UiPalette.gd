class_name UiPalette
extends RefCounted
## Shared luxury palette and style factories for every vanilla screen.

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
	var border := GOLD if focused else Color(0.48, 0.39, 0.20, 0.65)
	var style := panel(Color(0.018, 0.05, 0.038, 0.96), border, 7, 1, 10)
	style.shadow_size = 2
	return style
