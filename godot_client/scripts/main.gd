extends Control

const LocalGameScript = preload("res://scripts/game/local_game.gd")

const CARD_BACK = preload("res://assets/cards/card_back.png")
const SFX_SHUFFLE = preload("res://assets/audio/card_shuffle.ogg")
const SFX_CARD = preload("res://assets/audio/card_slide.ogg")
const SFX_FOLD = preload("res://assets/audio/card_place.ogg")
const SFX_CHIP = preload("res://assets/audio/chip_lay.ogg")
const SFX_SETTLE = preload("res://assets/audio/chips_collide.ogg")

const PANEL_SIZE := Vector2(220, 174)
const CARD_SIZE := Vector2(54, 72)

var game: RefCounted
var seat_views: Array = []
var _card_texture_cache: Dictionary = {}
var _previous_pot := 0
var _previous_round := 0
var _previous_phase := "setup"
var _sound_enabled := true
var _audio_player: AudioStreamPlayer

@onready var header: PanelContainer = $RootMargin/RootVBox/Header
@onready var table_wrap: PanelContainer = $RootMargin/RootVBox/Content/TableWrap
@onready var table_surface: PanelContainer = $RootMargin/RootVBox/Content/TableWrap/TableArea/TableSurface
@onready var seat_layer: Control = $RootMargin/RootVBox/Content/TableWrap/TableArea/SeatLayer
@onready var sidebar: PanelContainer = $RootMargin/RootVBox/Content/Sidebar

@onready var round_value: Label = $RootMargin/RootVBox/Header/HeaderMargin/HeaderRow/RoundBox/Value
@onready var pot_value: Label = $RootMargin/RootVBox/Header/HeaderMargin/HeaderRow/PotBox/Value
@onready var phase_value: Label = $RootMargin/RootVBox/Header/HeaderMargin/HeaderRow/PhaseBox/Value
@onready var sound_button: Button = $RootMargin/RootVBox/Header/HeaderMargin/HeaderRow/SoundButton
@onready var table_pot: Label = $RootMargin/RootVBox/Content/TableWrap/TableArea/TableSurface/CenterVBox/TablePot
@onready var round_message: Label = $RootMargin/RootVBox/Content/TableWrap/TableArea/TableSurface/CenterVBox/RoundMessage

@onready var setup_panel: VBoxContainer = $RootMargin/RootVBox/Content/Sidebar/SideMargin/SideVBox/SetupPanel
@onready var bot_count_input: SpinBox = $RootMargin/RootVBox/Content/Sidebar/SideMargin/SideVBox/SetupPanel/BotRow/BotCount
@onready var start_button: Button = $RootMargin/RootVBox/Content/Sidebar/SideMargin/SideVBox/SetupPanel/StartButton
@onready var action_help: Label = $RootMargin/RootVBox/Content/Sidebar/SideMargin/SideVBox/ActionHelp
@onready var bet_amount_input: SpinBox = $RootMargin/RootVBox/Content/Sidebar/SideMargin/SideVBox/BetAmount
@onready var first_action_row: HBoxContainer = $RootMargin/RootVBox/Content/Sidebar/SideMargin/SideVBox/FirstActionRow
@onready var bet_button: Button = $RootMargin/RootVBox/Content/Sidebar/SideMargin/SideVBox/FirstActionRow/BetButton
@onready var eat_button: Button = $RootMargin/RootVBox/Content/Sidebar/SideMargin/SideVBox/FirstActionRow/EatButton
@onready var fold_button: Button = $RootMargin/RootVBox/Content/Sidebar/SideMargin/SideVBox/FirstActionRow/FoldButton
@onready var follow_action_row: HBoxContainer = $RootMargin/RootVBox/Content/Sidebar/SideMargin/SideVBox/FollowActionRow
@onready var check_button: Button = $RootMargin/RootVBox/Content/Sidebar/SideMargin/SideVBox/FollowActionRow/CheckButton
@onready var dai_button: Button = $RootMargin/RootVBox/Content/Sidebar/SideMargin/SideVBox/FollowActionRow/DaiButton
@onready var next_round_button: Button = $RootMargin/RootVBox/Content/Sidebar/SideMargin/SideVBox/NextRoundButton
@onready var restart_button: Button = $RootMargin/RootVBox/Content/Sidebar/SideMargin/SideVBox/RestartButton
@onready var log_text: RichTextLabel = $RootMargin/RootVBox/Content/Sidebar/SideMargin/SideVBox/LogText

