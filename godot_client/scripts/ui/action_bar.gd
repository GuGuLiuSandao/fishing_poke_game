extends PanelContainer

const Styles = preload("res://scripts/ui/table_theme.gd")

signal action_requested(action: String, amount: int)
signal next_round_requested
signal restart_requested

var fold_button: Button
var bet_button: Button
var check_button: Button
var dai_button: Button
var next_button: Button
var restart_button: Button
var slider := HSlider.new()
var amount_input := LineEdit.new()
var _title: Label
var _help: Label
var _bet_controls := HBoxContainer.new()
var _slider_focus := Panel.new()
var _bet_row := HBoxContainer.new()
var _follow_row := HBoxContainer.new()
var _finished_row := HBoxContainer.new()
var _selected_bet := 0
var _pot := 0
var _max_bet := 0
var _dai_amount := 0

func _ready() -> void:
	custom_minimum_size.y = 140
	var inner := Styles.margin(12, 9)
	add_child(inner)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	inner.add_child(row)

	var copy := VBoxContainer.new()
	copy.custom_minimum_size.x = 244
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.size_flags_horizontal = SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 4)
	row.add_child(copy)
	_title = Styles.label("", 23)
	copy.add_child(_title)
	_help = Styles.label("", 15, Styles.MUTED)
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(_help)

	var actions := VBoxContainer.new()
	actions.custom_minimum_size.x = 434
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 10)
	row.add_child(actions)
	_build_bet_controls()
	actions.add_child(_bet_controls)
	actions.add_child(_bet_row)
	actions.add_child(_follow_row)
	actions.add_child(_finished_row)
	for group in [_bet_row, _follow_row, _finished_row]:
		group.add_theme_constant_override("separation", 8)
		group.alignment = BoxContainer.ALIGNMENT_END

	fold_button = _action_button(_bet_row, "弃牌", "Red")
	fold_button.pressed.connect(func() -> void: action_requested.emit("fold", 0))
	bet_button = _action_button(_bet_row, "下注", "Gold", 268)
	bet_button.pressed.connect(_submit_bet)
	check_button = _action_button(_follow_row, "过牌", "Button")
	check_button.pressed.connect(func() -> void: action_requested.emit("check", 0))
	dai_button = _action_button(_follow_row, "带", "Gold", 268)
	dai_button.pressed.connect(func() -> void: action_requested.emit("dai", _dai_amount))
	next_button = _action_button(_finished_row, "下一局", "Gold", 268)
	next_button.pressed.connect(func() -> void: next_round_requested.emit())
	restart_button = _action_button(_finished_row, "重新开始", "Gold", 268)
	restart_button.pressed.connect(func() -> void: restart_requested.emit())

func _build_bet_controls() -> void:
	_bet_controls.add_theme_constant_override("separation", 8)
	_bet_controls.add_child(Styles.label("下注金额", 15, Styles.MUTED))
	slider.min_value = 1
	slider.step = 1
	slider.custom_minimum_size = Vector2(115, 44)
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	slider.accessibility_name = "下注金额"
	slider.tooltip_text = "拖动调整下注金额"
	slider.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	slider.value_changed.connect(func(amount: float) -> void: _select_bet(int(amount)))
	slider.drag_ended.connect(func(value_changed: bool) -> void:
		if not value_changed:
			_select_bet(int(slider.value))
	)
	_bet_controls.add_child(slider)
	_slider_focus.mouse_filter = MOUSE_FILTER_IGNORE
	_slider_focus.add_theme_stylebox_override("panel", Styles.focus_box(7))
	slider.add_child(_slider_focus)
	_slider_focus.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	slider.focus_entered.connect(_slider_focus.show)
	slider.focus_exited.connect(_slider_focus.hide)
	_slider_focus.hide()

	amount_input.custom_minimum_size = Vector2(92, 44)
	amount_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount_input.placeholder_text = "输入"
	amount_input.max_length = 6
	amount_input.accessibility_name = "输入下注底数"
	amount_input.tooltip_text = "输入整数底数"
	amount_input.text_changed.connect(_on_amount_edited)
	amount_input.text_submitted.connect(_commit_amount)
	_bet_controls.add_child(amount_input)
	_bet_controls.add_child(Styles.label("底", 14, Styles.MUTED))

