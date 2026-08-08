extends SceneTree

const LocalGameScript = preload("res://scripts/game/local_game.gd")

const TARGET_ROUNDS := 20
const BOT_COUNT := 3
const TEST_SEED := 20260731
const EXPECTED_TOTAL_CHIPS := (BOT_COUNT + 1) * 100

var _human_action_counts := {
	"bet": 0,
	"eat": 0,
	"fold": 0,
	"check": 0,
	"dai": 0
}
var _table_action_counts := {
	"bet": 0,
	"eat": 0,
	"fold": 0,
	"check": 0,
	"dai": 0
}

func _init() -> void:
	var game = LocalGameScript.new()
	game.start_match(BOT_COUNT, TEST_SEED)

	var completed_rounds := 0
	var safety := 0
	var round_human_actions: Array[String] = []

	print("playthrough_20_rounds: seed=%d, players=%d" % [TEST_SEED, BOT_COUNT + 1])
	while completed_rounds < TARGET_ROUNDS:
		safety += 1
		if not _require(safety <= 1000, "回放超过行动安全上限"):
			return

		var state: Dictionary = game.get_state()
		if not _validate_state(game, state):
			return

		match str(state["phase"]):
			"playing":
				var decision := _choose_human_action(game, state, completed_rounds + 1)
				var action := str(decision["action"])
				var amount := int(decision["amount"])
				var action_label := _action_label(action, amount, int(state["pot"]))
				round_human_actions.append(action_label)
				if action == "bet" and amount == int(state["pot"]):
					_human_action_counts["eat"] += 1
				else:
					_human_action_counts[action] += 1
				if not _require(game.player_action(action, amount), "第 %d 局真人动作被拒绝：%s" % [completed_rounds + 1, action_label]):
					return
			"round_end":
				completed_rounds += 1
				if not _require(int(state["round_index"]) == completed_rounds, "局号没有连续递增"):
					return
				if not _validate_round_end_visibility(game, state):
					return
				_count_round_actions(state)
				print(_round_report_line(state, round_human_actions))
				round_human_actions.clear()
				if completed_rounds < TARGET_ROUNDS:
					if not _require(game.start_next_round(), "第 %d 局后无法开始下一局" % completed_rounds):
						return
			"game_over":
				_fail("挑战在完成 %d 局后提前结束：%s" % [completed_rounds, state["match_message"]])
				return
			_:
				_fail("出现未知阶段：%s" % state["phase"])
				return

	var final_state: Dictionary = game.get_state()
	if not _require(completed_rounds == TARGET_ROUNDS, "没有严格完成 20 局"):
		return
	if not _validate_state(game, final_state):
		return

	print("真人动作统计：下注=%d，吃=%d，弃牌=%d，过牌=%d，带=%d" % [
		_human_action_counts["bet"],
		_human_action_counts["eat"],
		_human_action_counts["fold"],
		_human_action_counts["check"],
		_human_action_counts["dai"]
	])
	print("全桌动作统计：下注=%d，吃=%d，弃牌=%d，过牌=%d，带=%d" % [
		_table_action_counts["bet"],
		_table_action_counts["eat"],
		_table_action_counts["fold"],
		_table_action_counts["check"],
		_table_action_counts["dai"]
	])
	print("最终筹码：%s；底池=%d；总量=%d" % [
		_chips_text(final_state["seats"]),
		final_state["pot"],
		_total_value(game)
	])
	print("playthrough_20_rounds: ok")
	quit()

func _choose_human_action(game, state: Dictionary, round_number: int) -> Dictionary:
	var legal: Array = state["available_actions"]
	var hand: Dictionary = game.seats[0]["hand"]
	var category := int(hand["category"])
	var pot_before := int(state["pot"])

	if legal.has("bet"):
		var max_bet := int(state["max_bet"])
		if category >= 10 and max_bet == pot_before:
			return {"action": "bet", "amount": pot_before}
		if category >= 8:
			return {"action": "bet", "amount": mini(max_bet, maxi(1, ceili(float(pot_before) / 2.0)))}
		if category >= 6 or round_number % 6 == 0:
			return {"action": "bet", "amount": 1}
		return {"action": "fold", "amount": 0}

	if legal.has("dai") and category >= 9 and pot_before <= 24:
		return {"action": "dai", "amount": pot_before}
	if legal.has("check"):
		return {"action": "check", "amount": 0}

	return {"action": "fold", "amount": 0}

