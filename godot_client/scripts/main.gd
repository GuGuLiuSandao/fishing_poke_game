extends Control

const LocalGameScript = preload("res://scripts/game/local_game.gd")
const Styles = preload("res://scripts/ui/table_theme.gd")
const PokerTable = preload("res://scripts/ui/poker_table.gd")
const ActionBar = preload("res://scripts/ui/action_bar.gd")
const SFX_SHUFFLE = preload("res://assets/audio/card_shuffle.ogg")
const SFX_CARD = preload("res://assets/audio/card_slide.ogg")
const SFX_FOLD = preload("res://assets/audio/card_place.ogg")
const SFX_CHIP = preload("res://assets/audio/chip_lay.ogg")
const SFX_SETTLE = preload("res://assets/audio/chips_collide.ogg")

const RULES := """[b]目标[/b]
每人 100 底。一局结束时，筹码小于或等于 0 的玩家被淘汰。淘汰所有对手即赢得挑战，你被淘汰时挑战结束。

[b]怎么行动[/b]
第一次轮到你，可以弃牌或下注。下注至少 1 底，最多投入当前底池或你的筹码加 1，取较小值。下满底池叫「吃」。
你下注过之后，再轮到你可以过牌或「带」。过牌保留比牌资格。带须投入与当时底池相同的金额，筹码可用到 −1。
有人追加投入后，从这位玩家的下一家继续行动。绕回最后下注的人时比牌，只剩一家时直接结算。

[b]两张牌怎么比[/b]
从弱到强：普通 0～9 点、2+8、Q+8、Q+9、同色对子、至尊（大王+红桃 3）。
普通牌取点数总和的个位数。大王算 6，J 算 11，Q 算 12。同点只比最高权重牌。权重从弱到强：黑 10、红 4、红 8、2、Q。
相同牌面且同色才算对子。对子从弱到强：普通对子、黑 10 对、红 4 对、红 8 对、2 对、Q 对。

[b]底池怎么分[/b]
比牌胜出或下注打跑其他玩家时，收取底池与最后一次下注两倍中的较小值。若从未下注就剩你一人，普通 8 点或更强可捡天水、收走整个底池。
平局或捡天水失败时底池保留。每局开始时，底池不超过本局人数的一半（向下取整），每位参与者补 1 底。"""

var game := LocalGameScript.new()
var table := PokerTable.new()
var action_bar := ActionBar.new()
var start_button: Button
var history_button: Button
var rules_button: Button
var settings_button: Button
var restart_button: Button
var _round_label: Label
var _setup := PanelContainer.new()
var _bot_buttons: Array[Button] = []
var _setup_note: Label
var _bot_count := 3
var _bot_timer := Timer.new()
var _deal_timer := Timer.new()
var _audio_player := AudioStreamPlayer.new()
var _payout_audio := AudioStreamPlayer.new()
var _sound_enabled := true
var _motion_enabled := true
var _manual_peek := false
var _hand_open := true
var _dealing := false
var _overlay := ColorRect.new()
var _dialog := PanelContainer.new()
var _dialog_body := VBoxContainer.new()
var _dialog_close: Button
var _focus_before_dialog: Control
var _history: RichTextLabel

func _ready() -> void:
	theme = Styles.build()
	game.set_auto_drive_bots(false)
	_build_surface()
	_build_overlay()
	_setup.resized.connect(_center_setup)
	resized.connect(_center_setup)
	table.hand_opened.connect(_open_hand)
	action_bar.action_requested.connect(_play_action)
	action_bar.next_round_requested.connect(_next_round)
	action_bar.restart_requested.connect(_restart)
	_bot_timer.one_shot = true
	_bot_timer.timeout.connect(_step_bot)
	add_child(_bot_timer)
	_deal_timer.one_shot = true
	_deal_timer.timeout.connect(_finish_deal)
	add_child(_deal_timer)
	_audio_player.volume_db = -9.0
	add_child(_audio_player)
	_payout_audio.stream = SFX_SETTLE
	_payout_audio.volume_db = -12.0
	add_child(_payout_audio)
	_render()

