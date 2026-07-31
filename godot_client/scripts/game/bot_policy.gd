class_name BotPolicy
extends RefCounted

static func choose_action(
	legal_actions: Array,
	pot: int,
	max_bet: int,
	hand_result: Dictionary,
	difficulty: int,
	rng: RandomNumberGenerator
) -> Dictionary:
	var strength := _strength(hand_result)

	if legal_actions.has("bet"):
		var enter_threshold: float = [0.72, 0.60, 0.50][clampi(difficulty, 1, 3) - 1]
		var bluff_chance: float = [0.16, 0.10, 0.05][clampi(difficulty, 1, 3) - 1]
		if strength < enter_threshold and rng.randf() >= bluff_chance:
			return {"action": "fold", "amount": 0}

		var amount := 1
		if strength >= 0.82 and max_bet == pot:
			amount = pot
		elif strength >= 0.62:
			amount = maxi(1, mini(max_bet, floori(float(pot) / 2.0)))
		return {"action": "bet", "amount": mini(amount, max_bet)}

	if legal_actions.has("dai"):
		var dai_threshold: float = [0.84, 0.72, 0.62][clampi(difficulty, 1, 3) - 1]
		if strength >= dai_threshold:
			return {"action": "dai", "amount": pot}

	return {"action": "check", "amount": 0}

static func _strength(hand_result: Dictionary) -> float:
	var category := int(hand_result["category"])
	if category >= 13:
		return 1.0
	if category >= 10:
		return 0.92
	return clampf(float(category) / 9.0, 0.0, 1.0)