func _validate_state(game, state: Dictionary) -> bool:
	if not _require(int(state["pot"]) >= 0, "底池不能为负数"):
		return false
	if not _require(_total_value(game) == EXPECTED_TOTAL_CHIPS, "筹码与底池总量不守恒"):
		return false

	var seen_cards := {}
	for index in range(game.seats.size()):
		var internal_seat: Dictionary = game.seats[index]
		var visible_seat: Dictionary = state["seats"][index]
		if not _require(int(internal_seat["chips"]) >= -1, "%s 的筹码低于 -1" % internal_seat["name"]):
			return false
		if bool(internal_seat["participating"]):
			if not _require(internal_seat["cards"].size() == 2, "%s 没有拿到两张牌" % internal_seat["name"]):
				return false
			for card in internal_seat["cards"]:
				var label := str(card["label"])
				if not _require(not seen_cards.has(label), "本局出现重复牌：%s" % label):
					return false
				seen_cards[label] = true

		if str(state["phase"]) == "playing" and index > 0 and not bool(internal_seat["revealed"]):
			var expected_cards := "?? ??" if bool(internal_seat["participating"]) else "—"
			if not _require(str(visible_seat["cards_text"]) == expected_cards, "%s 的暗牌发生泄露" % internal_seat["name"]):
				return false

	if str(state["phase"]) == "playing":
		if not _require(int(state["active_seat_index"]) == 0, "Bot 自动行动后没有停在真人回合"):
			return false
		var actions: Array = state["available_actions"]
		if not _require(not actions.is_empty(), "真人回合没有合法动作"):
			return false
		var human: Dictionary = game.seats[0]
		if bool(human["has_bet"]):
			if not _require(actions.has("check") and not actions.has("bet") and not actions.has("fold"), "已下注后的合法动作不正确"):
				return false
		else:
			if not _require(actions.has("fold") and not actions.has("check"), "首次行动的合法动作不正确"):
				return false

	return true

func _validate_round_end_visibility(game, state: Dictionary) -> bool:
	for index in range(1, game.seats.size()):
		var internal_seat: Dictionary = game.seats[index]
		var visible_seat: Dictionary = state["seats"][index]
		if bool(internal_seat["folded"]):
			if not _require(str(visible_seat["cards_text"]) in ["?? ??", "—"], "%s 弃牌后亮出了暗牌" % internal_seat["name"]):
				return false
		elif bool(internal_seat["revealed"]):
			if not _require(str(visible_seat["cards_text"]) != "?? ??", "%s 比牌时没有亮牌" % internal_seat["name"]):
				return false
	return true

func _round_report_line(state: Dictionary, human_actions: Array[String]) -> String:
	var actions_text := "无（Bot 行动后已结束）" if human_actions.is_empty() else " -> ".join(human_actions)
	return "第 %02d 局 | 你：%s | %s | 底池=%d | %s" % [
		state["round_index"],
		actions_text,
		state["round_message"],
		state["pot"],
		_chips_text(state["seats"])
	]

func _count_round_actions(state: Dictionary) -> void:
	var lines: Array = state["action_log"]
	var start_index := 0
	for index in range(lines.size()):
		if str(lines[index]).begins_with("—— 第 "):
			start_index = index

	for index in range(start_index, lines.size()):
		var line := str(lines[index])
		if line.contains(" 弃牌。"):
			_table_action_counts["fold"] += 1
		elif line.contains(" 下注 "):
			_table_action_counts["bet"] += 1
		elif line.contains(" 吃 "):
			_table_action_counts["eat"] += 1
		elif line.contains(" 过牌。"):
			_table_action_counts["check"] += 1
		elif line.contains(" 带 "):
			_table_action_counts["dai"] += 1

func _action_label(action: String, amount: int, pot_before: int) -> String:
	match action:
		"bet":
			return ("吃 %d" if amount == pot_before else "下注 %d") % amount
		"fold":
			return "弃牌"
		"check":
			return "过牌"
		"dai":
			return "带 %d" % pot_before
	return action

func _chips_text(visible_seats: Array) -> String:
	var values: PackedStringArray = []
	for seat in visible_seats:
		values.append("%s=%d" % [seat["name"], seat["chips"]])
	return "，".join(values)

func _total_value(game) -> int:
	var total := int(game.pot)
	for seat in game.seats:
		total += int(seat["chips"])
	return total

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false

func _fail(message: String) -> void:
	printerr("playthrough_20_rounds: FAILED: %s" % message)
	quit(1)