func _build_surface() -> void:
	var background := TextureRect.new()
	background.mouse_filter = MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var texture := GradientTexture2D.new()
	texture.width = 960
	texture.height = 540
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.42)
	texture.fill_to = Vector2(1.0, 0.86)
	var gradient := Gradient.new()
	gradient.set_color(0, Color("#292823"))
	gradient.set_color(1, Color("#101213"))
	texture.gradient = gradient
	background.texture = texture
	add_child(background)

	var inset := Styles.margin(28, 16)
	inset.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	inset.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(inset)
	var column := VBoxContainer.new()
	column.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 10)
	inset.add_child(column)
	column.add_child(_build_header())
	column.add_child(table)
	column.add_child(action_bar)
	_build_setup()

func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.custom_minimum_size.y = 49
	var mark := TextureRect.new()
	mark.texture = preload("res://assets/icon.svg")
	mark.custom_minimum_size = Vector2(40, 40)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.mouse_filter = MOUSE_FILTER_IGNORE
	header.add_child(mark)
	header.add_child(Styles.label("钓鱼", 26))
	var divider := VSeparator.new()
	divider.custom_minimum_size.x = 16
	header.add_child(divider)
	_round_label = Styles.label("单机牌桌", 15, Styles.MUTED)
	header.add_child(_round_label)
	header.add_child(Styles.spacer())
	history_button = Styles.button("牌局记录", "Quiet")
	history_button.pressed.connect(_open_history)
	header.add_child(history_button)
	rules_button = Styles.button("玩法", "Quiet")
	rules_button.pressed.connect(_open_rules)
	header.add_child(rules_button)
	settings_button = Styles.button("设置", "Quiet")
	settings_button.pressed.connect(_open_settings)
	header.add_child(settings_button)
	restart_button = Styles.button("重新开始", "Quiet")
	restart_button.pressed.connect(_confirm_restart)
	header.add_child(restart_button)
	return header

func _build_setup() -> void:
	_setup.add_theme_stylebox_override("panel", Styles.box(Color("#151c19"), Color("#92774c"), 15))
	_setup.custom_minimum_size.x = 460
	add_child(_setup)
	var inset := Styles.margin(22, 20)
	_setup.add_child(inset)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	inset.add_child(column)
	var title := Styles.label("开始挑战", 32)
	column.add_child(title)
	column.add_child(Styles.label("选择对手人数", 16, Styles.MUTED))
	var counts := HBoxContainer.new()
	counts.add_theme_constant_override("separation", 8)
	column.add_child(counts)
	var group := ButtonGroup.new()
	for count in range(1, 6):
		var button := Styles.button(str(count), "Button")
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = count == _bot_count
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.accessibility_name = "%d 名对手" % count
		button.pressed.connect(func() -> void: _select_bot_count(count))
		counts.add_child(button)
		_bot_buttons.append(button)
	_setup_note = Styles.label("", 15, Styles.MUTED)
	column.add_child(_setup_note)
	_select_bot_count(_bot_count)
	start_button = Styles.button("入座发牌", "Gold", 50)
	start_button.add_theme_font_size_override("font_size", 19)
	start_button.pressed.connect(_start_match)
	column.add_child(start_button)

func _center_setup() -> void:
	_setup.position = ((size - _setup.size) / 2.0 + Vector2(0, 13)).round()

func _select_bot_count(count: int) -> void:
	_bot_count = count
	for index in range(_bot_buttons.size()):
		_bot_buttons[index].theme_type_variation = "Gold" if index == _bot_count - 1 else "Button"
	_setup_note.text = "%d 人桌 · 每人 100 底" % (_bot_count + 1)

func _start_match() -> void:
	game.start_match(_bot_count)
	_begin_deal()

func _restart() -> void:
	game.restart_match()
	_close_dialog()
	_begin_deal()

func _next_round() -> void:
	if game.start_next_round():
		_begin_deal()

