extends SceneTree

const BotContractScript = preload("res://scripts/game/bot_contract.gd")
const LocalGameScript = preload("res://scripts/game/local_game.gd")
const RoundSimulatorScript = preload("res://scripts/game/round_simulator.gd")

func _init() -> void:
	_test_contract()
	_test_structured_history_and_privacy()
	_test_clone_is_independent()
	_test_simulated_next_round()
	_test_simulator_matches_local_game()
	print("bot_foundation_test: ok")
	quit()

func _test_contract() -> void:
	var initial := BotContractScript.legal_actions(7, 10, false)
	assert(BotContractScript.action_names(initial) == ["fold", "bet"])
	var bet := BotContractScript.find_action(initial, "bet")
	assert(int(bet["min_amount"]) == 1)
	assert(int(bet["max_amount"]) == 8)
	assert(BotContractScript.is_legal_decision(initial, {"action": "bet", "amount": 8}))
	assert(not BotContractScript.is_legal_decision(initial, {"action": "bet", "amount": 9}))

	var follow := BotContractScript.legal_actions(9, 10, true)
	assert(BotContractScript.action_names(follow) == ["check", "dai"])
	assert(BotContractScript.is_legal_decision(follow, {"action": "dai", "amount": 10}))
	assert(not BotContractScript.is_legal_decision(follow, {"action": "dai", "amount": 9}))

func _test_structured_history_and_privacy() -> void:
	var game = LocalGameScript.new()
	game.set_auto_drive_bots(false)
	game.start_match(2, 301)
	var context: Dictionary = game.get_decision_context(game.active_seat_index)
	assert(BotContractScript.validate_context(context))
	var observation: Dictionary = context["observation"]
	assert(observation["own_cards"].size() == 2)
	for public_seat in observation["public_seats"]:
		assert(not public_seat.has("cards"))
		assert(not public_seat.has("hand"))

	var actor := int(game.active_seat_index)
	var decision := _aggressive_decision(context["legal_actions"])
	assert(_apply_to_local_game(game, actor, decision))
	assert(game.structured_action_history.size() == 1)
	var event: Dictionary = game.structured_action_history[0]
	for key in [
		"round_index",
		"sequence",
		"actor_seat",
		"action",
		"amount",
		"pot_before",
		"pot_after",
		"has_bet_before",
		"active_player_count_before"
	]:
		assert(event.has(key))
	assert(int(event["actor_seat"]) == actor)

func _test_clone_is_independent() -> void:
	var game = LocalGameScript.new()
	game.set_auto_drive_bots(false)
	game.start_match(2, 302)
	var simulator = RoundSimulatorScript.from_snapshot(game._internal_round_snapshot())
	var cloned = simulator.clone()
	assert(cloned.state_hash() == simulator.state_hash())
	var original_pot := int(simulator.pot)
	assert(cloned.apply_decision(_aggressive_decision(cloned.legal_actions())))
	assert(simulator.pot == original_pot)
	assert(cloned.state_hash() != simulator.state_hash())

func _test_simulated_next_round() -> void:
	var game = LocalGameScript.new()
	game.set_auto_drive_bots(false)
	game.start_match(3, 303)
	var simulator = RoundSimulatorScript.from_snapshot(game._internal_round_snapshot())
	var original_total := _simulator_total(simulator)
	while simulator.phase == "playing":
		var names := BotContractScript.action_names(simulator.legal_actions())
		var decision := {"action": "fold", "amount": 0}
		if not names.has("fold"):
			decision = {"action": "check", "amount": 0}
		assert(simulator.apply_decision(decision))
	var finished_round := int(simulator.round_index)
	assert(simulator.start_next_round(9001))
	assert(simulator.phase == "playing")
	assert(simulator.round_index == finished_round + 1)
	assert(_simulator_total(simulator) == original_total)
	var seen_cards := {}
	for seat in simulator.seats:
		if bool(seat["participating"]):
			assert(seat["cards"].size() == 2)
			for card in seat["cards"]:
				assert(not seen_cards.has(card["label"]))
				seen_cards[card["label"]] = true

func _test_simulator_matches_local_game() -> void:
	for seed_value in range(410, 430):
		var game = LocalGameScript.new()
		game.set_auto_drive_bots(false)
		game.start_match(3, seed_value)
		var simulator = RoundSimulatorScript.from_snapshot(game._internal_round_snapshot())
		var safety := 0
		while game.phase == "playing":
			safety += 1
			assert(safety < 100)
			assert(simulator.active_seat == game.active_seat_index)
			var actor := int(game.active_seat_index)
			var decision := _comparison_decision(simulator.legal_actions(), seed_value + safety)
			assert(simulator.apply_decision(decision))
			assert(_apply_to_local_game(game, actor, decision))
			_assert_same_public_state(game, simulator)
		assert(simulator.phase == "round_end")
func _apply_to_local_game(game, actor: int, decision: Dictionary) -> bool:
	if actor == 0:
		return game.player_action(str(decision["action"]), int(decision["amount"]))
	return game.apply_bot_decision(decision)

func _aggressive_decision(specs: Array) -> Dictionary:
	var bet := BotContractScript.find_action(specs, "bet")
	if not bet.is_empty():
		return {"action": "bet", "amount": int(bet["max_amount"])}
	var dai := BotContractScript.find_action(specs, "dai")
	if not dai.is_empty():
		return {"action": "dai", "amount": int(dai["exact_amount"])}
	var check := BotContractScript.find_action(specs, "check")
	if not check.is_empty():
		return {"action": "check", "amount": 0}
	return {"action": "fold", "amount": 0}

func _comparison_decision(specs: Array, selector: int) -> Dictionary:
	var names := BotContractScript.action_names(specs)
	if names.has("bet"):
		if selector % 5 == 0:
			return {"action": "fold", "amount": 0}
		var bet := BotContractScript.find_action(specs, "bet")
		var amount := int(bet["max_amount"]) if selector % 2 == 0 else int(bet["min_amount"])
		return {"action": "bet", "amount": amount}
	if names.has("dai") and selector % 2 == 0:
		return {"action": "dai", "amount": int(BotContractScript.find_action(specs, "dai")["exact_amount"])}
	return {"action": "check", "amount": 0}

func _assert_same_public_state(game, simulator) -> void:
	if simulator.phase == "round_end":
		assert(game.phase in ["round_end", "game_over"])
	else:
		assert(simulator.phase == game.phase)
	assert(simulator.active_seat == game.active_seat_index)
	assert(simulator.pot == game.pot)
	assert(simulator.last_bettor_seat == game._last_bettor_index)
	assert(simulator.bet_order == game._bet_order)
	assert(simulator.structured_action_history == game._current_round_history())
	for index in range(game.seats.size()):
		for key in ["chips", "participating", "folded", "has_bet", "last_bet", "last_bet_order", "revealed"]:
			assert(simulator.seats[index][key] == game.seats[index][key])
	if game.phase == "round_end":
		assert(simulator.next_starter_seat == game._next_starter_index)

func _simulator_total(simulator) -> int:
	var total := int(simulator.pot)
	for seat in simulator.seats:
		total += int(seat["chips"])
	return total
