extends SceneTree

const Hands = preload("res://scripts/game/hand_rules.gd")
const Rules = preload("res://scripts/game/game_rules.gd")
const Match = preload("res://scripts/game/local_game.gd")
const Simulator = preload("res://scripts/game/round_simulator.gd")

# These tables and fixture outcomes come from docs/rules/game-rules.md.
const DECK := [
	"大王", "♥3", "♥Q", "♦Q", "♥J", "♦J", "♥9", "♦9", "♥5", "♦5", "♥2", "♦2",
	"♥10", "♦10", "♠10", "♣10", "♥8", "♦8", "♠8", "♣8", "♥7", "♦7", "♠7", "♣7",
	"♥6", "♦6", "♠6", "♣6", "♥4", "♦4", "♠4", "♣4"
]
const POINTS := {"大王": 6, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8, "9": 9, "10": 10, "J": 11, "Q": 12}
const COLORS := {"大": "red", "♥": "red", "♦": "red", "♠": "black", "♣": "black"}
const SUITS := {"大": "JOKER", "♥": "H", "♦": "D", "♠": "S", "♣": "C"}
const WEIGHTS := {"♠10": 1, "♣10": 1, "♥4": 2, "♦4": 2, "♥8": 3, "♦8": 3, "♥2": 4, "♦2": 4, "♥Q": 5, "♦Q": 5}
const SPECIALS := {"2/8": "二八", "8/Q": "Q八", "9/Q": "Q九"}
const PAIRS := {"♣10/♠10": "黑10对", "♥4/♦4": "红4对", "♥8/♦8": "红8对", "♥2/♦2": "2对", "♥Q/♦Q": "Q对"}
const HAND_ORDER := [
	"0点", "1点", "2点", "3点", "4点", "5点", "6点", "7点", "8点", "9点",
	"二八", "Q八", "Q九", "普通对子", "黑10对", "红4对", "红8对", "2对", "Q对", "至尊"
]
const POINT_TIERS := 10
const WEIGHT_LEVELS := 6

var _deck_by_label: Dictionary = {}
var _checks := 0
var _failures := 0

