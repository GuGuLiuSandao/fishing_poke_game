extends SceneTree

const LocalGameScript = preload("res://scripts/game/local_game.gd")
const HandRulesScript = preload("res://scripts/game/hand_rules.gd")

func _init() -> void:
	_test_fold_win()
	_test_natural_success()
	_test_natural_failure()
	_test_showdown_winner()
	_test_showdown_tie()
	print("settlement_test: ok")
	quit()

func _test_fold_win() -> void:
	var game = _game_with_two_seats()
	game.pot = 20
	game.seats[0] = _seat("你", false, 90, true, false, true, 3, 1, _hand(["♥6", "♥3"]))
	game.seats[1] = _seat("Bot", true, 90, true, true, false, 0, 0, _hand(["♥J", "♦4"]))
	game._finish_single_player([0])

	assert(int(game.pot) == 14)
	assert(int(game.seats[0]["chips"]) == 96)
	assert(not bool(game.seats[0]["revealed"]))
	assert(game.phase == "round_end")

func _test_natural_success() -> void:
	var game = _game_with_two_seats()
	game.pot = 12
	game.seats[0] = _seat("你", false, 1, true, false, false, 0, 0, _hand(["♥J", "♦7"]))
	game.seats[1] = _seat("Bot", true, 90, true, true, false, 0, 0, _hand(["♥6", "♥3"]))
	game._finish_single_player([0])

	assert(int(game.pot) == 0)
	assert(int(game.seats[0]["chips"]) == 13)
	assert(bool(game.seats[0]["revealed"]))
	assert(str(game.seats[0]["status"]) == "捡天水成功")

func _test_natural_failure() -> void:
	var game = _game_with_two_seats()
	game.pot = 12
	game.seats[0] = _seat("你", false, 2, true, false, false, 0, 0, _hand(["♠6", "♣4"]))
	game.seats[1] = _seat("Bot", true, 90, true, true, false, 0, 0, _hand(["♥J", "♦4"]))
	game._finish_single_player([0])

	assert(int(game.pot) == 12)
	assert(int(game.seats[0]["chips"]) == 2)
	assert(bool(game.seats[0]["revealed"]))
	assert(str(game.seats[0]["status"]) == "捡天水失败")

func _test_showdown_winner() -> void:
	var game = _game_with_two_seats()
	game.pot = 24
	game.seats[0] = _seat("你", false, 80, true, false, true, 2, 1, _hand(["♥Q", "♦9"]))
	game.seats[1] = _seat("Bot", true, 80, true, false, true, 7, 2, _hand(["♥2", "♣8"]))
	game._finish_showdown()

	assert(int(game.pot) == 20)
	assert(int(game.seats[0]["chips"]) == 84)
	assert(bool(game.seats[0]["revealed"]))
	assert(bool(game.seats[1]["revealed"]))
	assert(int(game._next_starter_index) == 0)

func _test_showdown_tie() -> void:
	var game = _game_with_two_seats()
	game.pot = 24
	game.seats[0] = _seat("你", false, 80, true, false, true, 2, 1, _hand(["♥J", "♦J"]))
	game.seats[1] = _seat("Bot", true, 80, true, false, true, 7, 2, _hand(["♥7", "♦7"]))
	game._finish_showdown()

	assert(int(game.pot) == 24)
	assert(int(game.seats[0]["chips"]) == 80)
	assert(int(game.seats[1]["chips"]) == 80)
	assert(int(game._next_starter_index) == 1)
	assert(str(game.round_message).contains("并列最强"))

func _game_with_two_seats():
	var game = LocalGameScript.new()
	game.bot_count = 1
	game.round_index = 1
	game.phase = "playing"
	var empty_logs: Array[String] = []
	game.action_log = empty_logs
	game.seats = [
		_seat("你", false, 100, true, false, false, 0, 0, _hand(["♥Q", "♦9"])),
		_seat("Bot", true, 100, true, false, false, 0, 0, _hand(["♥2", "♣8"]))
	]
	return game

func _seat(
	player_name: String,
	is_bot: bool,
	chips: int,
	participating: bool,
	folded: bool,
	has_bet: bool,
	last_bet: int,
	last_bet_order: int,
	hand_data: Dictionary
) -> Dictionary:
	return {
		"name": player_name,
		"is_bot": is_bot,
		"chips": chips,
		"participating": participating,
		"folded": folded,
		"has_bet": has_bet,
		"last_bet": last_bet,
		"last_bet_order": last_bet_order,
		"cards": hand_data["cards"],
		"hand": hand_data["result"],
		"revealed": false,
		"status": "等待行动"
	}

func _hand(labels: Array) -> Dictionary:
	var deck := HandRulesScript.build_deck()
	var cards: Array = []
	for label in labels:
		for card in deck:
			if str(card["label"]) == str(label):
				cards.append(card)
				break
	assert(cards.size() == 2)
	return {"cards": cards, "result": HandRulesScript.evaluate(cards)}
