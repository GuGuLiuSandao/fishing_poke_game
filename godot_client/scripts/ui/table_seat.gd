extends Control

const Styles = preload("res://scripts/ui/table_theme.gd")
const ChipStack = preload("res://scripts/ui/chip_stack.gd")
const PLATE_SIZE := Vector2(158, 48)
const OPPONENT_CARD_SIZE := Vector2(46, 62)
const PLAYER_CARD_SIZE := Vector2(68, 91)

var cards: Array[TextureRect] = []
var open_button: Button
var wager := HBoxContainer.new()
var _plate := PanelContainer.new()
var _name: Label
var _chips: Label
var _starter: Label
var _caption: Label
var _wager_chips := ChipStack.new()
var _wager_label: Label
var _states: Dictionary = {}

func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	for index in range(2):
		var card := TextureRect.new()
		card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card.mouse_filter = MOUSE_FILTER_PASS
		add_child(card)
		cards.append(card)

	_plate.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_plate)
	var row := HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE
	_plate.add_child(row)
	_name = Styles.label("", 17)
	_name.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(_name)
	_chips = Styles.label("", 16, Styles.GOLD)
	row.add_child(_chips)

	_caption = Styles.label("", 14)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.add_theme_stylebox_override("normal", Styles.box(Color("#111716"), Color("#456055"), 10))
	add_child(_caption)

	_starter = Styles.label("先", 13, Styles.GOLD_INK)
	_starter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_starter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_starter.mouse_filter = MOUSE_FILTER_PASS
	_starter.tooltip_text = "本局先手"
	_starter.add_theme_stylebox_override("normal", Styles.box(Styles.GOLD, Color("#fff2bf"), 14))
	add_child(_starter)

	wager.mouse_filter = MOUSE_FILTER_IGNORE
	wager.alignment = BoxContainer.ALIGNMENT_CENTER
	wager.add_theme_constant_override("separation", 4)
	add_child(wager)
	_wager_chips.custom_minimum_size = Vector2(49, 27)
	wager.add_child(_wager_chips)
	_wager_label = Styles.label("", 14)
	wager.add_child(_wager_label)

	open_button = Styles.button("看牌", "Gold", 44)
	open_button.tooltip_text = "翻开自己的手牌"
	add_child(open_button)
	for key in ["normal", "human", "active", "winner", "out"]:
		_states[key] = _plate_style(key)

func layout_at(anchor: Vector2, wager_position: Vector2, human: bool) -> void:
	position = (anchor - PLATE_SIZE / 2).round()
	_plate.size = PLATE_SIZE
	var card_size := PLAYER_CARD_SIZE if human else OPPONENT_CARD_SIZE
	var gap := 6.0
	var left := (PLATE_SIZE.x - card_size.x * 2.0 - gap) / 2.0
	for index in range(cards.size()):
		cards[index].position = Vector2(left + index * (card_size.x + gap), -card_size.y + 3)
		cards[index].size = card_size
	_caption.position = Vector2(-12, PLATE_SIZE.y + 3)
	_caption.size = Vector2(PLATE_SIZE.x + 24, 26)
	_starter.position = Vector2(-16, -6)
	_starter.size = Vector2(28, 28)
	wager.position = (wager_position - position - Vector2(61, 15)).round()
	wager.size = Vector2(122, 30)
	open_button.position = Vector2(27, -55)
	open_button.size = Vector2(104, 44)

func render(seat: Dictionary, is_human: bool, active: bool, starter: bool, winner: bool, masked: bool, playing: bool, textures: Array[Texture2D]) -> void:
	var folded := bool(seat["folded"])
	var participating := bool(seat["participating"])
	var dimmed := folded or not participating
	_name.text = str(seat["name"])
	_chips.text = "%d 底" % int(seat["chips"])
	_name.modulate.a = 0.68 if dimmed else 1.0
	_chips.modulate.a = _name.modulate.a
	_starter.visible = starter and participating

	var style := "human" if is_human else "normal"
	if dimmed:
		style = "out"
	elif winner:
		style = "winner"
	elif active:
		style = "active"
	_plate.add_theme_stylebox_override("panel", _states[style])
	_caption.text = _caption_text(seat, is_human, active, winner, masked)
	_caption.visible = not _caption.text.is_empty()
	_caption.tooltip_text = _caption.text
	_caption.add_theme_color_override("font_color", Styles.GOLD if active or winner else Styles.MUTED)
	var last_bet := int(seat["last_bet"])
	_wager_chips.amount = last_bet
	_wager_label.text = "%d 底" % last_bet
	wager.visible = playing and last_bet > 0 and not dimmed

	var visible_cards: Array = seat["cards"]
	for index in range(cards.size()):
		var card := cards[index]
		card.visible = index < visible_cards.size() and (not folded or is_human)
		card.texture = textures[index] if index < textures.size() else null
		card.modulate.a = 0.50 if folded else 1.0
		card.tooltip_text = ""
		if card.visible:
			card.tooltip_text = "牌背" if masked or bool(visible_cards[index].get("hidden", false)) else str(visible_cards[index]["label"])
		card.accessibility_name = card.tooltip_text
	open_button.visible = is_human and masked and not visible_cards.is_empty()

func _caption_text(seat: Dictionary, is_human: bool, active: bool, winner: bool, masked: bool) -> String:
	var status := str(seat["status"])
	if not bool(seat["participating"]):
		return "已淘汰"
	if bool(seat["folded"]):
		return "已弃牌"
	if status == "捡天水成功":
		return "捡天水 · %s" % seat["hand_name"]
	if winner:
		return "胜出 · %s" % seat["hand_name"] if not str(seat["hand_name"]).is_empty() else "胜出"
	if active:
		if is_human and not masked:
			return str(seat["hand_name"])
		return "轮到你" if is_human else "思考中"
	if status == "等待行动":
		return str(seat["hand_name"]) if is_human and not masked else ""
	if status.begins_with("亮牌："):
		return str(seat["hand_name"])
	return status

func _plate_style(key: String) -> StyleBoxFlat:
	var fill := Color("#1b2220")
	var border := Color("#48564e")
	match key:
		"human":
			border = Color("#779787")
		"active":
			fill = Color("#382b1a")
			border = Styles.GOLD
		"winner":
			fill = Color("#264635")
			border = Styles.GOLD
		"out":
			fill = Color("#171c1a")
			border = Color("#3e4842")
	var style := Styles.box(fill, border, 11, 2 if key in ["winner", "active"] else 1)
	style.shadow_color = Color(0, 0, 0, 0.44)
	style.shadow_size = 7
	style.shadow_offset = Vector2(0, 4)
	return style
