class_name LocalGame
extends RefCounted

const HandRulesScript = preload("res://scripts/game/hand_rules.gd")
const GameRulesScript = preload("res://scripts/game/game_rules.gd")
const BotContractScript = preload("res://scripts/game/bot_contract.gd")
const LegacyGeneBotScript = preload("res://scripts/game/legacy_gene_bot.gd")

const STARTING_CHIPS := 100
const HUMAN_SEAT_INDEX := 0
const MAX_LOG_LINES := 80
const BOT_NAMES := ["阿浪", "七筒", "老周", "小满", "北风"]

var phase := "setup"
var round_index := 0
var active_seat_index := -1
var pot := 0
var seats: Array = []
var action_log: Array[String] = []
var structured_action_history: Array[Dictionary] = []
var round_message := ""
var match_message := ""
var match_result := ""
var bot_count := 3
var human_seat_index := HUMAN_SEAT_INDEX

var _rng := RandomNumberGenerator.new()
var _deck: Array = []
var _last_bettor_index := -1
var _bet_order := 0
var _next_starter_index := -1
var _bot_action_provider: Callable
var _bot_rngs: Array[RandomNumberGenerator] = []
var _auto_drive_bots := true
var _action_sequence := 0

func _init() -> void:
	_rng.randomize()
	reset_to_setup()

func reset_to_setup() -> void:
	phase = "setup"
	round_index = 0
	active_seat_index = -1
	pot = 0
	seats = []
	action_log = ["选择 Bot 数量，然后开始挑战。"]
	structured_action_history = []
	round_message = ""
	match_message = ""
	match_result = ""
	_last_bettor_index = -1
	_bet_order = 0
	_next_starter_index = -1
	_action_sequence = 0

func start_match(new_bot_count: int = 3, seed_value: int = 0) -> void:
	bot_count = clampi(new_bot_count, 1, 5)
	human_seat_index = clampi(human_seat_index, 0, bot_count)
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value

	round_index = 0
	active_seat_index = -1
	pot = 0
	round_message = ""
	match_message = ""
	match_result = ""
	_last_bettor_index = -1
	_bet_order = 0
	_next_starter_index = -1
	action_log = []
	structured_action_history = []
	_action_sequence = 0
	_create_seats()
	_seed_bot_rngs(seed_value)
	_push_log("挑战开始：你将对战 %d 名 Bot。" % bot_count)
	_start_round()

func restart_match() -> void:
	start_match(bot_count)

func set_bot_action_provider(provider: Callable) -> void:
	_bot_action_provider = provider

func set_human_seat_index(index: int) -> void:
	human_seat_index = maxi(0, index)

func set_auto_drive_bots(enabled: bool) -> void:
	_auto_drive_bots = enabled

func apply_bot_decision(decision: Dictionary) -> bool:
	if phase != "playing" or active_seat_index < 0:
		return false
	if not bool(seats[active_seat_index]["is_bot"]):
		return false
	if not _apply_action(active_seat_index, str(decision.get("action", "")), int(decision.get("amount", 0))):
		return false
	_drive_bots_until_human_or_end()
	return true

func start_next_round() -> bool:
	if phase != "round_end":
		return false
	_start_round()
	return true

func player_action(action: String, amount: int = 0) -> bool:
	if phase != "playing" or active_seat_index != human_seat_index:
		return false
	if action == "dai" and amount == 0:
		amount = pot
	if not get_available_actions().has(action):
		return false
	if not _apply_action(human_seat_index, action, amount):
		return false
	_drive_bots_until_human_or_end()
	return true

func get_available_actions() -> Array:
	if phase != "playing" or active_seat_index < 0:
		return []
	var seat: Dictionary = seats[active_seat_index]
	if bool(seat["is_bot"]) or bool(seat["folded"]):
		return []
	return _legal_actions_for(active_seat_index)

func get_decision_context(index: int) -> Dictionary:
	if phase != "playing" or active_seat_index != index:
		return {}
	var seat: Dictionary = seats[index]
	if bool(seat["folded"]):
		return {}
	return _bot_context(index, _legal_action_specs_for(index))

