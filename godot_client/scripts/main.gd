extends Control

const LocalGameScript = preload("res://scripts/game/local_game.gd")

var game: RefCounted
var seat_views: Array = []

@onready var header: PanelContainer = $RootMargin/RootVBox/Header
@onready var table_wrap: PanelContainer = $RootMargin/RootVBox/Content/TableWrap
@onready var table_surface: PanelContainer = $RootMargin/RootVBox/Content/TableWrap/TableArea/TableSurface
@onready var seat_layer: Control = $RootMargin/RootVBox/Content/TableWrap/TableArea/SeatLayer
@onready var sidebar: PanelContainer = $RootMargin/RootVBox/Content/Sidebar

@onready var round_value: Label = $RootMargin/RootVBox/Header/HeaderMargin/HeaderRow/RoundBox/Value
@onready var pot_value: Label = $RootMargin/RootVBox/Header/HeaderMargin/HeaderRow/PotBox/Value
@onready var phase_value: Label = $RootMargin/RootVBox/Header/HeaderMargin/HeaderRow/PhaseBox/Value
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

	start_button.pressed.connect(_on_start_pressed)
	bet_button.pressed.connect(_on_bet_pressed)
	eat_button.pressed.connect(_on_eat_pressed)
	fold_button.pressed.connect(_on_fold_pressed)
	check_button.pressed.connect(_on_check_pressed)
	dai_button.pressed.connect(_on_dai_pressed)
	next_round_button.pressed.connect(_on_next_round_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
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
		_render()

func _on_check_pressed() -> void:
	if game.player_action("check"):
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

func _render() -> void:
	var state: Dictionary = game.get_state()
	var current_phase := str(state["phase"])
	var actions: Array = state["available_actions"]

	round_value.text = "—" if int(state["round_index"]) == 0 else str(state["round_index"])
	pot_value.text = "%d 底" % int(state["pot"])
	table_pot.text = "%d" % int(state["pot"])
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
		eat_button.visible = maximum >= int(state["pot"])
		eat_button.text = "吃 %d" % int(state["pot"])
	else:
		eat_button.visible = false
	if actions.has("dai"):
		dai_button.text = "带 %d" % int(state["dai_amount"])

	action_help.text = _action_help(state)
	round_message.text = _center_message(state)
	_render_log(state["action_log"])
	_render_seats(state)

func _render_seats(state: Dictionary) -> void:
	var seats: Array = state["seats"]
	if seat_views.size() != seats.size():
		_rebuild_seat_views(seats.size())

	for index in range(seats.size()):
		var seat: Dictionary = seats[index]
		var view: Dictionary = seat_views[index]
		view["name"].text = str(seat["name"])
		view["chips"].text = "%d 底" % int(seat["chips"])
		view["status"].text = str(seat["status"])
		view["cards"].text = str(seat["cards_text"])
		view["hand"].text = str(seat["hand_name"])

		var panel: PanelContainer = view["panel"]
		if index == int(state["active_seat_index"]):
			panel.add_theme_stylebox_override("panel", _seat_style(Color("#5b451d"), Color("#f2c85b"), 3))
		elif not bool(seat["participating"]):
			panel.add_theme_stylebox_override("panel", _seat_style(Color("#181d20"), Color("#343c41"), 1))
		elif bool(seat["folded"]):
			panel.add_theme_stylebox_override("panel", _seat_style(Color("#24282b"), Color("#4b5053"), 1))
		elif index == 0:
			panel.add_theme_stylebox_override("panel", _seat_style(Color("#163b3a"), Color("#47b5a5"), 2))
		else:
			panel.add_theme_stylebox_override("panel", _seat_style(Color("#20282d"), Color("#526068"), 1))
	_layout_seats()

func _rebuild_seat_views(count: int) -> void:
	for child in seat_layer.get_children():
		child.queue_free()
	seat_views = []

	for index in range(count):
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(184, 136)
		panel.size = Vector2(184, 136)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		seat_layer.add_child(panel)

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_theme_constant_override("margin_top", 9)
		margin.add_theme_constant_override("margin_right", 12)
		margin.add_theme_constant_override("margin_bottom", 9)
		panel.add_child(margin)

		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 1)
		margin.add_child(column)

		var name_label := Label.new()
		name_label.add_theme_font_size_override("font_size", 18)
		name_label.add_theme_color_override("font_color", Color("#f1f3ef"))
		column.add_child(name_label)

		var chips_label := Label.new()
		chips_label.add_theme_color_override("font_color", Color("#f2c85b"))
		column.add_child(chips_label)

		var cards_label := Label.new()
		cards_label.add_theme_font_size_override("font_size", 18)
		cards_label.add_theme_color_override("font_color", Color("#f5f1e6"))
		column.add_child(cards_label)

		var hand_label := Label.new()
		hand_label.add_theme_color_override("font_color", Color("#6fd0bd"))
		column.add_child(hand_label)

		var status_label := Label.new()
		status_label.add_theme_color_override("font_color", Color("#aeb9bd"))
		status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		column.add_child(status_label)

		seat_views.append({
			"panel": panel,
			"name": name_label,
			"chips": chips_label,
			"cards": cards_label,
			"hand": hand_label,
			"status": status_label
		})

	call_deferred("_layout_seats")

