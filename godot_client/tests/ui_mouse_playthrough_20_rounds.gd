extends SceneTree

const TARGET_ROUNDS := 20
const EXPECTED_TOTAL_CHIPS := 400

var _click_counts := {
	"开始挑战": 0,
	"下注": 0,
	"吃": 0,
	"弃牌": 0,
	"过牌": 0,
	"带": 0,
	"下一局": 0,
	"重新开始": 0
}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn")
	var main := scene.instantiate()
	root.add_child(main)
	await _settle_ui()
	main._sound_enabled = false
	main._motion_enabled = false

	if not await _click_control(main.start_button, "开始挑战"):
		return
	await _wait_for_turn(main)
	if not _require(str(main.game.get_state()["phase"]) != "setup", "点击开始挑战后仍停留在准备阶段"):
		return
	if not await _click_control(main.history_button, "牌局记录"):
		return
	if not _require(main._overlay.visible, "点击牌局记录后面板未打开"):
		return
	if not await _click_control(main._dialog_close, "关闭记录"):
		return
	if not _require(not main._overlay.visible, "关闭记录后面板仍然可见"):
		return

	var completed_rounds := 0
	var safety := 0
	var rounds_in_current_match := 0
	var last_recorded_round := 0

	print("ui_mouse_playthrough_20_rounds: viewport=%s" % root.size)
	while completed_rounds < TARGET_ROUNDS:
		safety += 1
		if not _require(safety <= 1200, "鼠标回放超过安全上限"):
			return

		await _wait_for_turn(main)
		var state: Dictionary = main.game.get_state()
		if not _validate_state(main, state):
			return

		match str(state["phase"]):
			"playing":
				if not await _click_human_action(main, state, completed_rounds + 1):
					return
			"round_end":
				if int(state["round_index"]) != last_recorded_round:
					completed_rounds += 1
					rounds_in_current_match += 1
					last_recorded_round = int(state["round_index"])
					print(_round_report_line(completed_rounds, state))
				if completed_rounds < TARGET_ROUNDS:
					var previous_round := int(state["round_index"])
					if not await _click_control(main.action_bar.next_button, "下一局"):
						return
					if not _require(int(main.game.get_state()["round_index"]) == previous_round + 1, "点击下一局后局号没有增加"):
						return
			"game_over":
				if int(state["round_index"]) != last_recorded_round and not str(state["round_message"]).is_empty():
					completed_rounds += 1
					rounds_in_current_match += 1
					last_recorded_round = int(state["round_index"])
					print(_round_report_line(completed_rounds, state))
				if completed_rounds < TARGET_ROUNDS:
					if not await _click_restart(main):
						return
					last_recorded_round = 0
					rounds_in_current_match = 0
					if not _require(int(main.game.get_state()["round_index"]) == 1, "点击重新开始后没有进入新挑战第一局"):
						return
			_:
				_fail("出现未知界面阶段：%s" % state["phase"])
				return

	var final_state: Dictionary = main.game.get_state()
	if not _require(completed_rounds == TARGET_ROUNDS, "没有通过鼠标严格完成 20 局"):
		return
	if not _validate_state(main, final_state):
		return
	root.size = Vector2i(1024, 600)
	await _settle_ui()

	var final_round_before_restart := int(final_state["round_index"])
	if not await _click_restart(main):
		return
	var restarted: Dictionary = main.game.get_state()
	if not _require(int(restarted["round_index"]) == 1, "最终重新开始点击未生效"):
		return
	if not _require(int(restarted["pot"]) >= 0, "重新开始后的底池无效"):
		return

	print("鼠标点击统计：%s" % _click_counts_text())
	print("已完成局数=%d，最终挑战内局数=%d，重开前局号=%d" % [
		completed_rounds,
		rounds_in_current_match,
		final_round_before_restart
	])
	print("ui_mouse_playthrough_20_rounds: ok")
	quit()

func _click_human_action(main, state: Dictionary, total_round_number: int) -> bool:
	var actions: Array = state["available_actions"]
	var hand: Dictionary = main.game.seats[0]["hand"]
	var category := int(hand["category"])
	var pot := int(state["pot"])

	var button: Button
	var action_name: String
	var amount := 0
	var before: int = main.game.structured_action_history.size()
	if actions.has("bet"):
		var maximum := int(state["max_bet"])
		if category >= 10 and int(state["max_bet"]) == pot:
			amount = pot
		elif category >= 6 or total_round_number % 6 == 0:
			amount = mini(2, maximum)
		if amount > 0:
			var input: LineEdit = main.action_bar.amount_input
			if not await _click_control(input, "输入金额"):
				return false
			_type_number(amount)
			await _settle_ui()
			if not _require(input.text == str(amount), "下注金额输入框没有收到键盘输入"):
				return false
			if not _require(main.game.structured_action_history.size() == before, "输入金额时提前提交了行动"):
				return false
			button = main.action_bar.bet_button
			action_name = "吃" if amount == pot else "下注"
		else:
			button = main.action_bar.fold_button
			action_name = "弃牌"
	elif actions.has("dai") and category >= 9 and pot <= 24:
		button = main.action_bar.dai_button
		action_name = "带"
		amount = int(state["dai_amount"])
	elif actions.has("check"):
		button = main.action_bar.check_button
		action_name = "过牌"
	else:
		_fail("真人回合没有可点击的合法按钮")
		return false

	if not await _click_control(button, action_name):
		return false
	if not _require(main.game.structured_action_history.size() > before, "点击%s后未提交行动" % action_name):
		return false
	var event: Dictionary = main.game.structured_action_history[before]
	return _require(int(event["amount"]) == amount, "%s提交的底数与所选金额不符" % action_name)