func get_state() -> Dictionary:
	var visible_seats: Array = []
	for index in range(seats.size()):
		var seat: Dictionary = seats[index]
		var show_cards := index == human_seat_index or bool(seat["revealed"])
		var cards_text := "—"
		var hand_name := ""
		var visible_cards: Array = []
		if not seat["cards"].is_empty():
			cards_text = HandRulesScript.cards_text(seat["cards"]) if show_cards else "?? ??"
			hand_name = str(seat["hand"]["name"]) if show_cards else ""
			if show_cards:
				visible_cards = seat["cards"].duplicate(true)
			else:
				visible_cards = [{"hidden": true}, {"hidden": true}]
		visible_seats.append({
			"name": seat["name"],
			"is_bot": seat["is_bot"],
			"chips": seat["chips"],
			"participating": seat["participating"],
			"folded": seat["folded"],
			"has_bet": seat["has_bet"],
			"last_bet": seat["last_bet"],
			"status": seat["status"],
			"cards_text": cards_text,
			"cards": visible_cards,
			"hand_name": hand_name,
			"revealed": show_cards
		})

	var max_bet := 0
	var dai_amount := 0
	if phase == "playing" and active_seat_index == human_seat_index:
		var human: Dictionary = seats[human_seat_index]
		max_bet = GameRulesScript.max_initial_bet(int(human["chips"]), pot)
		if GameRulesScript.can_dai(int(human["chips"]), pot):
			dai_amount = pot

	return {
		"phase": phase,
		"round_index": round_index,
		"active_seat_index": active_seat_index,
		"pot": pot,
		"seats": visible_seats,
		"action_log": action_log.duplicate(),
		"structured_action_history": structured_action_history.duplicate(true),
		"available_actions": get_available_actions(),
		"max_bet": max_bet,
		"dai_amount": dai_amount,
		"round_message": round_message,
		"match_message": match_message,
		"match_result": match_result,
		"bot_count": bot_count,
		"human_seat_index": human_seat_index
	}

func _create_seats() -> void:
	seats = []
	var bot_name_index := 0
	for index in range(bot_count + 1):
		if index == human_seat_index:
			seats.append(_new_seat("你", false))
		else:
			seats.append(_new_seat(BOT_NAMES[bot_name_index], true))
			bot_name_index += 1

func _seed_bot_rngs(seed_value: int) -> void:
	_bot_rngs = []
	for index in range(seats.size()):
		var bot_rng := RandomNumberGenerator.new()
		if seed_value == 0:
			bot_rng.randomize()
		else:
			bot_rng.seed = seed_value * 1009 + (index + 1) * 9176
		_bot_rngs.append(bot_rng)

func _new_seat(player_name: String, is_bot: bool) -> Dictionary:
	return {
		"name": player_name,
		"is_bot": is_bot,
		"chips": STARTING_CHIPS,
		"participating": false,
		"folded": false,
		"has_bet": false,
		"last_bet": 0,
		"last_bet_order": 0,
		"cards": [],
		"hand": {},
		"revealed": false,
		"status": "等待开局"
	}

func _start_round() -> void:
	if not _can_start_another_round():
		return

	phase = "playing"
	round_index += 1
	active_seat_index = -1
	round_message = ""
	_last_bettor_index = -1
	_bet_order = 0

	var participants := _eligible_indices()
	for index in range(seats.size()):
		var seat: Dictionary = seats[index]
		var participating := participants.has(index)
		seat["participating"] = participating
		seat["folded"] = not participating
		seat["has_bet"] = false
		seat["last_bet"] = 0
		seat["last_bet_order"] = 0
		seat["cards"] = []
		seat["hand"] = {}
		seat["revealed"] = false
		seat["status"] = "等待行动" if participating else "已淘汰"
		seats[index] = seat

	_push_log("—— 第 %d 局 ——" % round_index)
	if GameRulesScript.should_collect_ante(pot, participants.size()):
		for index in participants:
			var seat: Dictionary = seats[index]
			seat["chips"] = int(seat["chips"]) - 1
			seats[index] = seat
			pot += 1
		_push_log("%d 人补底，每人支付 1 底，底池为 %d。" % [participants.size(), pot])
	else:
		_push_log("底池为 %d，本局无需补底。" % pot)

	_deck = HandRulesScript.build_deck()
	_shuffle_deck()
	for index in participants:
		var seat: Dictionary = seats[index]
		seat["cards"] = [_deck.pop_back(), _deck.pop_back()]
		seat["hand"] = HandRulesScript.evaluate(seat["cards"])
		seats[index] = seat

	if round_index == 1 or _next_starter_index < 0:
		active_seat_index = participants[_rng.randi_range(0, participants.size() - 1)]
	else:
		active_seat_index = GameRulesScript.find_eligible_from(_next_starter_index, seats)
	_next_starter_index = -1
	_push_log("%s 先手。" % seats[active_seat_index]["name"])
	_update_active_status()
	_drive_bots_until_human_or_end()