func _begin_deal() -> void:
	_stop_timers()
	_hand_open = not _manual_peek
	_dealing = _motion_enabled
	_render()
	if _dealing:
		_play_sfx(SFX_SHUFFLE)
		table.start_deal(game.starter_seat_index)
		_deal_timer.start(0.44)
	else:
		_after_deal()

func _finish_deal() -> void:
	_dealing = false
	table.clear_effects()
	_render()
	_after_deal()

func _after_deal() -> void:
	_play_sfx(SFX_CARD)
	_schedule_bot()
	_focus_for_turn()

func _open_hand() -> void:
	if _dealing or _hand_open:
		return
	_hand_open = true
	table.render(game.get_state(), false)
	if _motion_enabled:
		table.animate_open_hand()
	_play_sfx(SFX_CARD)
	_focus_for_turn()

func _play_action(action: String, amount: int) -> void:
	if _dealing or _overlay.visible:
		return
	if game.player_action(action, amount):
		_after_action()

func _step_bot() -> void:
	if game.step_bot_turn():
		_after_action()

func _schedule_bot() -> void:
	if game.phase == "playing" and game.active_seat_index != game.human_seat_index and not _overlay.visible:
		_bot_timer.start(0.36 if _motion_enabled else 0.05)

func _after_action() -> void:
	_render()
	var event: Dictionary = game.structured_action_history.back()
	if _motion_enabled:
		table.animate_action(event, game.settlement)
		table.animate_reveal(game.settlement)
	match str(event["action"]):
		"fold":
			_play_sfx(SFX_FOLD)
		"check":
			_play_sfx(SFX_CARD)
		_:
			_play_sfx(SFX_CHIP)
	if game.phase in ["round_end", "game_over"] and _sound_enabled:
		_payout_audio.play()
	_schedule_bot()
	if get_viewport().gui_get_focus_owner() == null:
		_focus_for_turn()

func _focus_for_turn() -> void:
	if _overlay.visible:
		return
	var actions := game.get_available_actions()
	if not actions.is_empty() and not _hand_open:
		var view = table.views[game.human_seat_index]
		if view.open_button.is_visible_in_tree():
			view.open_button.grab_focus()
			return
	if actions.has("bet"):
		if action_bar.slider.editable:
			action_bar.slider.grab_focus()
		else:
			action_bar.amount_input.grab_focus()
	elif actions.has("check"):
		if action_bar.dai_button.disabled:
			action_bar.check_button.grab_focus()
	elif actions.has("fold"):
		action_bar.fold_button.grab_focus()
	elif game.phase == "round_end":
		action_bar.next_button.grab_focus()
	elif game.phase == "game_over":
		action_bar.restart_button.grab_focus()

func _render() -> void:
	var state := game.get_state()
	var setup := game.phase == "setup"
	_setup.visible = setup
	history_button.visible = not setup
	restart_button.visible = not setup and game.phase != "game_over"
	_round_label.text = "单机牌桌" if setup else "第 %d 局  ·  %d 人桌" % [game.round_index, game.bot_count + 1]
	table.render(state, not _hand_open)
	action_bar.render(state, _dealing)
	if is_instance_valid(_history):
		_render_history(state["action_log"])

func _stop_timers() -> void:
	_bot_timer.stop()
	_deal_timer.stop()
	table.clear_effects()

func _play_sfx(stream: AudioStream) -> void:
	if _sound_enabled:
		_audio_player.stream = stream
		_audio_player.play()