func _type_number(amount: int) -> void:
	var value := str(amount)
	for index in range(value.length()):
		var digit := value.unicode_at(index)
		for pressed in [true, false]:
			var event := InputEventKey.new()
			event.keycode = digit as Key
			event.unicode = digit if pressed else 0
			event.pressed = pressed
			root.push_input(event, true)

func _click_restart(main) -> bool:
	if main.game.phase == "game_over":
		return await _click_control(main.action_bar.restart_button, "重新开始")
	if not await _click_control(main.restart_button, "重新开始"):
		return false
	var confirm_button: Button = main._dialog_body.get_child(-1)
	return await _click_control(confirm_button, "确认重新开始")

func _wait_for_turn(main) -> void:
	var deadline := Time.get_ticks_msec() + 3000
	while main.game.phase == "playing" and main.game.get_available_actions().is_empty():
		if Time.get_ticks_msec() > deadline:
			_fail("等候 Bot 行动超时")
			break
		await process_frame
	await _settle_ui()

func _click_control(control: Control, action_name: String) -> bool:
	if not _require(control.is_visible_in_tree(), "%s按钮当前不可见" % action_name):
		return false
	if control is BaseButton and not _require(not control.disabled, "%s按钮当前不可用" % action_name):
		return false

	var position := control.get_global_rect().get_center()

	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	root.push_input(motion, true)
	await process_frame
	if not _require(root.gui_get_hovered_control() == control, "%s 按钮被其他控件遮挡" % action_name):
		return false

	var pressed := InputEventMouseButton.new()
	pressed.button_index = MOUSE_BUTTON_LEFT
	pressed.position = position
	pressed.global_position = position
	pressed.pressed = true
	pressed.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(pressed, true)
	await process_frame

	var released := InputEventMouseButton.new()
	released.button_index = MOUSE_BUTTON_LEFT
	released.position = position
	released.global_position = position
	released.pressed = false
	released.button_mask = 0
	root.push_input(released, true)
	await _settle_ui()

	_click_counts[action_name] = _click_counts.get(action_name, 0) + 1
	return true

func _settle_ui() -> void:
	await process_frame
	await process_frame

func _validate_state(main, state: Dictionary) -> bool:
	var total := int(state["pot"])
	for seat in main.game.seats:
		total += int(seat["chips"])
		if not _require(int(seat["chips"]) >= -1, "%s 的筹码低于 -1" % seat["name"]):
			return false
	if not _require(total == EXPECTED_TOTAL_CHIPS, "UI 回放中筹码与底池总量不守恒"):
		return false

	if str(state["phase"]) == "playing":
		if not _require(
			int(state["active_seat_index"]) == int(state["human_seat_index"]),
			"Bot 行动后界面没有停在真人行动回合"
		):
			return false
		for index in range(1, state["seats"].size()):
			var seat: Dictionary = state["seats"][index]
			if bool(seat["participating"]) and not bool(seat["revealed"]):
				if not _require(str(seat["cards_text"]) == "?? ??", "%s 的暗牌在界面泄露" % seat["name"]):
					return false

	return true

func _round_report_line(total_round_number: int, state: Dictionary) -> String:
	return "鼠标局 %02d | 对局内第 %d 局 | %s | 底池=%d | %s" % [
		total_round_number,
		state["round_index"],
		state["round_message"],
		state["pot"],
		_chips_text(state["seats"])
	]

func _chips_text(seats: Array) -> String:
	var values: PackedStringArray = []
	for seat in seats:
		values.append("%s=%d" % [seat["name"], seat["chips"]])
	return "，".join(values)

func _click_counts_text() -> String:
	var values: PackedStringArray = []
	for action_name in _click_counts:
		values.append("%s=%d" % [action_name, _click_counts[action_name]])
	return "，".join(values)

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false

func _fail(message: String) -> void:
	printerr("ui_mouse_playthrough_20_rounds: FAILED: %s" % message)
	quit(1)
