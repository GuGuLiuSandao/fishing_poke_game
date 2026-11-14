extends RefCounted

const INK := Color("#f6f0e5")
const MUTED := Color("#b9b2a5")
const GOLD := Color("#f2cd86")
const GOLD_INK := Color("#211709")
const PANEL := Color("#171b1c")
const BORDER := Color("#393b38")
const DARK := Color("#101314")
const RED := Color("#623138")

static func build() -> Theme:
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Inter", "PingFang SC", "Microsoft YaHei UI", "Noto Sans CJK SC"])
	theme.default_font = font
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", INK)
	theme.set_color("default_color", "RichTextLabel", INK)
	theme.set_constant("line_separation", "RichTextLabel", 7)
	theme.set_stylebox("panel", "PanelContainer", box(PANEL, BORDER, 12))
	theme.set_stylebox("normal", "LineEdit", box(DARK, BORDER, 8))
	theme.set_stylebox("focus", "LineEdit", focus_box(8))
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_selected_color", "LineEdit", GOLD_INK)
	theme.set_color("selection_color", "LineEdit", GOLD)
	theme.set_color("caret_color", "LineEdit", GOLD)
	theme.set_stylebox("slider", "HSlider", track(Color("#3b3e38")))
	theme.set_stylebox("grabber_area", "HSlider", track(Color("#bd985a")))
	theme.set_stylebox("grabber_area_highlight", "HSlider", track(GOLD))
	theme.set_icon("grabber", "HSlider", knob(GOLD))
	theme.set_icon("grabber_highlight", "HSlider", knob(Color("#ffe6b7")))
	theme.set_icon("grabber_disabled", "HSlider", knob(MUTED))
	set_button_theme(theme, "Button", Color("#282d2d"), INK)
	set_button_theme(theme, "Quiet", Color("#1a1e1e"), MUTED)
	set_button_theme(theme, "Gold", GOLD, GOLD_INK)
	set_button_theme(theme, "Red", RED, INK)
	return theme

static func set_button_theme(theme: Theme, style_name: String, fill: Color, ink: Color) -> void:
	if style_name != "Button":
		theme.set_type_variation(style_name, "Button")
	theme.set_stylebox("normal", style_name, box(fill, fill.lightened(0.13), 8))
	theme.set_stylebox("hover", style_name, box(fill.lightened(0.09), fill.lightened(0.28), 8))
	theme.set_stylebox("pressed", style_name, box(fill.darkened(0.08), fill.lightened(0.25), 8))
	theme.set_stylebox("disabled", style_name, box(DARK, BORDER, 8))
	theme.set_stylebox("focus", style_name, focus_box(8))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(state, style_name, ink)
	theme.set_color("font_disabled_color", style_name, Color("#938e84"))

static func box(fill: Color, border: Color, radius: int, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_corner_radius_all(radius)
	style.set_border_width_all(width)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

static func focus_box(radius: int) -> StyleBoxFlat:
	var style := box(Color.TRANSPARENT, Color("#fff0c8"), radius, 2)
	style.draw_center = false
	return style

static func track(color: Color) -> StyleBoxFlat:
	var style := box(color, Color.TRANSPARENT, 4, 0)
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style

static func knob(color: Color) -> Texture2D:
	var texture := GradientTexture2D.new()
	texture.width = 21
	texture.height = 21
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.98, 0.5)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.78, 0.89, 1.0])
	gradient.colors = PackedColorArray([color, color, color.darkened(0.23), Color.TRANSPARENT])
	texture.gradient = gradient
	return texture

static func label(value: String, font_size: int, color: Color = INK) -> Label:
	var node := Label.new()
	node.text = value
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	return node

static func button(value: String, style_name: String = "Button", height: int = 44) -> Button:
	var node := Button.new()
	node.text = value
	node.theme_type_variation = style_name
	node.custom_minimum_size.y = height
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return node

static func spacer() -> Control:
	var node := Control.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

static func margin(x: int, y: int) -> MarginContainer:
	var node := MarginContainer.new()
	node.add_theme_constant_override("margin_left", x)
	node.add_theme_constant_override("margin_right", x)
	node.add_theme_constant_override("margin_top", y)
	node.add_theme_constant_override("margin_bottom", y)
	return node