func _build_overlay() -> void:
	_overlay.color = Color(0.01, 0.014, 0.014, 0.77)
	_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_overlay.hide()
	add_child(_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	_overlay.add_child(center)
	_dialog.custom_minimum_size.x = 560
	_dialog.add_theme_stylebox_override("panel", Styles.box(Styles.PANEL, Color("#796649"), 14))
	center.add_child(_dialog)
	var inset := Styles.margin(14, 12)
	_dialog.add_child(inset)
	_dialog_body.add_theme_constant_override("separation", 12)
	inset.add_child(_dialog_body)

func _show_dialog(title: String) -> void:
	_focus_before_dialog = get_viewport().gui_get_focus_owner()
	_overlay.show()
	_bot_timer.stop()
	if _dealing:
		_deal_timer.stop()
		_finish_deal()
	for child in _dialog_body.get_children():
		_dialog_body.remove_child(child)
		child.queue_free()
	_history = null
	var head := HBoxContainer.new()
	head.add_child(Styles.label(title, 24))
	head.add_child(Styles.spacer())
	_dialog_close = Styles.button("关闭", "Quiet")
	_dialog_close.pressed.connect(_close_dialog)
	head.add_child(_dialog_close)
	_dialog_body.add_child(head)
	_dialog_close.grab_focus()

func _close_dialog() -> void:
	if not _overlay.visible:
		return
	_overlay.hide()
	if is_instance_valid(_focus_before_dialog) and _focus_before_dialog.is_visible_in_tree():
		_focus_before_dialog.grab_focus()
	_schedule_bot()

func _open_history() -> void:
	_show_dialog("牌局记录")
	_history = _dialog_text(310)
	_history.scroll_following = true
	_render_history(game.get_state()["action_log"])

func _render_history(lines: Array) -> void:
	var formatted := PackedStringArray()
	for line in lines:
		if str(line).begins_with("——"):
			formatted.append("[color=#f2cd86][b]%s[/b][/color]" % line)
		else:
			formatted.append(str(line))
	_history.text = "\n".join(formatted)

func _open_rules() -> void:
	_show_dialog("钓鱼玩法")
	_dialog_text(380).text = RULES

func _dialog_text(height: int) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.selection_enabled = true
	label.focus_mode = Control.FOCUS_ALL
	label.custom_minimum_size.y = height
	_dialog_body.add_child(label)
	return label

func _open_settings() -> void:
	_show_dialog("牌桌设置")
	_add_setting("声音", _sound_enabled, func(enabled: bool) -> void:
		_sound_enabled = enabled
		if not enabled:
			_audio_player.stop()
			_payout_audio.stop()
	)
	_add_setting("发牌与筹码动画", _motion_enabled, func(enabled: bool) -> void:
		_motion_enabled = enabled
		if not enabled:
			table.clear_effects()
			table.render(game.get_state(), not _hand_open)
	)
	_add_setting("每局手动看牌", _manual_peek, func(enabled: bool) -> void:
		_manual_peek = enabled
		if not enabled:
			_open_hand()
	)

func _add_setting(title: String, enabled: bool, changed: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_child(Styles.label(title, 17))
	row.add_child(Styles.spacer())
	var button := Styles.button("开启" if enabled else "关闭", "Button")
	button.custom_minimum_size.x = 88
	button.toggle_mode = true
	button.button_pressed = enabled
	button.accessibility_name = title
	button.toggled.connect(func(on: bool) -> void:
		button.text = "开启" if on else "关闭"
		changed.call(on)
	)
	row.add_child(button)
	_dialog_body.add_child(row)

func _confirm_restart() -> void:
	_show_dialog("重新开始挑战？")
	_dialog_body.add_child(Styles.label("当前牌局将结束，每人恢复 100 底。", 17, Styles.MUTED))
	var confirm := Styles.button("确认重新开始", "Red", 48)
	confirm.pressed.connect(_restart)
	_dialog_body.add_child(confirm)

func _input(event: InputEvent) -> void:
	if not _overlay.visible or not event is InputEventKey or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE:
		_close_dialog()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_TAB:
		_move_dialog_focus(event.shift_pressed)
		get_viewport().set_input_as_handled()

func _move_dialog_focus(backward: bool) -> void:
	var controls := _dialog_body.find_children("*", "Control", true, false).filter(
		func(control: Control) -> bool: return control.focus_mode == FOCUS_ALL
	)
	var offset := -1 if backward else 1
	var index := controls.find(get_viewport().gui_get_focus_owner())
	controls[posmod(index + offset, controls.size())].grab_focus()
