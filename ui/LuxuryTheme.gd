class_name LuxuryTheme
extends RefCounted
## Programmatic theme keeps vanilla UI consistent and lets DLC screens opt in.

static func create() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 16

	theme.set_color("font_color", "Label", UiPalette.IVORY)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.7))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 2)

	theme.set_stylebox("panel", "PanelContainer", UiPalette.panel())

	theme.set_color("font_color", "Button", UiPalette.IVORY)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", UiPalette.GOLD_LIGHT)
	theme.set_color("font_disabled_color", "Button", Color(UiPalette.MUTED, 0.45))
	theme.set_stylebox("normal", "Button", UiPalette.button(UiPalette.FELT_DARK, UiPalette.GOLD_DARK))
	theme.set_stylebox("hover", "Button", UiPalette.button(UiPalette.FELT, UiPalette.GOLD, true))
	theme.set_stylebox("pressed", "Button", UiPalette.button(UiPalette.MAHOGANY_LIGHT, UiPalette.GOLD_LIGHT))
	theme.set_stylebox("disabled", "Button", UiPalette.button(Color(0.04, 0.055, 0.05, 0.78), Color(0.2, 0.2, 0.18, 0.5)))
	theme.set_stylebox("focus", "Button", UiPalette.button(Color.TRANSPARENT, UiPalette.GOLD_LIGHT))

	theme.set_color("font_color", "LineEdit", UiPalette.IVORY)
	theme.set_color("font_placeholder_color", "LineEdit", Color(UiPalette.MUTED, 0.7))
	theme.set_color("caret_color", "LineEdit", UiPalette.GOLD_LIGHT)
	theme.set_color("selection_color", "LineEdit", Color(UiPalette.GOLD, 0.3))
	theme.set_stylebox("normal", "LineEdit", UiPalette.line_edit())
	theme.set_stylebox("focus", "LineEdit", UiPalette.line_edit(true))

	theme.set_color("font_color", "OptionButton", UiPalette.IVORY)
	theme.set_stylebox("normal", "OptionButton", UiPalette.line_edit())
	theme.set_stylebox("hover", "OptionButton", UiPalette.line_edit(true))
	theme.set_stylebox("pressed", "OptionButton", UiPalette.line_edit(true))

	theme.set_stylebox("panel", "PopupMenu", UiPalette.panel(UiPalette.INK, UiPalette.GOLD_DARK, 8, 1, 8))
	theme.set_color("font_color", "PopupMenu", UiPalette.IVORY)
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	theme.set_stylebox("hover", "PopupMenu", UiPalette.panel(UiPalette.FELT, UiPalette.GOLD_DARK, 4, 0, 4))

	theme.set_stylebox("panel", "ItemList", UiPalette.line_edit())
	theme.set_color("font_color", "ItemList", UiPalette.IVORY)
	theme.set_color("font_selected_color", "ItemList", UiPalette.GOLD_LIGHT)
	theme.set_stylebox("selected", "ItemList", UiPalette.panel(Color(UiPalette.FELT, 0.92), UiPalette.GOLD, 6, 1, 5))
	theme.set_stylebox("selected_focus", "ItemList", UiPalette.panel(Color(UiPalette.FELT, 0.92), UiPalette.GOLD_LIGHT, 6, 1, 5))

	theme.set_icon("grabber", "HSlider", _circle_icon(UiPalette.GOLD_LIGHT, 9))
	theme.set_stylebox("slider", "HSlider", _bar_style(UiPalette.MAHOGANY_LIGHT, 6))
	theme.set_stylebox("grabber_area", "HSlider", _bar_style(UiPalette.GOLD, 6))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _bar_style(UiPalette.GOLD_LIGHT, 6))

	theme.set_stylebox("panel", "TooltipPanel", UiPalette.panel(UiPalette.INK, UiPalette.GOLD_DARK, 6, 1, 8))
	theme.set_color("font_color", "TooltipLabel", UiPalette.IVORY)
	return theme

static func _bar_style(color: Color, height: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(height / 2)
	style.content_margin_top = height
	style.content_margin_bottom = height
	return style

static func _circle_icon(color: Color, radius: int) -> ImageTexture:
	var size := radius * 2 + 2
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var center := Vector2(radius + 1, radius + 1)
	for y in size:
		for x in size:
			if Vector2(x, y).distance_to(center) <= radius:
				image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)