func _initialize() -> void:
	_run_case("§2–3 全副牌与任意两手牌的比较", _test_hands)
	if _deck_by_label.size() == DECK.size():
		_run_case("§1、§2、§4、§6、§13 开桌、洗牌、补底、参与资格", _test_dealing)
		_run_case("§5–8、§9.1、§11、§13 顺时针、下注循环、信用与亮牌", _test_betting_cycle)
		_run_case("§1、§5、§7、§9.1 整数下注与常规收取上限", _test_amount_boundaries)
		_run_case("§9.1、§10–11 打跑其他玩家、常规结算与补底前先手", _test_uncontested)
		_run_case("§9.2、§10–11 捡天水成功与失败", _test_natural)
		_run_case("§9.3、§10–12 平局、先手顺延与淘汰", _test_tie)
		_run_case("§1、§12、§13 整场胜负、停止行动与重新开始", _test_match_end)
	else:
		_failures += 1
		printerr("规则基准：牌组不完整，依赖固定牌面的对局未运行。")

	print("规则基准：%d 次断言，%d 次失败" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _run_case(title: String, test: Callable) -> void:
	var before := _failures
	test.call()
	print("%s %s" % ["通过" if _failures == before else "失败", title])

func _expect(actual: Variant, expected: Variant, label: String) -> bool:
	_checks += 1
	if actual == expected:
		return true
	_failures += 1
	if _failures <= 20:
		printerr("%s｜预期 %s，实际 %s" % [label, str(expected), str(actual)])
	return false

func _check(condition: bool, label: String) -> void:
	_expect(condition, true, label)

func _test_hands() -> void:
	var labels: Array = []
	for card in Hands.build_deck():
		var label: String = card["label"]
		labels.append(label)
		_deck_by_label[label] = card
	var expected_labels := DECK.duplicate()
	labels.sort()
	expected_labels.sort()
	if not _expect(labels, expected_labels, "32 张实体牌（含数量、花色及牌面）"):
		_deck_by_label.clear()
		return

	for label in DECK:
		var card: Dictionary = _deck_by_label[label]
		_expect(card["value"], POINTS[_rank(label)], label + " 点数")
		_expect(card["color"], COLORS[label.left(1)], label + " 颜色")
		_expect(card["rank"], "JOKER" if label == "大王" else _rank(label), label + " 牌面")
		_expect(card["suit"], SUITS[label.left(1)], label + " 花色")

	var hands: Array[Dictionary] = []
	for first in range(DECK.size() - 1):
		for second in range(first + 1, DECK.size()):
			var a: String = DECK[first]
			var b: String = DECK[second]
			var expected := _hand_name(a, b)
			var evaluated := Hands.evaluate([_deck_by_label[a], _deck_by_label[b]])
			var tier := HAND_ORDER.find(expected)
			var key := tier * WEIGHT_LEVELS
			if tier < POINT_TIERS:
				key += maxi(WEIGHTS.get(a, 0), WEIGHTS.get(b, 0))
			var description := "%s + %s" % [a, b]
			_expect(evaluated["name"], expected, description)
			_expect(Hands.evaluate([_deck_by_label[b], _deck_by_label[a]]), evaluated, description + " 交换顺序")
			_expect(Hands.is_natural(evaluated), tier >= 8, description + " 捡天水条件")
			hands.append({"name": description, "key": key, "value": evaluated})

	for first in hands:
		for second in hands:
			var expected := signi(int(first["key"]) - int(second["key"]))
			var actual := Hands.compare(first["value"], second["value"])
			if actual == expected:
				_checks += 1
			else:
				_expect(actual, expected, "%s 比 %s" % [first["name"], second["name"]])

func _rank(label: String) -> String:
	return label if label == "大王" else label.substr(1)

func _hand_name(a: String, b: String) -> String:
	if "%s/%s" % [a, b] in ["大王/♥3", "♥3/大王"]:
		return "至尊"
	var rank_a := _rank(a)
	var rank_b := _rank(b)
	if rank_a == rank_b and COLORS[a.left(1)] == COLORS[b.left(1)]:
		return PAIRS.get(a + "/" + b, PAIRS.get(b + "/" + a, "普通对子"))
	var special: String = SPECIALS.get(rank_a + "/" + rank_b, SPECIALS.get(rank_b + "/" + rank_a, ""))
	if not special.is_empty():
		return special
	return "%d点" % ((int(POINTS[rank_a]) + int(POINTS[rank_b])) % 10)

func _test_dealing() -> void:
	var default_game := Match.new()
	_expect(default_game.bot_count, 3, "默认三名对手")
	_expect(default_game.get_state()["phase"], "setup", "未入座")
	_expect(default_game.pot, 0, "初始底数")
	_expect(default_game.player_action("bet", 1), false, "未开局不能行动")
	var thresholds := [1, 1, 2, 2, 3]
	for count in range(2, 7):
		var threshold: int = thresholds[count - 2]
		for amount in [threshold - 1, threshold, threshold + 1]:
			_expect(Rules.should_collect_ante(amount, count), amount <= threshold, "%d 人从 %d 底判断补底" % [count, amount])
			_test_next_deal(count, amount, amount <= threshold)

		var starters := {}
		var deals := {}
		var game := Match.new()
		game.set_auto_drive_bots(false)
		for seed_value in range(100, 132):
			game.start_match(count - 1, seed_value)
			var state := game.get_state()
			_expect(state["round_index"], 1, "第一局局号")
			_expect(state["seats"].size(), count, "指定桌人数")
			_expect(state["pot"], count, "每人从 100 底补 1 底")
			_expect(_stacks(game.seats), _filled(count, 99), "第一局补底后筹码")
			_expect(game.active_seat_index >= 0 and game.active_seat_index < count, true, "随机先手属于本局参与者")
			_expect(game.starter_seat_index, game.active_seat_index, "首轮先手")
			_expect(game.seats[0]["is_bot"], false, "第 0 位是真人")
			for index in range(1, count):
				_expect(game.seats[index]["is_bot"], true, "其余席位由 Bot 控制")
			_expect(game.structured_action_history, [], "开局尚未行动")
			_expect(game.start_next_round(), false, "对局中不能发下一局")
			_assert_deal(game.seats, range(count), game._deck)
			_assert_visibility(game, range(1, count), [], "开局")
			starters[game.active_seat_index] = true
			deals[_card_labels(game.seats[0]["cards"])] = true
		_expect(starters.size(), count, "%d 人不同种子覆盖全部初始先手" % count)
		_expect(deals.size() > 1, true, "%d 人不同种子产生不同手牌" % count)

func _test_next_deal(count: int, amount: int, collect: bool) -> void:
	var game := Match.new()
	game.set_auto_drive_bots(false)
	game.start_match(5, 100)
	var previous_deck := _card_labels(game._deck)
	game.phase = "round_end"
	game.pot = amount
	game._next_starter_index = 0
	var after := _filled(count, 99 if collect else 100)
	for index in range(game.seats.size()):
		var chips := 100
		if index >= count:
			chips = 0 if index % 2 == 0 else -1
			after.append(chips)
		game.seats[index]["chips"] = chips
		# Force opposite values to check the next hand resets them.
		game.seats[index]["has_bet"] = true
		game.seats[index]["last_bet"] = 7
		game.seats[index]["revealed"] = true
	var simulator = Simulator.from_snapshot(game._internal_round_snapshot())
	_expect(game.start_next_round(), true, "上一局结算后可以重新发牌")
	_expect(simulator.start_next_round(427), true, "模拟器可以重新发牌")
	var expected_pot := amount + count if collect else amount
	_expect(game.pot, expected_pot, "用有资格人数计算补底")
	_expect(simulator.pot, expected_pot, "模拟器使用相同补底规则")
	_expect(_stacks(game.seats), after, "只由有资格者补底")
	_expect(_stacks(simulator.seats), after, "模拟器只由有资格者补底")
	_expect(game.round_index, 2, "下一局编号")
	_expect(simulator.round_index, 2, "模拟器下一局编号")
	_assert_deal(game.seats, range(count), game._deck)
	_assert_deal(simulator.seats, range(count))
	if count == 6:
		_check(_card_labels(game._deck) != previous_deck, "参与者相同时也重新洗牌")
	_assert_visibility(game, range(1, count), range(count, 6), "下一局")
	for seats in [game.seats, simulator.seats]:
		for seat in seats:
			_expect([seat["has_bet"], seat["last_bet"], seat["revealed"]], [false, 0, false], "新局重置下注与亮牌")

func _assert_deal(seats: Array, eligible: Array, unused: Variant = null) -> void:
	var dealt: Array = []
	for index in range(seats.size()):
		var cards: Array = seats[index]["cards"]
		_expect(seats[index]["participating"], index in eligible, "席位 %d 的本局资格" % index)
		_expect(cards.size(), 2 if index in eligible else 0, "席位 %d 发牌张数" % index)
		for card in cards:
			var label: String = card["label"]
			_expect(label in DECK and label not in dealt, true, "发牌来自完整牌组且不重复：" + label)
			dealt.append(label)
	if unused != null:
		for card in unused:
			dealt.append(card["label"])
		dealt.sort()
		var full := DECK.duplicate()
		full.sort()
		_expect(dealt, full, "本局手牌加未使用的牌恰为完整 32 张")

func _test_betting_cycle() -> void:
	var game := _fixture([80, 90, 70, 60, 50, 40], 8, 0, [
		["♥Q", "♠8"], ["♥J", "♦J"], ["大王", "♥3"], ["♥5", "♦9"], ["♣6", "♣7"], ["♠6", "♠7"]
	])
	var sim = Simulator.from_snapshot(game._internal_round_snapshot())
	_legal(game, sim, ["fold", "bet"], 8)
	_reject(game, sim, [["check", 0], ["dai", 8], ["bet", 0], ["bet", -1], ["bet", 9], ["call", 2], ["raise", 2], ["all_in", 80]])
	_expect(game.apply_bot_decision({"action": "fold", "amount": 0}), false, "真人行动时不能替 Bot 提交")
	_step(game, sim, 0, "bet", 2, "bet", 1, 10, [78, 90, 70, 60, 50, 40])
	_expect(game.player_action("fold"), false, "Bot 行动时真人不能提交")
	_legal(game, sim, ["fold", "bet"], 10)
	_step(game, sim, 1, "bet", 10, "eat", 2, 20, [78, 80, 70, 60, 50, 40])
	_step(game, sim, 2, "fold", 0, "fold", 3, 20, [78, 80, 70, 60, 50, 40])
	_step(game, sim, 3, "bet", 3, "bet", 4, 23, [78, 80, 70, 57, 50, 40])
	_step(game, sim, 4, "bet", 4, "bet", 5, 27, [78, 80, 70, 57, 46, 40])
	_step(game, sim, 5, "fold", 0, "fold", 0, 27, [78, 80, 70, 57, 46, 40])
	_legal(game, sim, ["check", "dai"], 27)
	_reject(game, sim, [["fold", 0], ["bet", 1], ["dai", 26], ["dai", 28]])
	_step(game, sim, 0, "check", 0, "check", 1, 27, [78, 80, 70, 57, 46, 40])
	_step(game, sim, 1, "dai", 27, "dai", 3, 54, [78, 53, 70, 57, 46, 40])
	_step(game, sim, 3, "dai", 54, "dai", 4, 108, [78, 53, 70, 3, 46, 40])
	_legal(game, sim, ["check"])
	_reject(game, sim, [["dai", 47], ["dai", 108]])
	_step(game, sim, 4, "check", 0, "check", 0, 108, [78, 53, 70, 3, 46, 40])
	_step(game, sim, 0, "check", 0, "check", 1, 108, [78, 53, 70, 3, 46, 40])
	_step(game, sim, 1, "check", 0, "check", -1, 54, [78, 107, 70, 3, 46, 40])
	_settled(game, sim, "showdown", "showdown_win", [1], 54, 1, [1, 3, 4], [2, 5])
	_expect(game.start_next_round(), true, "比牌结算后开启下一局")
	_expect(game.active_seat_index, 1, "比牌赢家下一局先手")
	_expect(game.pot, 54, "剩余底数留到下一局")
	_expect(_stacks(game.seats), [78, 107, 70, 3, 46, 40], "保留筹码且不重复补底")

func _test_amount_boundaries() -> void:
	_expect(Rules.winner_payout(50, 7), 14, "仅收取最后一次下注的两倍")
	_expect(Rules.winner_payout(8, 7), 8, "收取金额不超过当前底数")
	var game := _fixture([10, 10], 5, 0, [["♥Q", "♦Q"], ["♠6", "♣4"]])
	var sim = Simulator.from_snapshot(game._internal_round_snapshot())
	_reject(game, sim, [["bet", 1.5], ["bet", "2"], ["bet", true], ["bet", INF], ["bet", NAN]])
	_step(game, sim, 0, "bet", 1, "bet", 1, 6, [9, 10])
	_reject(game, sim, [["bet", 2.5]])
	_test_credit_at_minus_one()

func _test_credit_at_minus_one() -> void:
	var credit := _fixture([3, 8, 12], 5, 0, [["♥6", "♦7"], ["♥J", "♦J"], ["♣10", "♣4"]])
	var credit_sim = Simulator.from_snapshot(credit._internal_round_snapshot())
	_legal(credit, credit_sim, ["fold", "bet"], 4)
	_reject(credit, credit_sim, [["bet", 5]])
	_step(credit, credit_sim, 0, "bet", 4, "bet", 1, 9, [-1, 8, 12])
	_step(credit, credit_sim, 1, "bet", 1, "bet", 2, 10, [-1, 7, 12])
	_step(credit, credit_sim, 2, "fold", 0, "fold", 0, 10, [-1, 7, 12])
	_legal(credit, credit_sim, ["check"])
	_reject(credit, credit_sim, [["fold", 0], ["dai", 10]])
	_step(credit, credit_sim, 0, "check", 0, "check", -1, 8, [-1, 9, 12])
	_settled(credit, credit_sim, "showdown", "showdown_win", [1], 2, 1, [1], [2], "game_over")
	_expect(credit.seats[0]["revealed"], true, "达到负 1 底仍正常比牌")

func _test_uncontested() -> void:
	var game := _fixture([0, 1], 2, 0, [["♥Q", "♦9"], ["♠6", "♣4"]])
	var sim = Simulator.from_snapshot(game._internal_round_snapshot())
	_legal(game, sim, ["fold", "bet"], 1)
	_step(game, sim, 0, "bet", 1, "bet", 1, 3, [-1, 1])
	_step(game, sim, 1, "fold", 0, "fold", -1, 1, [1, 1])
	_settled(game, sim, "uncontested", "single_bet", [0], 2, 0, [], [1])
	_expect(game.seats[0]["revealed"], false, "赢家自己的牌也不对全桌公开")
	_expect(game.start_next_round(), true, "双方各剩 1 底仍能参局")
	_expect(sim.start_next_round(417), true, "模拟器允许补底后双方都为 0 底")
	_expect(_stacks(game.seats), [0, 0], "双方补底后仍参局")
	_expect(_stacks(sim.seats), [0, 0], "模拟器补底记账")
	_expect(game.active_seat_index, 0, "原定先手补底扣到 0 底仍先手")
	_expect(game.starter_seat_index, 0, "牌桌的先手标志与实际行动者一致")
	_expect(sim.active_seat, 0, "模拟器用补底前资格确定先手")
	_assert_deal(game.seats, [0, 1], game._deck)
	if game.active_seat_index == 0 and sim.active_seat == 0:
		_legal(game, sim, ["fold", "bet"], 1)
		_step(game, sim, 0, "bet", 1, "bet", 1, 4, [-1, 0])
		_legal(game, sim, ["fold", "bet"], 1)

	var bot_win := _fixture([8, 8], 8, 1, [["♠6", "♣4"], ["♥Q", "♦9"]])
	var bot_sim = Simulator.from_snapshot(bot_win._internal_round_snapshot())
	_step(bot_win, bot_sim, 1, "bet", 1, "bet", 0, 9, [8, 7])
	_step(bot_win, bot_sim, 0, "fold", 0, "fold", -1, 7, [8, 9])
	_settled(bot_win, bot_sim, "uncontested", "single_bet", [1], 2, 1, [], [1])

func _test_natural() -> void:
	var rows := [
		[["♠6", "♥J"], 0, "natural_miss", "natural_failure"],
		[["♥J", "♦7"], 12, "natural_win", "natural_success"],
		[["♥5", "♣4"], 12, "natural_win", "natural_success"],
		[["大王", "♥3"], 12, "natural_win", "natural_success"]
	]
	for row in rows:
		var payout: int = row[1]
		var game := _fixture([100, 100, 100], 12, 2, [["♥Q", "♣6"], row[0], ["♥4", "♦4"]])
		var sim = Simulator.from_snapshot(game._internal_round_snapshot())
		_step(game, sim, 2, "fold", 0, "fold", 0, 12, [100, 100, 100])
		_step(game, sim, 0, "fold", 0, "fold", -1, 12 - payout, [100, 100 + payout, 100])
		_settled(game, sim, row[2], row[3], [1], payout, 1, [1], [2])
		_expect(game.start_next_round(), true, "捡天水结算后可以开启下一局")
		_expect(game.active_seat_index, 1, "捡天水无论成功失败均为下一局原定先手")
		_expect(game.pot, 3 if payout > 0 else 12, "捡天水后按实际余底补底")

func _test_tie() -> void:
	for initial_stack in [10, 2]:
		var game := _fixture([99, 99, initial_stack, 99], 4, 0, [
			["♥J", "♦J"], ["♥6", "♦5"], ["♥7", "♦7"], ["♠6", "♣4"]
		])
		var sim = Simulator.from_snapshot(game._internal_round_snapshot())
		_step(game, sim, 0, "bet", 1, "bet", 1, 5, [98, 99, initial_stack, 99])
		_step(game, sim, 1, "bet", 2, "bet", 2, 7, [98, 97, initial_stack, 99])
		_step(game, sim, 2, "bet", 3, "bet", 3, 10, [98, 97, initial_stack - 3, 99])
		_step(game, sim, 3, "bet", 4, "bet", 0, 14, [98, 97, initial_stack - 3, 95])
		_step(game, sim, 0, "check", 0, "check", 1, 14, [98, 97, initial_stack - 3, 95])
		_step(game, sim, 1, "check", 0, "check", 2, 14, [98, 97, initial_stack - 3, 95])
		_step(game, sim, 2, "check", 0, "check", -1, 14, [98, 97, initial_stack - 3, 95])
		_settled(game, sim, "tie", "tie", [0, 2], 0, 2, [1, 2, 3], [])
		_expect(game.start_next_round(), true, "平局后发牌")
		_expect(sim.start_next_round(430), true, "模拟器平局后发牌")
		var expected := 2 if initial_stack == 10 else 3
		_expect(game.active_seat_index, expected, "并列者最后下注优先，淘汰则顺时针顺延")
		_expect(sim.active_seat, expected, "模拟器平局先手")
		_expect(game.pot, 14, "平局无人分底或退款")
		var eligible := [0, 1, 2, 3] if initial_stack == 10 else [0, 1, 3]
		_assert_deal(game.seats, eligible, game._deck)
		_assert_deal(sim.seats, eligible)

	_expect(Rules.find_eligible_from(3, [{"chips": 1}, {"chips": 0}, {"chips": 3}, {"chips": -1}]), 0, "顺延先手可以绕回第 0 席")

func _test_match_end() -> void:
	var victory := _fixture([20, 1], 8, 0, [["♥Q", "♦Q"], ["♥4", "♦4"]])
	var sim = Simulator.from_snapshot(victory._internal_round_snapshot())
	_step(victory, sim, 0, "bet", 1, "bet", 1, 9, [19, 1])
	_step(victory, sim, 1, "bet", 2, "bet", 0, 11, [19, -1])
	_step(victory, sim, 0, "check", 0, "check", -1, 9, [21, -1])
	_settled(victory, sim, "showdown", "showdown_win", [0], 2, 0, [1], [], "game_over")
	_expect(victory.match_result, "victory", "对手全部淘汰即胜利")
	_expect(victory.pot, 9, "挑战胜利不额外分配剩余底数")
	_expect(victory.start_next_round(), false, "胜利后不能继续发牌")

	var defeat := _fixture([1, 12, 10], 6, 0, [["♠6", "♣4"], ["♥Q", "♦Q"], ["♥5", "♦5"]])
	var defeat_sim = Simulator.from_snapshot(defeat._internal_round_snapshot())
	_step(defeat, defeat_sim, 0, "bet", 1, "bet", 1, 7, [0, 12, 10])
	_step(defeat, defeat_sim, 1, "bet", 2, "bet", 2, 9, [0, 10, 10])
	_step(defeat, defeat_sim, 2, "bet", 1, "bet", 0, 10, [0, 10, 9])
	_step(defeat, defeat_sim, 0, "check", 0, "check", 1, 10, [0, 10, 9])
	_step(defeat, defeat_sim, 1, "check", 0, "check", -1, 6, [0, 14, 9])
	_settled(defeat, defeat_sim, "showdown", "showdown_win", [1], 4, 1, [1, 2], [], "game_over")
	_expect(defeat.match_result, "defeat", "真人淘汰时有多个 Bot 仍立即结束")
	_expect(defeat.start_next_round(), false, "失败后不能旁观下一局")
	_expect(defeat.step_bot_turn(), false, "挑战结束后 Bot 停止行动")
	_expect(defeat.pot, 6, "挑战失败不额外分配剩余底数")
	_assert_restart(defeat, 3)
	_assert_restart(victory, 2)
	_step_restart_mid_match(victory)

func _step_restart_mid_match(game: Match) -> void:
	var actor := game.active_seat_index
	if _expect(_apply(game, {"action": "bet", "amount": 1}), true, "重新开始前进行一次下注"):
		_expect(game.structured_action_history.back()["actor_seat"], actor, "重开前已有本场行动")
	_assert_restart(game, 2)

func _assert_restart(game: Match, count: int) -> void:
	game.restart_match()
	_expect(game.phase, "playing", "可以重新开始挑战")
	_expect(game.round_index, 1, "重置局号并发第一局")
	_expect(game.bot_count, count - 1, "重开保留对手人数")
	_expect(_stacks(game.seats), _filled(count, 99), "重置到 100 再补底")
	_expect(game.pot, count, "清空原底数再补底")
	_expect(game.structured_action_history, [], "清空先前行动")
	_expect(game.settlement, {}, "清空先前结算")
	_expect(game.match_result, "", "清空挑战结论")
	_expect(game.starter_seat_index in range(count), true, "重新选取有资格先手")
	_assert_deal(game.seats, range(count), game._deck)

func _fixture(stacks: Array, pot: int, actor: int, hands: Array) -> Match:
	var game := Match.new()
	game.set_auto_drive_bots(false)
	game.start_match(stacks.size() - 1, 351)
	game.active_seat_index = actor
	game.starter_seat_index = actor
	game.pot = pot
	for index in range(stacks.size()):
		var cards: Array = []
		for label in hands[index]:
			cards.append(_deck_by_label[label])
		var seat: Dictionary = game.seats[index]
		seat["chips"] = stacks[index]
		seat["cards"] = cards
		seat["hand"] = Hands.evaluate(cards)
	return game

func _step(
	game: Match, sim: Simulator, actor: int, action: String, amount: int,
	kind: String, next_actor: int, pot: int, stacks: Array
) -> void:
	var description := "%d 席 %s %d 底" % [actor, action, amount]
	var history_size := game.structured_action_history.size()
	var sim_history_size := sim.structured_action_history.size()
	_expect(game.active_seat_index, actor, description + " 行动者")
	_expect(sim.active_seat, actor, description + " 模拟器行动者")
	var decision := {"action": action, "amount": amount}
	var applied := _apply(game, decision)
	var simulated := sim.apply_decision(decision)
	_expect(applied, true, description + " 行动生效")
	_expect(simulated, true, description + " 模拟器行动生效")
	for state in [[game.active_seat_index, game.pot, _stacks(game.seats)], [sim.active_seat, sim.pot, _stacks(sim.seats)]]:
		_expect(state, [next_actor, pot, stacks], description + " 下一行动者、底数和各席筹码")
	if _expect(game.structured_action_history.size(), history_size + 1, description + " 仅记一次行动"):
		var event: Dictionary = game.structured_action_history.back()
		_expect([event["actor_seat"], event["bet_kind"], event["amount"]], [actor, kind, amount], description + " 行动分类与底数")
	if _expect(sim.structured_action_history.size(), sim_history_size + 1, description + " 模拟器仅记一次行动"):
		var event: Dictionary = sim.structured_action_history.back()
		_expect([event["actor_seat"], event["bet_kind"], event["amount"]], [actor, kind, amount], description + " 模拟器行动分类与底数")

func _settled(
	game: Match, sim: Simulator, kind: String, sim_kind: String, seats: Array, payout: int,
	next_starter: int, shown: Array, hidden: Array, phase: String = "round_end"
) -> void:
	_expect(game.phase, phase, kind + " 后结束本局")
	_expect(game.get_available_actions(), [], kind + " 结算后无合法动作")
	_expect(game.get_state()["settlement"], {"kind": kind, "seats": seats, "payout": payout}, kind + " 结算明细")
	_expect(sim.phase, "round_end", kind + " 模拟器结束本局")
	_expect([sim.round_result, sim.winners, sim.payout], [sim_kind, seats, payout], kind + " 模拟器结算明细")
	_expect(game._next_starter_index, next_starter, kind + " 下一局原定先手")
	_expect(sim.next_starter_seat, next_starter, kind + " 模拟器下一局原定先手")
	_assert_visibility(game, hidden, [], kind)
	var public_seats: Array = game.get_state()["seats"]
	for index in shown:
		_expect(public_seats[index]["revealed"], true, kind + " 公开未弃牌者牌面")
		_expect(_card_labels(public_seats[index]["cards"]), _card_labels(game.seats[index]["cards"]), kind + " 公开真实牌面")
	for index in hidden:
		_expect(sim.seats[index]["revealed"], false, kind + " 模拟器保密")
	for index in shown:
		_expect(sim.seats[index]["revealed"], true, kind + " 模拟器亮牌")
	var before := game.get_state()
	_expect(game.player_action("bet", 1), false, kind + " 结算完成后不能下注")
	_check(game.get_state() == before, kind + " 拒绝动作不修改结算")

func _legal(game: Match, sim: Simulator, actions: Array, amount: int = 0) -> void:
	var context := game.get_decision_context(game.active_seat_index)
	for specs in [context.get("legal_actions", []), sim.legal_actions()]:
		var names: Array = []
		for spec in specs:
			var name: String = spec["action"]
			names.append(name)
			match name:
				"bet":
					_expect([spec["min_amount"], spec["max_amount"]], [1, amount], "首动下注范围")
				"dai":
					_expect(spec["exact_amount"], amount, "带须投入固定底数")
		_expect(names, actions, "合法行动清单")
	if game.active_seat_index == game.human_seat_index:
		var state := game.get_state()
		_expect(state["available_actions"], actions, "真人界面可用动作")
		if "bet" in actions:
			_expect(state["max_bet"], amount, "真人界面下注金额上限")
		if "dai" in actions:
			_expect(state["dai_amount"], amount, "真人界面带的固定底数")

func _reject(game: Match, sim: Simulator, attempts: Array) -> void:
	var before := game.get_state()
	var sim_before := sim.snapshot()
	for attempt in attempts:
		var decision := {"action": attempt[0], "amount": attempt[1]}
		var label := "拒绝非法行动 %s %s" % attempt
		_expect(_apply(game, decision), false, label)
		_expect(sim.apply_decision(decision), false, label + "（模拟器）")
		_check(game.get_state() == before, label + " 后局面不变")
		_check(sim.snapshot() == sim_before, label + " 后模拟局面不变")

func _apply(game: Match, decision: Dictionary) -> bool:
	if game.active_seat_index == game.human_seat_index:
		return game.player_action(decision["action"], decision["amount"])
	return game.apply_bot_decision(decision)

func _assert_visibility(game: Match, hidden_seats: Array, empty_seats: Array, label: String) -> void:
	var seats: Array = game.get_state()["seats"]
	for index in hidden_seats:
		var seat: Dictionary = seats[index]
		_expect([seat["revealed"], seat["cards"], seat["hand_name"]], [false, [{"hidden": true}, {"hidden": true}], ""], label + " 隐藏其他玩家牌面与牌型")
	for index in empty_seats:
		_expect(seats[index]["cards"], [], label + " 无资格座位没有手牌")
	var own_cards: Array = game.seats[game.human_seat_index]["cards"]
	_expect(_card_labels(seats[game.human_seat_index]["cards"]), _card_labels(own_cards), label + " 真人可以看自己的牌")

func _card_labels(cards: Array) -> Array:
	var labels: Array = []
	for card in cards:
		labels.append(card.get("label", "暗牌"))
	return labels

func _stacks(seats: Array) -> Array:
	var stacks: Array = []
	for seat in seats:
		stacks.append(seat["chips"])
	return stacks

func _filled(count: int, amount: int) -> Array:
	var values: Array = []
	values.resize(count)
	values.fill(amount)
	return values
