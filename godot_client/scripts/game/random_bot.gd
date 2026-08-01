class_name RandomBot
extends RefCounted

static func choose_action(context: Dictionary) -> Dictionary:
	var legal_actions: Array = context["legal_actions"]
	var rng: RandomNumberGenerator = context["rng"]

	if legal_actions.has("bet"):
		if rng.randi_range(0, 1) == 0:
			return {"action": "fold", "amount": 0}
		return {
			"action": "bet",
			"amount": rng.randi_range(1, int(context["max_bet"]))
		}

	if legal_actions.has("dai") and rng.randi_range(0, 1) == 1:
		return {"action": "dai", "amount": int(context["pot"])}
	if legal_actions.has("check"):
		return {"action": "check", "amount": 0}
	return {"action": "fold", "amount": 0}