func _ready() -> void:
	game = LocalGameScript.new()
	_audio_player = AudioStreamPlayer.new()
	_audio_player.volume_db = -7.0
	add_child(_audio_player)

	start_button.pressed.connect(_on_start_pressed)
	bet_button.pressed.connect(_on_bet_pressed)
	eat_button.pressed.connect(_on_eat_pressed)
	fold_button.pressed.connect(_on_fold_pressed)
	check_button.pressed.connect(_on_check_pressed)
	dai_button.pressed.connect(_on_dai_pressed)
	next_round_button.pressed.connect(_on_next_round_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	sound_button.pressed.connect(_on_sound_pressed)
	bet_amount_input.value_changed.connect(_on_bet_amount_changed)
	seat_layer.resized.connect(_layout_seats)

	_apply_styles()
	_render()

func _on_start_pressed() -> void:
	game.start_match(int(bot_count_input.value))
	_render()

func _on_bet_pressed() -> void:
	if game.player_action("bet", int(bet_amount_input.value)):
		_render()

func _on_eat_pressed() -> void:
	var state: Dictionary = game.get_state()
	if game.player_action("bet", int(state["pot"])):
		_render()

func _on_fold_pressed() -> void:
	if game.player_action("fold"):
		_play_sfx(SFX_FOLD)
		_render()

func _on_check_pressed() -> void:
	if game.player_action("check"):
		_play_sfx(SFX_CARD)
		_render()

func _on_dai_pressed() -> void:
	if game.player_action("dai"):
		_render()

func _on_next_round_pressed() -> void:
	if game.start_next_round():
		_render()

func _on_restart_pressed() -> void:
	game.restart_match()
	_render()

func _on_sound_pressed() -> void:
	_sound_enabled = not _sound_enabled
	sound_button.text = "声音  开" if _sound_enabled else "声音  关"
	if not _sound_enabled:
		_audio_player.stop()
	else:
		_play_sfx(SFX_CARD)

func _on_bet_amount_changed(value: float) -> void:
	bet_button.text = "下注  %d" % int(value)

func _render() -> void:
	var state: Dictionary = game.get_state()
	var current_phase := str(state["phase"])
	var actions: Array = state["available_actions"]
	var current_pot := int(state["pot"])
	var current_round := int(state["round_index"])

	round_value.text = "—" if current_round == 0 else str(current_round)
	pot_value.text = "%d 底" % current_pot
	table_pot.text = str(current_pot)
	phase_value.text = _phase_text(current_phase)

	setup_panel.visible = current_phase == "setup"
	restart_button.visible = current_phase != "setup"
	next_round_button.visible = current_phase == "round_end"
	bet_amount_input.visible = actions.has("bet")
	first_action_row.visible = actions.has("bet") or actions.has("fold")
	follow_action_row.visible = actions.has("check") or actions.has("dai")
	bet_button.visible = actions.has("bet")
	fold_button.visible = actions.has("fold")
	check_button.visible = actions.has("check")
	dai_button.visible = actions.has("dai")

	if actions.has("bet"):
		var maximum := int(state["max_bet"])
		bet_amount_input.max_value = maximum
		bet_amount_input.value = clampi(int(bet_amount_input.value), 1, maximum)
		eat_button.visible = maximum >= current_pot
		eat_button.text = "吃满  %d" % current_pot
		bet_button.text = "下注  %d" % int(bet_amount_input.value)
	else:
		eat_button.visible = false
	if actions.has("dai"):
		dai_button.text = "带满  %d" % int(state["dai_amount"])

	action_help.text = _action_help(state)
	round_message.text = _center_message(state)
	_render_log(state["action_log"])
	_render_seats(state)
	_render_feedback(current_pot, current_round, current_phase)

	_previous_pot = current_pot
	_previous_round = current_round
	_previous_phase = current_phase

func _render_feedback(current_pot: int, current_round: int, current_phase: String) -> void:
	if current_round > _previous_round:
		_play_sfx(SFX_SHUFFLE)
		call_deferred("_animate_deal")
	elif current_pot > _previous_pot:
		_play_sfx(SFX_CHIP)
		_animate_pot()
	elif current_phase == "round_end" and _previous_phase != "round_end":
		_play_sfx(SFX_SETTLE)
		_animate_pot()

func _render_seats(state: Dictionary) -> void:
	var seats: Array = state["seats"]
	if seat_views.size() != seats.size():
		_rebuild_seat_views(seats.size())

	for index in range(seats.size()):
		var seat: Dictionary = seats[index]
		var view: Dictionary = seat_views[index]
		var is_active := index == int(state["active_seat_index"])
		var is_human := index == int(state["human_seat_index"])

		view["name"].text = str(seat["name"])
		view["avatar"].text = "你" if is_human else str(seat["name"]).left(1)
		view["chips"].text = "●  %d 底" % int(seat["chips"])
		view["hand"].text = str(seat["hand_name"])
		view["status"].text = "▶ %s" % str(seat["status"]) if is_active else str(seat["status"])
		view["status"].add_theme_color_override(
			"font_color",
			Color("#f7d56b") if is_active else Color("#9eabad")
		)

		var card_views: Array = view["cards"]
		var visible_cards: Array = seat["cards"]
		for card_index in range(card_views.size()):
			var card_view: TextureRect = card_views[card_index]
			card_view.visible = card_index < visible_cards.size()
			if card_view.visible:
				var card: Dictionary = visible_cards[card_index]
				card_view.texture = _texture_for_card(card)
				card_view.tooltip_text = _card_tooltip(card)
				card_view.modulate = Color(1, 1, 1, 0.42) if bool(seat["folded"]) else Color.WHITE

		var panel: PanelContainer = view["panel"]
		if is_active:
			panel.add_theme_stylebox_override("panel", _seat_style(Color("#42371e"), Color("#f3cc62"), 3))
		elif not bool(seat["participating"]):
			panel.add_theme_stylebox_override("panel", _seat_style(Color("#151b1e"), Color("#2b3539"), 1))
		elif bool(seat["folded"]):
			panel.add_theme_stylebox_override("panel", _seat_style(Color("#202629"), Color("#3b464a"), 1))
		elif is_human:
			panel.add_theme_stylebox_override("panel", _seat_style(Color("#123a35"), Color("#48bba6"), 2))
		else:
			panel.add_theme_stylebox_override("panel", _seat_style(Color("#182429"), Color("#465a61"), 1))
	_layout_seats()

func _rebuild_seat_views(count: int) -> void:
	for child in seat_layer.get_children():
		child.queue_free()
	seat_views = []

	for index in range(count):
		var panel := PanelContainer.new()
		panel.custom_minimum_size = PANEL_SIZE
		panel.size = PANEL_SIZE
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		seat_layer.add_child(panel)

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_theme_constant_override("margin_top", 10)
		margin.add_theme_constant_override("margin_right", 12)
		margin.add_theme_constant_override("margin_bottom", 9)
		panel.add_child(margin)

		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 4)
		margin.add_child(column)

		var header_row := HBoxContainer.new()
		header_row.add_theme_constant_override("separation", 8)
		column.add_child(header_row)

		var avatar_label := Label.new()
		avatar_label.custom_minimum_size = Vector2(34, 34)
		avatar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		avatar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		avatar_label.add_theme_font_size_override("font_size", 15)
		avatar_label.add_theme_color_override("font_color", Color("#102223"))
		avatar_label.add_theme_stylebox_override("normal", _avatar_style(index))
		header_row.add_child(avatar_label)

		var identity := VBoxContainer.new()
		identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		identity.add_theme_constant_override("separation", 0)
		header_row.add_child(identity)

		var name_label := Label.new()
		name_label.add_theme_font_size_override("font_size", 17)
		name_label.add_theme_color_override("font_color", Color("#f3f4ec"))
		identity.add_child(name_label)

		var chips_label := Label.new()
		chips_label.add_theme_font_size_override("font_size", 13)
		chips_label.add_theme_color_override("font_color", Color("#f2c85b"))
		identity.add_child(chips_label)

		var cards_row := HBoxContainer.new()
		cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
		cards_row.add_theme_constant_override("separation", 6)
		column.add_child(cards_row)

		var card_views: Array = []
		for card_index in range(2):
			var card_view := TextureRect.new()
			card_view.custom_minimum_size = CARD_SIZE
			card_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			card_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			card_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			card_view.mouse_filter = Control.MOUSE_FILTER_PASS
			cards_row.add_child(card_view)
			card_views.append(card_view)

		var footer_row := HBoxContainer.new()
		column.add_child(footer_row)

		var hand_label := Label.new()
		hand_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hand_label.add_theme_font_size_override("font_size", 14)
		hand_label.add_theme_color_override("font_color", Color("#70d5c0"))
		footer_row.add_child(hand_label)

		var status_label := Label.new()
		status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		status_label.add_theme_font_size_override("font_size", 13)
		status_label.add_theme_color_override("font_color", Color("#9eabad"))
		status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		footer_row.add_child(status_label)

		seat_views.append({
			"panel": panel,
			"avatar": avatar_label,
			"name": name_label,
			"chips": chips_label,
			"cards": card_views,
			"hand": hand_label,
			"status": status_label
		})

	call_deferred("_layout_seats")

