class_name LegacyGeneBot
extends RefCounted

const HandRulesScript = preload("res://scripts/game/hand_rules.gd")
const BotContractScript = preload("res://scripts/game/bot_contract.gd")

const HISTORICAL_GENOME := {
	"entry_conf": 0.2717162786513663,
	"counter_conf": 0.8678161596211192,
	"greed": 1.905066915604972,
	"bluff": 0.0
}

const DEFAULT_GENOME := {
	"entry_conf": 0.32674856916965,
	"counter_conf": 0.776025883972883,
	"greed": 1.45151789486408,
	"bluff": 0.00786754488945007
}

static var _rank_by_power: Dictionary = {}

static func choose_action(context: Dictionary, genome: Dictionary = DEFAULT_GENOME) -> Dictionary:
	var legal_actions: Array = context["legal_actions"]
	var action_names := BotContractScript.action_names(legal_actions)
	var observation: Dictionary = context["observation"]
	var rng := BotContractScript.rng_for_context(context)
	var player_count := _active_player_count(observation["public_seats"])
	var win_rate := estimated_win_rate(observation["own_hand_result"], player_count)

	if action_names.has("bet"):
		var should_bet := win_rate > _gene(genome, "entry_conf", 0.6, 0.0, 1.0)
		if not should_bet and win_rate < 0.3:
			should_bet = rng.randf() < _gene(genome, "bluff", 0.1, 0.0, 0.5)
		if not should_bet:
			return {"action": "fold", "amount": 0}

		var bet_spec := BotContractScript.find_action(legal_actions, "bet")
		var max_bet := int(bet_spec["max_amount"])
		var amount := 1
		if win_rate * _gene(genome, "greed", 1.5, 0.5, 3.0) > 1.0:
			amount = max_bet
		return {"action": "bet", "amount": clampi(amount, 1, max_bet)}

	if action_names.has("dai"):
		var should_dai := win_rate > _gene(genome, "counter_conf", 0.7, 0.0, 1.0)
		if not should_dai and win_rate < 0.3:
			should_dai = rng.randf() < _gene(genome, "bluff", 0.1, 0.0, 0.5) * 0.5
		if should_dai:
			var dai_spec := BotContractScript.find_action(legal_actions, "dai")
			return {"action": "dai", "amount": int(dai_spec["exact_amount"])}

	if action_names.has("check"):
		return {"action": "check", "amount": 0}
	return {"action": "fold", "amount": 0}

static func estimated_win_rate(hand_result: Dictionary, player_count: int) -> float:
	var rank := hand_rank(hand_result)
	var single_opponent_rate := float(64 - rank) / 63.0
	return pow(single_opponent_rate, maxi(1, player_count - 1))

static func hand_rank(hand_result: Dictionary) -> int:
	_ensure_rank_lookup()
	return int(_rank_by_power.get(_power_key(hand_result), 63))

static func _ensure_rank_lookup() -> void:
	if not _rank_by_power.is_empty():
		return

	var deck := HandRulesScript.build_deck()
	var unique_results := {}
	for first in range(deck.size() - 1):
		for second in range(first + 1, deck.size()):
			var result := HandRulesScript.evaluate([deck[first], deck[second]])
			unique_results[_power_key(result)] = result

	var ordered: Array = unique_results.values()
	ordered.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return HandRulesScript.compare(first, second) > 0
	)
	for index in range(ordered.size()):
		_rank_by_power[_power_key(ordered[index])] = index + 1

static func _power_key(hand_result: Dictionary) -> String:
	return "%d|%d|%d" % [
		int(hand_result["category"]),
		int(hand_result["sub_rank"]),
		int(hand_result["weight"])
	]

static func _active_player_count(public_seats: Array) -> int:
	var count := 0
	for seat in public_seats:
		if bool(seat["participating"]) and not bool(seat["folded"]):
			count += 1
	return maxi(1, count)

static func _gene(
	genome: Dictionary,
	key: String,
	fallback: float,
	minimum: float,
	maximum: float
) -> float:
	return clampf(float(genome.get(key, fallback)), minimum, maximum)
