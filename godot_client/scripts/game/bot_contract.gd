class_name BotContract
extends RefCounted

const GameRulesScript = preload("res://scripts/game/game_rules.gd")

const VERSION := 1

static func legal_actions(chips: int, pot: int, has_bet: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not has_bet:
		result.append(_action_spec("fold", 0, 0, 0))
		var max_bet := GameRulesScript.max_initial_bet(chips, pot)
		if max_bet > 0:
			result.append(_action_spec("bet", 1, max_bet, -1))
		return result

	result.append(_action_spec("check", 0, 0, 0))
	if GameRulesScript.can_dai(chips, pot):
		result.append(_action_spec("dai", pot, pot, pot))
	return result

static func action_names(specs: Array) -> Array[String]:
	var result: Array[String] = []
	for spec in specs:
		result.append(str(spec["action"]))
	return result

static func find_action(specs: Array, action: String) -> Dictionary:
	for spec in specs:
		if str(spec["action"]) == action:
			return spec
	return {}

static func is_legal_decision(specs: Array, decision: Dictionary) -> bool:
	var spec := find_action(specs, str(decision.get("action", "")))
	if spec.is_empty():
		return false
	var amount := int(decision.get("amount", 0))
	var exact_amount := int(spec["exact_amount"])
	if exact_amount >= 0:
		return amount == exact_amount
	return amount >= int(spec["min_amount"]) and amount <= int(spec["max_amount"])

static func candidate_decisions(specs: Array, pot: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for spec in specs:
		var action := str(spec["action"])
		if action != "bet":
			result.append({"action": action, "amount": int(spec["exact_amount"])})
			continue

		var maximum := int(spec["max_amount"])
		var amounts: Array[int] = [
			1,
			maxi(1, roundi(float(pot) * 0.25)),
			maxi(1, roundi(float(pot) * 0.5)),
			maxi(1, roundi(float(pot) * 0.75)),
			maximum
		]
		if pot <= maximum:
			amounts.append(pot)
		amounts.sort()
		var previous := -1
		for raw_amount in amounts:
			var amount := clampi(raw_amount, int(spec["min_amount"]), maximum)
			if amount == previous:
				continue
			result.append({"action": "bet", "amount": amount})
			previous = amount
	return result

static func rng_for_context(context: Dictionary, salt: int = 0) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(context["decision_seed"]) + salt * 104729
	return rng

static func public_seat(seat: Dictionary, index: int) -> Dictionary:
	return {
		"seat_index": index,
		"name": str(seat["name"]),
		"chips": int(seat["chips"]),
		"participating": bool(seat["participating"]),
		"folded": bool(seat["folded"]),
		"has_bet": bool(seat["has_bet"]),
		"last_bet": int(seat["last_bet"]),
		"last_bet_order": int(seat["last_bet_order"])
	}

static func validate_context(context: Dictionary) -> bool:
	if not context.has("observation") or not context.has("legal_actions"):
		return false
	var observation: Dictionary = context["observation"]
	for key in [
		"contract_version",
		"actor_seat",
		"own_cards",
		"own_hand_result",
		"pot",
		"public_seats",
		"active_seat",
		"round_index",
		"structured_action_history"
	]:
		if not observation.has(key):
			return false
	return int(observation["contract_version"]) == VERSION

static func _action_spec(
	action: String,
	minimum: int,
	maximum: int,
	exact_amount: int
) -> Dictionary:
	return {
		"action": action,
		"min_amount": minimum,
		"max_amount": maximum,
		"exact_amount": exact_amount
	}