func _layout_seats() -> void:
	if seat_views.is_empty() or seat_layer.size.x <= 0.0:
		return
	var center := seat_layer.size / 2.0
	var radius_x := maxf(0.0, (seat_layer.size.x - PANEL_SIZE.x) / 2.0 - 12.0)
	var radius_y := maxf(0.0, (seat_layer.size.y - PANEL_SIZE.y) / 2.0 - 6.0)
	var count := seat_views.size()

	for index in range(count):
		var angle := PI / 2.0 + TAU * float(index) / float(count)
		var position := center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y) - PANEL_SIZE / 2.0
		var panel: PanelContainer = seat_views[index]["panel"]
		panel.position = position.round()
		panel.size = PANEL_SIZE

func _texture_for_card(card: Dictionary) -> Texture2D:
	if bool(card.get("hidden", false)):
		return CARD_BACK
	var rank := str(card.get("rank", ""))
	if rank == "JOKER":
		return load("res://assets/cards/card_joker.png")
	var suit_code: String = str({"H": "h", "D": "d", "S": "s", "C": "c"}.get(str(card.get("suit", "")), ""))
	var rank_number := 0
	if rank == "J":
		rank_number = 11
	elif rank == "Q":
		rank_number = 12
	elif rank.is_valid_int():
		rank_number = int(rank)
	var path := "res://assets/cards/card_%s_%02d.png" % [suit_code, rank_number]
	if not _card_texture_cache.has(path):
		_card_texture_cache[path] = load(path)
	return _card_texture_cache[path] if _card_texture_cache[path] != null else CARD_BACK

