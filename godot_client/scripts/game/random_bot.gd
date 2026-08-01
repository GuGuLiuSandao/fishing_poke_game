class_name RandomBot
extends RefCounted

const BotContractScript = preload("res://scripts/game/bot_contract.gd")

static func choose_action(context: Dictionary) -> Dictionary:
	var legal_actions: Array = context["legal_actions"]
	var action_names := BotContractScript.action_names(legal_actions)
	var rng := BotContractScript.rng_for_context(context)

	if action_names.has("bet"):
		if rng.randi_range(0, 1) == 0:
			return {"action": "fold", "amount": 0}
		var bet_spec := BotContractScript.find_action(legal_actions, "bet")
		return {
			"action": "bet",
			"amount": rng.randi_range(int(bet_spec["min_amount"]), int(bet_spec["max_amount"]))
		}

	if action_names.has("dai") and rng.randi_range(0, 1) == 1:
		var dai_spec := BotContractScript.find_action(legal_actions, "dai")
		return {"action": "dai", "amount": int(dai_spec["exact_amount"])}
	if action_names.has("check"):
		return {"action": "check", "amount": 0}
	return {"action": "fold", "amount": 0}