func render(state: Dictionary, dealing: bool) -> void:
	var phase := str(state["phase"])
	var actions: Array = state["available_actions"] if not dealing else []
	var betting := actions.has("bet")
	_pot = int(state["pot"])
	_dai_amount = int(state["dai_amount"])
	visible = phase != "setup"
	_bet_controls.visible = betting
	_bet_row.visible = actions.has("fold")
	bet_button.visible = betting
	_follow_row.visible = actions.has("check")
	_finished_row.visible = phase in ["round_end", "game_over"]
	next_button.visible = phase == "round_end"
	restart_button.visible = phase == "game_over"
	_title.add_theme_color_override("font_color", Styles.INK)
	if dealing:
		_title.text = "正在发牌"
		_help.text = ""
	elif phase == "round_end":
		_title.text = "本局已结算"
		_help.text = ""
	elif phase == "game_over":
		_title.text = "本次挑战已结束"
		_help.text = "重新开始后，每人恢复 100 底。"
	elif betting:
		_title.text = "轮到你"
		_title.add_theme_color_override("font_color", Styles.GOLD)
		_max_bet = int(state["max_bet"])
		slider.set_block_signals(true)
		slider.max_value = _max_bet
		slider.set_block_signals(false)
		slider.editable = _max_bet > 1
		slider.focus_mode = FOCUS_ALL if slider.editable else FOCUS_NONE
		slider.set_value_no_signal(1)
		amount_input.clear()
		_on_amount_edited("")
	elif actions.has("check"):
		_title.text = "轮到你"
		_title.add_theme_color_override("font_color", Styles.GOLD)
		var can_dai := actions.has("dai")
		dai_button.visible = can_dai
		dai_button.text = "带  %d 底" % _dai_amount if can_dai else "带"
		dai_button.disabled = not can_dai
		_help.text = "过牌后仍可比牌。" if can_dai else "筹码不足以带，过牌后仍可比牌。"
	elif actions.has("fold"):
		_title.text = "轮到你"
		_help.text = "当前没有可投入的筹码。"
	elif phase == "playing":
		var active := int(state["active_seat_index"])
		_title.text = "%s 正在思考" % state["seats"][active]["name"]
		_help.text = ""

func _select_bet(amount: int) -> void:
	amount_input.text = str(amount)
	_on_amount_edited(amount_input.text)

func _on_amount_edited(value: String) -> void:
	var amount_text := value.strip_edges()
	var amount := amount_text.to_int()
	var valid := amount_text.is_valid_int() and amount >= 1 and amount <= _max_bet
	_selected_bet = amount if valid else 0
	amount_input.remove_theme_color_override("font_color")
	_help.text = "可下注 1～%d 底。" % _max_bet if _max_bet > 1 else "可下注 1 底。"
	if valid:
		slider.set_value_no_signal(amount)
	elif not amount_text.is_empty():
		amount_input.add_theme_color_override("font_color", Color("#ffaaa4"))
		_help.text = "请输入 1～%d 的整数。" % _max_bet if _max_bet > 1 else "请输入 1。"
	_update_bet_button()

func _commit_amount(_value: String) -> void:
	if _selected_bet > 0:
		amount_input.text = str(_selected_bet)
		bet_button.grab_focus()

func _update_bet_button() -> void:
	bet_button.disabled = _selected_bet == 0
	var verb := "吃" if _selected_bet == _pot else "下注"
	bet_button.text = "下注" if bet_button.disabled else "%s  %d 底" % [verb, _selected_bet]

func _submit_bet() -> void:
	if _selected_bet > 0:
		action_requested.emit("bet", _selected_bet)

func _action_button(parent: HBoxContainer, value: String, variant: String, width: int = 158) -> Button:
	var node := Styles.button(value, variant, 48)
	node.custom_minimum_size.x = width
	node.add_theme_font_size_override("font_size", 19)
	parent.add_child(node)
	return node
