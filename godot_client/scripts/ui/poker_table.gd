extends Control

const Styles = preload("res://scripts/ui/table_theme.gd")
const SeatView = preload("res://scripts/ui/table_seat.gd")
const ChipStack = preload("res://scripts/ui/chip_stack.gd")
const CardBack = preload("res://assets/cards/card_back.png")
const Felt = preload("res://scripts/ui/felt.gdshader")
const SUITS := {"H": "h", "D": "d", "S": "s", "C": "c"}
const FACE_RANKS := {"J": 11, "Q": 12}
const SEAT_POINTS := {
	2: [Vector2(0.5, 0.87), Vector2(0.5, 0.19)],
	3: [Vector2(0.5, 0.87), Vector2(0.25, 0.23), Vector2(0.75, 0.23)],
	4: [Vector2(0.5, 0.87), Vector2(0.12, 0.54), Vector2(0.5, 0.19), Vector2(0.88, 0.54)],
	5: [Vector2(0.5, 0.87), Vector2(0.12, 0.62), Vector2(0.29, 0.19), Vector2(0.71, 0.19), Vector2(0.88, 0.62)],
	6: [Vector2(0.5, 0.87), Vector2(0.12, 0.64), Vector2(0.22, 0.23), Vector2(0.5, 0.18), Vector2(0.78, 0.23), Vector2(0.88, 0.64)]
}

signal hand_opened

var views: Array[Control] = []
var pot_amount: Label
var pot_center := VBoxContainer.new()
var pot_chips := ChipStack.new()
var result_panel := Panel.new()
var result_title: Label
var result_detail: Label
var result_meta: Label
var _felt := ColorRect.new()
var _deck: TextureRect
var _effects := Control.new()
var _texture_cache: Dictionary = {}
var _human_index := 0
var _flips: Array[Tween] = []

func _ready() -> void:
	size_flags_vertical = SIZE_EXPAND_FILL
	mouse_filter = MOUSE_FILTER_IGNORE
	_felt.mouse_filter = MOUSE_FILTER_IGNORE
	var felt_material := ShaderMaterial.new()
	felt_material.shader = Felt
	_felt.material = felt_material
	add_child(_felt)

	_deck = _card_sprite(CardBack)
	_deck.rotation = -0.14
	add_child(_deck)

	pot_center.mouse_filter = MOUSE_FILTER_IGNORE
	pot_center.add_theme_constant_override("separation", 2)
	pot_chips.custom_minimum_size = Vector2(88, 50)
	pot_center.add_child(pot_chips)
	pot_amount = Styles.label("", 21)
	pot_amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pot_center.add_child(pot_amount)
	add_child(pot_center)

	result_panel.mouse_filter = MOUSE_FILTER_IGNORE
	result_panel.add_theme_stylebox_override("panel", Styles.box(Color("#11251d"), Color("#6f7654"), 12))
	var column := VBoxContainer.new()
	column.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 3)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	column.offset_left = 12
	column.offset_right = -12
	result_panel.add_child(column)
	result_title = Styles.label("", 26, Styles.GOLD)
	result_detail = Styles.label("", 16)
	result_meta = Styles.label("", 14, Styles.MUTED)
	for label in [result_title, result_detail, result_meta]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(label)
	add_child(result_panel)

	_effects.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_effects)
	resized.connect(_layout)
	_layout()

func render(state: Dictionary, masked: bool) -> void:
	var seats: Array = state["seats"]
	var phase := str(state["phase"])
	_human_index = int(state["human_seat_index"])
	if views.size() != seats.size():
		_build_seats(seats.size())

	var pot := int(state["pot"])
	pot_center.visible = phase == "playing"
	pot_amount.text = "%d 底" % pot
	pot_amount.accessibility_name = "桌上筹码 %d 底" % pot
	pot_chips.amount = pot
	_deck.visible = phase == "playing"
	var active := int(state["active_seat_index"])
	var settlement: Dictionary = state["settlement"]
	var winners: Array = settlement.get("seats", [])
	for index in range(seats.size()):
		var seat: Dictionary = seats[index]
		var conceal := index == _human_index and masked and phase == "playing"
		var textures: Array[Texture2D] = []
		for card in seat["cards"]:
			textures.append(CardBack if conceal else texture_for_card(card))
		views[index].render(
			seat, index == _human_index, index == active,
			index == int(state["starter_seat_index"]),
			index in winners and str(settlement.get("kind", "")) in ["showdown", "uncontested", "natural_win"],
			conceal, phase == "playing", textures
		)

	result_panel.visible = phase in ["round_end", "game_over"]
	if result_panel.visible:
		_render_result(state, settlement, seats)
	_layout()