func _can_start_another_round() -> bool:
	if seats.is_empty():
		return false
	if int(seats[human_seat_index]["chips"]) <= 0:
		_finish_match("defeat", "你的筹码已经耗尽，本次挑战结束。")
		return false

	var bot_alive := 0
	for index in range(seats.size()):
		if index == human_seat_index:
			continue
		if int(seats[index]["chips"]) > 0:
			bot_alive += 1
	if bot_alive == 0:
		_finish_match("victory", "所有 Bot 都已淘汰，你赢得了本次挑战。")
		return false
	return true

func _eligible_indices() -> Array:
	var result: Array = []
	for index in range(seats.size()):
		if int(seats[index]["chips"]) > 0:
			result.append(index)
	return result

func _legal_actions_for(index: int) -> Array:
	return BotContractScript.action_names(_legal_action_specs_for(index))

func _legal_action_specs_for(index: int) -> Array[Dictionary]:
	var seat: Dictionary = seats[index]
	return BotContractScript.legal_actions(int(seat["chips"]), pot, bool(seat["has_bet"]))

func _apply_action(index: int, action: String, amount: int = 0) -> bool:
	var legal_actions := _legal_action_specs_for(index)
	var decision := {"action": action, "amount": amount}
	if not BotContractScript.is_legal_decision(legal_actions, decision):
		return false

	var seat: Dictionary = seats[index]
	var pot_before := pot
	var chips_before := int(seat["chips"])
	var has_bet_before := bool(seat["has_bet"])
	var active_count_before := _active_indices().size()
	if action == "fold":
		seat["folded"] = true
		seat["status"] = "已弃牌"
		seats[index] = seat
		_push_log("%s 弃牌。" % seat["name"])
	elif action == "bet":
		seat["chips"] = int(seat["chips"]) - amount
		seat["has_bet"] = true
		seat["last_bet"] = amount
		_bet_order += 1
		seat["last_bet_order"] = _bet_order
		pot += amount
		_last_bettor_index = index
		var action_name := "吃" if amount == pot_before else "下注"
		seat["status"] = "%s %d" % [action_name, amount]
		seats[index] = seat
		_push_log("%s %s %d，底池变为 %d。" % [seat["name"], action_name, amount, pot])
	elif action == "check":
		seat["status"] = "过牌"
		seats[index] = seat
		_push_log("%s 过牌。" % seat["name"])
	elif action == "dai":
		if not GameRulesScript.can_dai(int(seat["chips"]), pot):
			return false
		var dai_amount := pot
		seat["chips"] = int(seat["chips"]) - dai_amount
		seat["last_bet"] = dai_amount
		_bet_order += 1
		seat["last_bet_order"] = _bet_order
		pot += dai_amount
		_last_bettor_index = index
		seat["status"] = "带 %d" % dai_amount
		seats[index] = seat
		_push_log("%s 带 %d，底池变为 %d。" % [seat["name"], dai_amount, pot])

	_record_structured_action(
		index,
		action,
		amount,
		pot_before,
		chips_before,
		has_bet_before,
		active_count_before
	)
	_advance_after_action(index)
	return true

func _advance_after_action(index: int) -> void:
	var active := _active_indices()
	if active.size() <= 1:
		_finish_single_player(active)
		return

	var next_index := _next_active_index(index)
	if next_index < 0:
		_finish_showdown()
		return
	if _last_bettor_index >= 0 and next_index == _last_bettor_index:
		_finish_showdown()
		return

	active_seat_index = next_index
	_update_active_status()

