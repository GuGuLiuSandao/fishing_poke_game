extends SceneTree

const TARGET_ROUNDS := 20
const EXPECTED_TOTAL_CHIPS := 400

const START_BUTTON_PATH := "RootMargin/RootVBox/Content/Sidebar/SideMargin/SideVBox/SetupPanel/StartButton"
const BET_BUTTON_PATH := "RootMargin/RootVBox/Content/Sidebar/SideMargin/SideVBox/FirstActionRow/BetButton"
const EAT_BUTTON_PATH := "RootMargin/RootVBox/Content/Sidebar/SideMargin/SideVBox/FirstActionRow/EatButton"
const FOLD_BUTTON_PATH := "RootMargin/RootVBox/Content/Sidebar/SideMargin/SideVBox/FirstActionRow/FoldButton"
const CHECK_BUTTON_PATH := "RootMargin/RootVBox/Content/Sidebar/SideMargin/SideVBox/FollowActionRow/CheckButton"
const DAI_BUTTON_PATH := "RootMargin/RootVBox/Content/Sidebar/SideMargin/SideVBox/FollowActionRow/DaiButton"
const NEXT_ROUND_BUTTON_PATH := "RootMargin/RootVBox/Content/Sidebar/SideMargin/SideVBox/NextRoundButton"
const RESTART_BUTTON_PATH := "RootMargin/RootVBox/Content/Sidebar/SideMargin/SideVBox/RestartButton"

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

	if not await _click_control(main.get_node(START_BUTTON_PATH), "开始挑战"):
		return
	if not await _wait_for_search(main):
		return
	if not _require(str(main.game.get_state()["phase"]) != "setup", "点击开始挑战后仍停留在准备阶段"):
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

		if not await _wait_for_search(main):
			return
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
					if not await _click_control(main.get_node(NEXT_ROUND_BUTTON_PATH), "下一局"):
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
					if not await _click_control(main.get_node(RESTART_BUTTON_PATH), "重新开始"):
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

	var final_round_before_restart := int(final_state["round_index"])
	if not await _click_control(main.get_node(RESTART_BUTTON_PATH), "重新开始"):
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

	var button_path := ""
	var action_name := ""
	if actions.has("bet"):
		if category >= 10 and int(state["max_bet"]) == pot:
			button_path = EAT_BUTTON_PATH
			action_name = "吃"
		elif category >= 6 or total_round_number % 6 == 0:
			button_path = BET_BUTTON_PATH
			action_name = "下注"
		else:
			button_path = FOLD_BUTTON_PATH
			action_name = "弃牌"
	elif actions.has("dai") and category >= 9 and pot <= 24:
		button_path = DAI_BUTTON_PATH
		action_name = "带"
	elif actions.has("check"):
		button_path = CHECK_BUTTON_PATH
		action_name = "过牌"
	else:
		_fail("真人回合没有可点击的合法按钮")
		return false

	var before_log: Array = state["action_log"]
	for attempt in range(3):
		if not await _click_control(main.get_node(button_path), action_name):
			return false
		var after_log: Array = main.game.get_state()["action_log"]
		if after_log != before_log:
			return true
	return _require(false, "连续三次点击%s后对局日志仍未变化" % action_name)

func _click_control(control: Control, action_name: String) -> bool:
	if not _require(control.is_visible_in_tree(), "%s按钮当前不可见" % action_name):
		return false
	if control is BaseButton and not _require(not control.disabled, "%s按钮当前不可用" % action_name):
		return false

	var position := control.get_global_rect().get_center()
	root.grab_focus()
	Input.warp_mouse(position)
	await process_frame

	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	Input.parse_input_event(motion)
	await process_frame

	var pressed := InputEventMouseButton.new()
	pressed.button_index = MOUSE_BUTTON_LEFT
	pressed.position = position
	pressed.global_position = position
	pressed.pressed = true
	pressed.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(pressed)
	await process_frame

	var released := InputEventMouseButton.new()
	released.button_index = MOUSE_BUTTON_LEFT
	released.position = position
	released.global_position = position
	released.pressed = false
	released.button_mask = 0
	Input.parse_input_event(released)
	await _settle_ui()

	_click_counts[action_name] += 1
	return true

func _settle_ui() -> void:
	await process_frame
	await process_frame

func _wait_for_search(main) -> bool:
	var started := Time.get_ticks_msec()
	while main.game.needs_search_bot_action():
		if not _require(Time.get_ticks_msec() - started < 5000, "等待 SearchBot 超过 5 秒"):
			return false
		await process_frame
	return true

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
			"SearchBot 完成后界面没有停在真人行动回合"
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