func _render_result(state: Dictionary, settlement: Dictionary, seats: Array) -> void:
	var phase := str(state["phase"])
	var payout := int(settlement.get("payout", 0))
	var names: PackedStringArray = []
	for index in settlement.get("seats", []):
		names.append(str(seats[index]["name"]))
	var names_text := "、".join(names)
	match str(settlement.get("kind", "")):
		"tie":
			result_title.text = "平局"
			result_detail.text = "%s 并列最强" % names_text
		"natural_miss":
			result_title.text = "捡天水失败"
			result_detail.text = "%s · %s" % [names_text, seats[settlement["seats"][0]]["hand_name"]]
		"natural_win":
			result_title.text = "捡天水成功"
			result_detail.text = "%s 收走全部 %d 底" % [names_text, payout]
		"showdown", "uncontested":
			result_title.text = "%s赢得本局" % names_text
			result_detail.text = "收取 %d 底" % payout
			if settlement["kind"] == "showdown":
				result_detail.text = "%s · %s" % [seats[settlement["seats"][0]]["hand_name"], result_detail.text]
			else:
				result_detail.text = "对手全弃 · %s" % result_detail.text
		_:
			result_title.text = "本局结算"
			result_detail.text = str(state["round_message"])
	var carry := int(state["pot"])
	if phase == "game_over":
		var round_title := result_title.text
		var round_detail := result_detail.text
		result_title.text = "挑战获胜" if state["match_result"] == "victory" else "挑战失败"
		result_detail.text = str(state["match_message"])
		result_meta.text = "%s · %s" % [round_title, round_detail] if not round_detail.is_empty() else round_title
	else:
		result_meta.text = "留到下一局  %d 底" % carry

func _build_seats(count: int) -> void:
	for view in views:
		remove_child(view)
		view.queue_free()
	views.clear()
	for index in range(count):
		var view := SeatView.new()
		view.open_button.pressed.connect(func() -> void: hand_opened.emit())
		add_child(view)
		views.append(view)
	move_child(_effects, -1)

func _layout() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var center_x := size.x * 0.5
	_felt.position = (size * Vector2(0.055, 0.13)).round()
	_felt.size = (size * Vector2(0.89, 0.79)).round()
	_felt.material.set_shader_parameter("surface_size", _felt.size)

	_deck.position = (Vector2(center_x - minf(size.x * 0.20, 240.0), size.y * 0.43) - Vector2(20, 27)).round()
	_deck.size = Vector2(40, 54)
	pot_center.position = Vector2(center_x - 92, size.y * 0.34).round()
	pot_center.size = Vector2(184, 100)

	var result_width := minf(428, size.x * 0.38)
	result_panel.position = Vector2(center_x - result_width * 0.5, size.y * 0.35).round()
	result_panel.size = Vector2(result_width, 113)

	if views.size() < 2:
		return
	var points: Array = SEAT_POINTS[views.size()]
	for index in range(views.size()):
		var order := posmod(index - _human_index, views.size())
		var point: Vector2 = points[order]
		var anchor := point * size
		var toward_middle := ((Vector2(0.5, 0.50) - point) * size).normalized()
		var wager_position := anchor + toward_middle * 128.0
		if order == 0:
			wager_position = anchor + Vector2(142, -65)
		elif is_equal_approx(point.x, 0.5):
			wager_position = anchor + Vector2(130, 20)
		elif point.x > 0.8:
			wager_position += Vector2(-18, 0)
		views[index].layout_at(anchor, wager_position, order == 0)

func texture_for_card(card: Dictionary) -> Texture2D:
	if bool(card.get("hidden", false)):
		return CardBack
	var rank := str(card.get("rank", ""))
	var path := "res://assets/cards/card_joker.png"
	if rank != "JOKER":
		var suit := str(SUITS.get(str(card.get("suit", "")), ""))
		path = "res://assets/cards/card_%s_%02d.png" % [suit, int(FACE_RANKS.get(rank, rank.to_int()))]
	if not _texture_cache.has(path):
		_texture_cache[path] = load(path)
	return _texture_cache[path] if _texture_cache[path] != null else CardBack