func _card_tooltip(card: Dictionary) -> String:
	if bool(card.get("hidden", false)):
		return "未公开手牌"
	return str(card.get("label", "手牌"))

func _render_log(lines: Array) -> void:
	var output: PackedStringArray = []
	var first_index := maxi(0, lines.size() - 12)
	for index in range(first_index, lines.size()):
		var color := "#f1d477" if index == lines.size() - 1 else "#9eabad"
		output.append("[color=%s]›[/color] %s" % [color, str(lines[index])])
	log_text.text = "\n".join(output)
	log_text.scroll_to_line(maxi(0, output.size() - 1))

func _action_help(state: Dictionary) -> String:
	var phase := str(state["phase"])
	var actions: Array = state["available_actions"]
	if phase == "setup":
		return "牌桌已备好。选定对手后立即发牌。"
	if phase == "round_end":
		return "本局已结算。牌面仍会保留，确认后再开下一局。"
	if phase == "game_over":
		return str(state["match_message"])
	if actions.has("bet"):
		return "首次行动只能下注或弃牌，可投入 1～%d 底。" % int(state["max_bet"])
	if actions.has("check"):
		if actions.has("dai"):
			return "你已下注过：过牌保留比牌资格，或带满当前底池。"
		return "当前筹码不足以带满，只能过牌并保留比牌资格。"
	return "对手正在思考，请留意牌桌动态。"

func _center_message(state: Dictionary) -> String:
	var phase := str(state["phase"])
	if phase == "setup":
		return "等你入座\n选择右侧配置，开一桌"
	if phase == "game_over":
		return str(state["match_message"])
	if not str(state["round_message"]).is_empty():
		return str(state["round_message"])
	var active_index := int(state["active_seat_index"])
	if active_index >= 0:
		var active_name := str(state["seats"][active_index]["name"])
		return "轮到你 · 请选择行动" if active_index == int(state["human_seat_index"]) else "%s 正在行动" % active_name
	return "等待行动"