func _layout_seats() -> void:
	if seat_views.is_empty() or seat_layer.size.x <= 0.0:
		return
	var panel_size := Vector2(184, 136)
	var center := seat_layer.size / 2.0
	var radius_x := maxi(0, floori((seat_layer.size.x - panel_size.x) / 2.0) - 24)
	var radius_y := maxi(0, floori((seat_layer.size.y - panel_size.y) / 2.0) - 18)
	var count := seat_views.size()

	for index in range(count):
		var angle := PI / 2.0 + TAU * float(index) / float(count)
		var position := center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y) - panel_size / 2.0
		var panel: PanelContainer = seat_views[index]["panel"]
		panel.position = position
		panel.size = panel_size

func _render_log(lines: Array) -> void:
	var output: PackedStringArray = []
	for line in lines:
		output.append("[color=#aeb9bd]•[/color] %s" % str(line))
	log_text.text = "\n".join(output)
	log_text.scroll_to_line(maxi(0, output.size() - 1))

func _action_help(state: Dictionary) -> String:
	var phase := str(state["phase"])
	var actions: Array = state["available_actions"]
	if phase == "setup":
		return "一场挑战最多 6 人；所有规则都在本地运行。"
	if phase == "round_end":
		return "本局已经结算。确认牌面和底池后进入下一局。"
	if phase == "game_over":
		return str(state["match_message"])
	if actions.has("bet"):
		return "这是你本局第一次行动：选择 1～%d 底，或弃牌。" % int(state["max_bet"])
	if actions.has("check"):
		if actions.has("dai"):
			return "你已经下注过：可以过牌，或带满当前底池。"
		return "筹码不足以带满底池，本次只能过牌。"
	return "Bot 正在行动。"

func _center_message(state: Dictionary) -> String:
	var phase := str(state["phase"])
	if phase == "setup":
		return "选择右侧配置\n开始一场本地挑战"
	if phase == "game_over":
		return str(state["match_message"])
	if not str(state["round_message"]).is_empty():
		return str(state["round_message"])
	var active_index := int(state["active_seat_index"])
	if active_index >= 0:
		return "轮到 %s" % state["seats"][active_index]["name"]
	return "等待行动"

func _phase_text(phase: String) -> String:
	match phase:
		"setup":
			return "准备"
		"playing":
			return "行动中"
		"round_end":
			return "本局结束"
		"game_over":
			return "挑战结束"
	return phase

func _apply_styles() -> void:
	header.add_theme_stylebox_override("panel", _panel_style(Color("#172127"), Color("#2c3940")))
	table_wrap.add_theme_stylebox_override("panel", _panel_style(Color("#11181c"), Color("#263238")))
	sidebar.add_theme_stylebox_override("panel", _panel_style(Color("#172127"), Color("#2c3940")))

	var table_style := StyleBoxFlat.new()
	table_style.bg_color = Color("#174c3a")
	table_style.border_color = Color("#94653a")
	table_style.set_border_width_all(10)
	table_style.set_corner_radius_all(120)
	table_style.shadow_color = Color(0, 0, 0, 0.35)
	table_style.shadow_size = 14
	table_surface.add_theme_stylebox_override("panel", table_style)

	_style_button(start_button, Color("#d7a832"), Color("#17140b"))
	_style_button(bet_button, Color("#d7a832"), Color("#17140b"))
	_style_button(eat_button, Color("#efc85a"), Color("#17140b"))
	_style_button(fold_button, Color("#9d3f44"), Color("#ffffff"))
	_style_button(check_button, Color("#425a68"), Color("#ffffff"))
	_style_button(dai_button, Color("#2f806c"), Color("#ffffff"))
	_style_button(next_round_button, Color("#2f806c"), Color("#ffffff"))
	_style_button(restart_button, Color("#343f45"), Color("#e3e8e9"))

func _style_button(button: Button, background: Color, foreground: Color) -> void:
	var normal := _panel_style(background, background.lightened(0.12))
	var hover := _panel_style(background.lightened(0.08), background.lightened(0.2))
	var pressed := _panel_style(background.darkened(0.08), background)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", foreground)
	button.add_theme_color_override("font_hover_color", foreground)
	button.add_theme_color_override("font_pressed_color", foreground)

func _panel_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	return style

func _seat_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := _panel_style(background, border)
	style.set_border_width_all(width)
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0, 0, 0, 0.28)
	style.shadow_size = 6
	return style