func start_deal(starter: int) -> void:
	clear_effects()
	var order := 0
	for card_index in range(2):
		for offset in range(views.size()):
			var seat_index := posmod(starter + offset, views.size())
			var view := views[seat_index]
			var card: TextureRect = view.cards[card_index]
			if not card.visible:
				continue
			card.texture = CardBack
			card.hide()
			var flight := _card_sprite(CardBack)
			_effects.add_child(flight)
			flight.size = Vector2(32, 43)
			flight.position = _deck.position
			flight.hide()
			var tween := flight.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.tween_interval(order * 0.018)
			tween.tween_callback(flight.show)
			tween.tween_property(flight, "position", card.global_position - global_position, 0.20)
			tween.parallel().tween_property(flight, "size", card.size, 0.20)
			tween.tween_callback(card.show)
			tween.tween_callback(flight.queue_free)
			order += 1
	for view in views:
		view.open_button.hide()

func clear_effects() -> void:
	for effect in _effects.get_children():
		effect.free()
	for flip in _flips:
		flip.kill()
	_flips.clear()
	for view in views:
		for card in view.cards:
			card.scale = Vector2.ONE

func animate_reveal(settlement: Dictionary) -> void:
	var kind := str(settlement.get("kind", ""))
	if kind not in ["showdown", "tie", "natural_win", "natural_miss"]:
		return
	for index in range(views.size()):
		if index != _human_index:
			_flip_cards(views[index].cards)

func animate_open_hand() -> void:
	_flip_cards(views[_human_index].cards)

func _flip_cards(cards: Array[TextureRect]) -> void:
	for card in cards:
		if not card.visible or card.texture == CardBack:
			continue
		var face := card.texture
		card.texture = CardBack
		card.pivot_offset = card.size / 2
		var tween := card.create_tween().set_trans(Tween.TRANS_SINE)
		tween.tween_property(card, "scale:x", 0.06, 0.10)
		tween.tween_callback(card.set_texture.bind(face))
		tween.tween_property(card, "scale:x", 1.0, 0.13)
		_flips.append(tween)
		tween.finished.connect(func() -> void: _flips.erase(tween))

func animate_action(event: Dictionary, settlement: Dictionary) -> void:
	var index := int(event["actor_seat"])
	var kind := str(event["action"])
	var view := views[index]
	if kind == "fold":
		if index != _human_index:
			var cards: Array = view.cards
			for card in cards:
				var leaving := _card_sprite(CardBack)
				_effects.add_child(leaving)
				leaving.position = card.global_position - global_position
				leaving.size = card.size
				var tween := leaving.create_tween().set_parallel(true)
				tween.tween_property(leaving, "position", _deck.position, 0.22)
				tween.tween_property(leaving, "modulate:a", 0.0, 0.22)
				tween.chain().tween_callback(leaving.queue_free)
	elif int(event["pot_after"]) > int(event["pot_before"]):
		_fly_chips(view.wager.get_global_rect().get_center() - global_position, _pot_origin(), int(event["pot_after"]) - int(event["pot_before"]))
	var payout := int(settlement.get("payout", 0))
	if payout > 0:
		var winner := int(settlement["seats"][0])
		var destination := views[winner].position + Vector2(79, 24)
		_fly_chips(_pot_origin(), destination, payout, 0.17)

func _pot_origin() -> Vector2:
	return pot_center.position + Vector2(92, 29)

func _fly_chips(from: Vector2, to: Vector2, amount: int, delay: float = 0.0) -> void:
	var chips := ChipStack.new()
	chips.amount = amount
	chips.size = Vector2(72, 40)
	chips.position = from - chips.size / 2
	_effects.add_child(chips)
	chips.visible = delay == 0
	var tween := chips.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if delay > 0:
		tween.tween_interval(delay)
		tween.tween_callback(chips.show)
	tween.tween_property(chips, "position", to - chips.size / 2, 0.26)
	tween.parallel().tween_property(chips, "modulate:a", 0.20, 0.26)
	tween.tween_callback(chips.queue_free)

func _card_sprite(texture: Texture2D) -> TextureRect:
	var sprite := TextureRect.new()
	sprite.texture = texture
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.mouse_filter = MOUSE_FILTER_IGNORE
	return sprite