func _phase_text(phase: String) -> String:
	match phase:
		"setup":
			return "等待入座"
		"playing":
			return "牌局进行中"
		"round_end":
			return "本局结算"
		"game_over":
			return "挑战结束"
	return phase

func _animate_deal() -> void:
	for seat_index in range(seat_views.size()):
		var card_views: Array = seat_views[seat_index]["cards"]
		for card_index in range(card_views.size()):
			var card: TextureRect = card_views[card_index]
			if not card.visible:
				continue
			card.pivot_offset = card.size / 2.0
			card.scale = Vector2(0.55, 0.55)
			card.modulate.a = 0.0
			var tween := create_tween()
			tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_interval(float(seat_index * 2 + card_index) * 0.035)
			tween.set_parallel(true)
			tween.tween_property(card, "scale", Vector2.ONE, 0.24)
			tween.tween_property(card, "modulate:a", 1.0, 0.15)

func _animate_pot() -> void:
	table_pot.pivot_offset = table_pot.size / 2.0
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	table_pot.scale = Vector2(1.28, 1.28)
	table_pot.modulate = Color("#fff2a8")
	tween.set_parallel(true)
	tween.tween_property(table_pot, "scale", Vector2.ONE, 0.28)
	tween.tween_property(table_pot, "modulate", Color.WHITE, 0.28)

func _play_sfx(stream: AudioStream) -> void:
	if not _sound_enabled or _audio_player == null:
		return
	_audio_player.stream = stream
	_audio_player.play()

func _apply_styles() -> void:
	header.add_theme_stylebox_override("panel", _panel_style(Color("#111c20"), Color("#26373d"), 12))
	table_wrap.add_theme_stylebox_override("panel", _panel_style(Color("#0b1215"), Color("#203036"), 12))
	sidebar.add_theme_stylebox_override("panel", _panel_style(Color("#101b1f"), Color("#2a3b41"), 12))

	var table_style := StyleBoxFlat.new()
	table_style.bg_color = Color("#14513e")
	table_style.border_color = Color("#8a5e32")
	table_style.set_border_width_all(12)
	table_style.set_corner_radius_all(132)
	table_style.shadow_color = Color(0, 0, 0, 0.5)
	table_style.shadow_size = 20
	table_style.shadow_offset = Vector2(0, 8)
	table_surface.add_theme_stylebox_override("panel", table_style)

	_style_button(start_button, Color("#e0ae35"), Color("#17130a"))
	_style_button(bet_button, Color("#d9a82f"), Color("#17130a"))
	_style_button(eat_button, Color("#f0ca5b"), Color("#17130a"))
	_style_button(fold_button, Color("#9e3f46"), Color.WHITE)
	_style_button(check_button, Color("#3b5663"), Color.WHITE)
	_style_button(dai_button, Color("#2e816b"), Color.WHITE)
	_style_button(next_round_button, Color("#2e816b"), Color.WHITE)
	_style_button(restart_button, Color("#303e43"), Color("#d9e1e2"))
	_style_button(sound_button, Color("#24343a"), Color("#d9e1e2"))

	for button in [start_button, bet_button, eat_button, fold_button, check_button, dai_button, next_round_button]:
		button.add_theme_font_size_override("font_size", 16)

func _style_button(button: Button, background: Color, foreground: Color) -> void:
	var normal := _panel_style(background, background.lightened(0.12), 8)
	var hover := _panel_style(background.lightened(0.08), background.lightened(0.25), 8)
	var pressed := _panel_style(background.darkened(0.09), background, 8)
	var focus := _panel_style(background.lightened(0.04), Color("#f5db81"), 8)
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_color", foreground)
	button.add_theme_color_override("font_hover_color", foreground)
	button.add_theme_color_override("font_pressed_color", foreground)

func _panel_style(background: Color, border: Color, radius: int = 7) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style

func _seat_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := _panel_style(background, border, 10)
	style.set_border_width_all(width)
	style.shadow_color = Color(0, 0, 0, 0.38)
	style.shadow_size = 9
	style.shadow_offset = Vector2(0, 4)
	return style

func _avatar_style(index: int) -> StyleBoxFlat:
	var colors := [Color("#69c9b5"), Color("#e9bd58"), Color("#db8270"), Color("#79a8d8"), Color("#aa8bd1"), Color("#83b66f")]
	var color: Color = colors[index % colors.size()]
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(17)
	return style
