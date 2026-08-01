extends SceneTree

const HandRulesScript = preload("res://scripts/game/hand_rules.gd")
const LegacyGeneBotScript = preload("res://scripts/game/legacy_gene_bot.gd")
const LocalGameScript = preload("res://scripts/game/local_game.gd")
const RandomBotScript = preload("res://scripts/game/random_bot.gd")

func _init() -> void:
	_test_frozen_genomes()
	_test_hand_rank()
	_test_legacy_decisions()
	_test_random_decisions()
	_test_context_hides_opponent_cards()
	print("legacy_gene_bot_test: ok")
	quit()

func _test_frozen_genomes() -> void:
	assert(LegacyGeneBotScript.HISTORICAL_GENOME != LegacyGeneBotScript.DEFAULT_GENOME)
	assert(is_equal_approx(
		float(LegacyGeneBotScript.DEFAULT_GENOME["entry_conf"]),
		0.32674856916965
	))
	assert(is_equal_approx(
		float(LegacyGeneBotScript.DEFAULT_GENOME["counter_conf"]),
		0.776025883972883
	))
	assert(is_equal_approx(
		float(LegacyGeneBotScript.DEFAULT_GENOME["greed"]),
		1.45151789486408
	))
	assert(is_equal_approx(
		float(LegacyGeneBotScript.DEFAULT_GENOME["bluff"]),
		0.00786754488945007
	))

func _test_hand_rank() -> void:
	var deck := HandRulesScript.build_deck()
	var supreme := _hand(deck, "大王", "♥3")
	var q_pair := _hand(deck, "♥Q", "♦Q")
	var weakest := _hand(deck, "♠6", "♣4")

	assert(LegacyGeneBotScript.hand_rank(supreme) == 1)
	assert(LegacyGeneBotScript.hand_rank(q_pair) == 2)
	assert(LegacyGeneBotScript.hand_rank(weakest) == 63)
	assert(is_equal_approx(LegacyGeneBotScript.estimated_win_rate(supreme, 2), 1.0))
	assert(is_equal_approx(LegacyGeneBotScript.estimated_win_rate(weakest, 2), 1.0 / 63.0))

func _test_legacy_decisions() -> void:
	var deck := HandRulesScript.build_deck()
	var rng := RandomNumberGenerator.new()
	rng.seed = 100

	var strong_context := _context(_hand(deck, "大王", "♥3"), ["fold", "bet"], rng)
	var strong := LegacyGeneBotScript.choose_action(strong_context)
	assert(strong == {"action": "bet", "amount": 10})

	var weak_context := _context(_hand(deck, "♠6", "♣4"), ["fold", "bet"], rng)
	var weak := LegacyGeneBotScript.choose_action(weak_context)
	assert(weak == {"action": "fold", "amount": 0})

	var follow_context := _context(_hand(deck, "大王", "♥3"), ["check", "dai"], rng)
	var follow := LegacyGeneBotScript.choose_action(follow_context)
	assert(follow == {"action": "dai", "amount": 10})

func _test_random_decisions() -> void:
	var deck := HandRulesScript.build_deck()
	var rng := RandomNumberGenerator.new()
	rng.seed = 200
	var context := _context(_hand(deck, "♥Q", "♦9"), ["fold", "bet"], rng)
	for index in range(20):
		var decision := RandomBotScript.choose_action(context)
		assert(str(decision["action"]) in ["fold", "bet"])
		if str(decision["action"]) == "bet":
			assert(int(decision["amount"]) >= 1 and int(decision["amount"]) <= 10)

func _test_context_hides_opponent_cards() -> void:
	var context := {}
	for seed_value in range(1, 100):
		var game = LocalGameScript.new()
		game.start_match(2, 1, seed_value)
		if game.phase == "playing" and game.active_seat_index == 0:
			context = game.get_decision_context(0)
			break

	assert(not context.is_empty())
	assert(context["cards"].size() == 2)
	assert(context["hand"] is Dictionary)
	assert(context["legal_actions"] is Array)
	assert(not context.has("seats"))
	assert(not context.has("deck"))
	assert(not context.has("opponent_cards"))

func _context(hand: Dictionary, actions: Array, rng: RandomNumberGenerator) -> Dictionary:
	return {
		"legal_actions": actions,
		"rng": rng,
		"hand": hand,
		"player_count": 2,
		"max_bet": 10,
		"pot": 10
	}

func _hand(deck: Array, first_label: String, second_label: String) -> Dictionary:
	return HandRulesScript.evaluate([
		_card(deck, first_label),
		_card(deck, second_label)
	])

func _card(deck: Array, label: String) -> Dictionary:
	for card in deck:
		if str(card["label"]) == label:
			return card
	assert(false, "找不到测试牌：%s" % label)
	return {}