func _active_indices() -> Array:
	var result: Array = []
	for index in range(seats.size()):
		var seat: Dictionary = seats[index]
		if bool(seat["participating"]) and not bool(seat["folded"]):
			result.append(index)
	return result

func _next_active_index(from_index: int) -> int:
	for offset in range(1, seats.size() + 1):
		var index := posmod(from_index + offset, seats.size())
		var seat: Dictionary = seats[index]
		if bool(seat["participating"]) and not bool(seat["folded"]):
			return index
	return -1

func _drive_bots_until_human_or_end() -> void:
	if not _auto_drive_bots:
		return
	var safety := 0
	while phase == "playing" and active_seat_index != human_seat_index:
		safety += 1
		if safety > 500:
			push_error("Bot 行动超过安全上限，对局状态可能无法收敛")
			return
		var seat: Dictionary = seats[active_seat_index]
		var legal_actions := _legal_action_specs_for(active_seat_index)
		var decision: Dictionary
		if _bot_action_provider.is_valid():
			decision = _bot_action_provider.call(_bot_context(active_seat_index, legal_actions))
		else:
			decision = LegacyGeneBotScript.choose_action(_bot_context(active_seat_index, legal_actions))
		if not _apply_action(active_seat_index, str(decision.get("action", "")), int(decision.get("amount", 0))):
			push_error("Bot %s 返回非法动作：%s" % [seat["name"], decision])
			var legal_names := BotContractScript.action_names(legal_actions)
			var fallback_action := "fold" if legal_names.has("fold") else "check"
			_apply_action(active_seat_index, fallback_action, 0)

func _bot_context(index: int, legal_actions: Array) -> Dictionary:
	var seat: Dictionary = seats[index]
	var public_seats: Array[Dictionary] = []
	for seat_index in range(seats.size()):
		public_seats.append(BotContractScript.public_seat(seats[seat_index], seat_index))
	var observation := {
		"contract_version": BotContractScript.VERSION,
		"actor_seat": index,
		"own_cards": seat["cards"].duplicate(true),
		"own_hand_result": seat["hand"].duplicate(true),
		"pot": pot,
		"public_seats": public_seats,
		"active_seat": active_seat_index,
		"round_index": round_index,
		"structured_action_history": _current_round_history(),
		"last_bettor_seat": _last_bettor_index,
		"bet_order": _bet_order
	}
	return {
		"observation": observation,
		"legal_actions": legal_actions.duplicate(),
		"decision_seed": int(_bot_rngs[index].randi())
	}

func _current_round_history() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event in structured_action_history:
		if int(event["round_index"]) == round_index:
			result.append(event.duplicate(true))
	return result

func _record_structured_action(
	index: int,
	action: String,
	amount: int,
	pot_before: int,
	chips_before: int,
	has_bet_before: bool,
	active_count_before: int
) -> void:
	_action_sequence += 1
	structured_action_history.append({
		"round_index": round_index,
		"sequence": _action_sequence,
		"type": "action",
		"actor_seat": index,
		"action": action,
		"bet_kind": "eat" if action == "bet" and amount == pot_before else action,
		"amount": amount,
		"pot_before": pot_before,
		"pot_after": pot,
		"chips_before": chips_before,
		"chips_after": int(seats[index]["chips"]),
		"has_bet_before": has_bet_before,
		"active_player_count_before": active_count_before
	})

func _internal_round_snapshot() -> Dictionary:
	return {
		"phase": phase,
		"round_index": round_index,
		"active_seat": active_seat_index,
		"pot": pot,
		"seats": seats.duplicate(true),
		"structured_action_history": _current_round_history(),
		"last_bettor_seat": _last_bettor_index,
		"bet_order": _bet_order,
		"action_sequence": _action_sequence,
		"next_starter_seat": _next_starter_index,
		"winners": [],
		"payout": 0,
		"round_result": ""
	}

