extends SceneTree

const HandRulesScript = preload("res://scripts/game/hand_rules.gd")
const GameRulesScript = preload("res://scripts/game/game_rules.gd")

func _init() -> void:
	_test_deck()
	_test_hand_ranking()
	_test_game_rules()
	print("rules_test: ok")
	quit()

func _test_deck() -> void:
	var deck := HandRulesScript.build_deck()
	assert(deck.size() == 32)

	var labels := {}
	for card in deck:
		var label := str(card["label"])
		assert(not labels.has(label))
		labels[label] = true

	for required in ["大王", "♥3", "♥Q", "♦Q", "♠10", "♣4"]:
		assert(labels.has(required))

func _test_hand_ranking() -> void:
	var deck := HandRulesScript.build_deck()
	var supreme := HandRulesScript.evaluate([_card(deck, "大王"), _card(deck, "♥3")])
	var q_pair := HandRulesScript.evaluate([_card(deck, "♥Q"), _card(deck, "♦Q")])
	var red_eight_pair := HandRulesScript.evaluate([_card(deck, "♥8"), _card(deck, "♦8")])
	var black_eight_pair := HandRulesScript.evaluate([_card(deck, "♠8"), _card(deck, "♣8")])
	var mixed_eights := HandRulesScript.evaluate([_card(deck, "♥8"), _card(deck, "♠8")])
	var q_nine := HandRulesScript.evaluate([_card(deck, "♥Q"), _card(deck, "♦9")])
	var q_eight := HandRulesScript.evaluate([_card(deck, "♦Q"), _card(deck, "♠8")])
	var two_eight := HandRulesScript.evaluate([_card(deck, "♥2"), _card(deck, "♣8")])

	assert(int(supreme["category"]) == 14)
	assert(int(q_pair["sub_rank"]) == 100)
	assert(int(red_eight_pair["sub_rank"]) == 60)
	assert(int(black_eight_pair["sub_rank"]) == 1)
	assert(int(mixed_eights["category"]) == 6)
	assert(HandRulesScript.compare(supreme, q_pair) > 0)
	assert(HandRulesScript.compare(q_pair, q_nine) > 0)
	assert(HandRulesScript.compare(q_nine, q_eight) > 0)
	assert(HandRulesScript.compare(q_eight, two_eight) > 0)

	var q_high_nine := HandRulesScript.evaluate([_card(deck, "♥Q"), _card(deck, "♠7")])
	var two_high_nine := HandRulesScript.evaluate([_card(deck, "♥2"), _card(deck, "♣7")])
	assert(int(q_high_nine["points"]) == 9)
	assert(int(two_high_nine["points"]) == 9)
	assert(HandRulesScript.compare(q_high_nine, two_high_nine) > 0)

	var ordinary_pair_one := HandRulesScript.evaluate([_card(deck, "♥J"), _card(deck, "♦J")])
	var ordinary_pair_two := HandRulesScript.evaluate([_card(deck, "♥7"), _card(deck, "♦7")])
	assert(HandRulesScript.compare(ordinary_pair_one, ordinary_pair_two) == 0)
	assert(HandRulesScript.is_natural(HandRulesScript.evaluate([_card(deck, "♥4"), _card(deck, "♦4")])))
	assert(not HandRulesScript.is_natural(HandRulesScript.evaluate([_card(deck, "♠6"), _card(deck, "♥J")])))

func _test_game_rules() -> void:
	assert(GameRulesScript.should_collect_ante(3, 6))
	assert(not GameRulesScript.should_collect_ante(4, 6))
	assert(GameRulesScript.should_collect_ante(2, 5))
	assert(not GameRulesScript.should_collect_ante(3, 5))
	assert(GameRulesScript.max_initial_bet(0, 10) == 1)
	assert(GameRulesScript.max_initial_bet(3, 10) == 4)
	assert(GameRulesScript.max_initial_bet(-1, 10) == 0)
	assert(GameRulesScript.can_dai(9, 10))
	assert(not GameRulesScript.can_dai(8, 10))
	assert(GameRulesScript.winner_payout(50, 7) == 14)
	assert(GameRulesScript.winner_payout(8, 7) == 8)

	var seats := [
		{"chips": 0},
		{"chips": -1},
		{"chips": 4},
		{"chips": 3}
	]
	assert(GameRulesScript.find_eligible_from(0, seats) == 2)
	assert(GameRulesScript.find_eligible_from(3, seats) == 3)

func _card(deck: Array, label: String) -> Dictionary:
	for card in deck:
		if str(card["label"]) == label:
			return card
	assert(false, "找不到测试牌：%s" % label)
	return {}