func _finish_single_player(active: Array) -> void:
	active_seat_index = -1
	if active.is_empty():
		round_message = "本局无人留在牌局中，底池保留。"
		_push_log(round_message)
		phase = "round_end"
		return

	var winner_index: int = active[0]
	var winner: Dictionary = seats[winner_index]
	_next_starter_index = winner_index

	if bool(winner["has_bet"]):
		var payout := GameRulesScript.winner_payout(pot, int(winner["last_bet"]))
		winner["chips"] = int(winner["chips"]) + payout
		pot -= payout
		winner["status"] = "打跑对手"
		round_message = "%s 打跑其他玩家，收取 %d 底。" % [winner["name"], payout]
	else:
		winner["revealed"] = true
		if HandRulesScript.is_natural(winner["hand"]):
			var payout := pot
			winner["chips"] = int(winner["chips"]) + payout
			pot = 0
			winner["status"] = "捡天水成功"
			round_message = "%s 以%s捡天水，收走全部 %d 底。" % [
				winner["name"],
				winner["hand"]["name"],
				payout
			]
		else:
			winner["status"] = "捡天水失败"
			round_message = "%s 仅有%s，捡天水失败，底池保留。" % [
				winner["name"],
				winner["hand"]["name"]
			]
	seats[winner_index] = winner
	_push_log(round_message)
	_finish_round()

func _finish_showdown() -> void:
	active_seat_index = -1
	var active := _active_indices()
	if active.is_empty():
		round_message = "无人可以比牌，底池保留。"
		_push_log(round_message)
		phase = "round_end"
		return

	for index in active:
		var seat: Dictionary = seats[index]
		seat["revealed"] = true
		seat["status"] = "亮牌：%s" % seat["hand"]["name"]
		seats[index] = seat

	var winners: Array = [active[0]]
	for position in range(1, active.size()):
		var index: int = active[position]
		var comparison := HandRulesScript.compare(seats[index]["hand"], seats[winners[0]]["hand"])
		if comparison > 0:
			winners = [index]
		elif comparison == 0:
			winners.append(index)

	if winners.size() == 1:
		var winner_index: int = winners[0]
		var winner: Dictionary = seats[winner_index]
		var payout := GameRulesScript.winner_payout(pot, int(winner["last_bet"]))
		winner["chips"] = int(winner["chips"]) + payout
		winner["status"] = "胜出：%s" % winner["hand"]["name"]
		seats[winner_index] = winner
		pot -= payout
		_next_starter_index = winner_index
		round_message = "%s 以%s胜出，收取 %d 底。" % [
			winner["name"],
			winner["hand"]["name"],
			payout
		]
	else:
		var starter_index: int = winners[0]
		for index in winners:
			if int(seats[index]["last_bet_order"]) > int(seats[starter_index]["last_bet_order"]):
				starter_index = index
		_next_starter_index = starter_index
		var names: PackedStringArray = []
		for index in winners:
			names.append(str(seats[index]["name"]))
		round_message = "%s 并列最强，本局无人收池。" % "、".join(names)

	_push_log("比牌：")
	for index in active:
		var seat: Dictionary = seats[index]
		_push_log("%s：%s（%s）" % [
			seat["name"],
			HandRulesScript.cards_text(seat["cards"]),
			seat["hand"]["name"]
		])
	_push_log(round_message)
	_finish_round()

func _finish_round() -> void:
	phase = "round_end"
	for index in range(seats.size()):
		var seat: Dictionary = seats[index]
		if bool(seat["folded"]):
			seat["status"] = "已弃牌"
		seats[index] = seat
	_can_start_another_round()

func _finish_match(result: String, message: String) -> void:
	phase = "game_over"
	active_seat_index = -1
	match_result = result
	match_message = message
	_push_log(message)

func _update_active_status() -> void:
	for index in range(seats.size()):
		var seat: Dictionary = seats[index]
		if index == active_seat_index:
			seat["status"] = "轮到行动"
		elif bool(seat["participating"]) and not bool(seat["folded"]) and str(seat["status"]) == "轮到行动":
			seat["status"] = "等待行动"
		seats[index] = seat

func _shuffle_deck() -> void:
	for index in range(_deck.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, index)
		var temporary = _deck[index]
		_deck[index] = _deck[swap_index]
		_deck[swap_index] = temporary

func _push_log(message: String) -> void:
	action_log.append(message)
	while action_log.size() > MAX_LOG_LINES:
		action_log.pop_front()
