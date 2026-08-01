class_name SearchBot
extends RefCounted

const LegacyGeneBotScript = preload("res://scripts/game/legacy_gene_bot.gd")
const RoundSimulatorScript = preload("res://scripts/game/round_simulator.gd")
const BotContractScript = preload("res://scripts/game/bot_contract.gd")

const STANDARD_BUDGET_MS := 100
const EXPERT_BUDGET_MS := 500
const DEFAULT_FIXED_SAMPLES := 12
const MAX_ROLLOUT_ACTIONS := 256
const DEFAULT_CONFIDENCE_Z := 2.5
const MINIMUM_ADVANTAGE := 0.1
const MINIMUM_DEVIATION_SAMPLES := 30
const DETERMINIZATION_CANDIDATES := 4

static func prepare() -> void:
	LegacyGeneBotScript.prepare()

static func choose_action(context: Dictionary, config: Dictionary = {}) -> Dictionary:
	return analyze(context, config)["decision"]

static func analyze(context: Dictionary, config: Dictionary = {}) -> Dictionary:
	assert(BotContractScript.validate_context(context), "SearchBot 收到无效 BotContext")
	var observation: Dictionary = context["observation"]
	var candidates := BotContractScript.candidate_decisions(context["legal_actions"], int(observation["pot"]))
	var control = config.get("control")
	var fixed_samples := int(config.get("fixed_samples", 0))
	var time_budget_ms := int(config.get("time_budget_ms", 0))
	if fixed_samples <= 0 and time_budget_ms <= 0:
		fixed_samples = DEFAULT_FIXED_SAMPLES

	var totals: Array[float] = []
	var counts: Array[int] = []
	var scores: Array[Array] = []
	for _candidate in candidates:
		totals.append(0.0)
		counts.append(0)
		scores.append([])

	var started_usec := Time.get_ticks_usec()
	var sample_index := 0
	while true:
		if fixed_samples > 0 and sample_index >= fixed_samples:
			break
		if sample_index > 0 and time_budget_ms > 0 and _elapsed_ms(started_usec) >= time_budget_ms:
			break
		if _is_cancelled(control):
			break

		var root = _determinized_root(observation, int(context["decision_seed"]), sample_index)
		for candidate_index in range(candidates.size()):
			if _is_cancelled(control):
				break
			var score := _rollout(
				root.clone(),
				candidates[candidate_index],
				int(observation["actor_seat"]),
				int(context["decision_seed"]),
				sample_index,
				control
			)
			totals[candidate_index] += score
			counts[candidate_index] += 1
			scores[candidate_index].append(score)
		if _is_cancelled(control):
			break
		sample_index += 1

	var legacy_decision := LegacyGeneBotScript.choose_action(context)
	var best_index := _best_candidate_index(candidates, totals, counts)
	var legacy_index := candidates.find(legacy_decision)
	var round_player_count := _round_player_count(observation["public_seats"])
	var confidence_z := float(config.get("confidence_z", DEFAULT_CONFIDENCE_Z))
	confidence_z *= float(maxi(1, round_player_count - 1))
	var selected_index := _confident_candidate_index(
		best_index,
		legacy_index,
		scores,
		confidence_z
	)
	var decision: Dictionary = legacy_decision
	if selected_index >= 0:
		decision = candidates[selected_index].duplicate(true)

	var candidate_stats: Array[Dictionary] = []
	for index in range(candidates.size()):
		candidate_stats.append({
			"decision": candidates[index].duplicate(true),
			"samples": counts[index],
			"average_score": totals[index] / float(counts[index]) if counts[index] > 0 else 0.0
		})
	return {
		"decision": decision,
		"stats": {
			"elapsed_ms": _elapsed_ms(started_usec),
			"completed_samples": sample_index,
			"candidate_count": candidates.size(),
			"cancelled": _is_cancelled(control),
			"used_legacy_fallback": selected_index == legacy_index or selected_index < 0,
			"candidates": candidate_stats
		}
	}

static func config_for_difficulty(difficulty: int, control = null) -> Dictionary:
	return {
		"time_budget_ms": STANDARD_BUDGET_MS if difficulty <= 2 else EXPERT_BUDGET_MS,
		"control": control
	}

static func _rollout(
	simulator,
	first_decision: Dictionary,
	search_seat: int,
	decision_seed: int,
	sample_index: int,
	control
) -> float:
	var starting_chips := int(simulator.seats[search_seat]["chips"])
	var starting_pot_share := _pot_share(simulator, search_seat, true)
	if not simulator.apply_decision(first_decision):
		return -INF

	var action_index := 0
	while simulator.phase == "playing" and action_index < MAX_ROLLOUT_ACTIONS:
		if _is_cancelled(control):
			break
		var actor := int(simulator.active_seat)
		var rollout_seed := _mixed_seed(decision_seed, sample_index, action_index + 1)
		var rollout_context: Dictionary = simulator.build_context(actor, rollout_seed)
		var decision: Dictionary = LegacyGeneBotScript.choose_action(rollout_context)
		if not simulator.apply_decision(decision):
			return -INF
		action_index += 1

	if simulator.phase != "round_end":
		return -INF
	var ending_value := float(int(simulator.seats[search_seat]["chips"]))
	ending_value += _pot_share(simulator, search_seat, false)
	return ending_value - float(starting_chips) - starting_pot_share

static func _pot_share(simulator, search_seat: int, current_round: bool) -> float:
	var candidate_count := 0
	for seat in simulator.seats:
		if current_round:
			if bool(seat["participating"]) and not bool(seat["folded"]):
				candidate_count += 1
		elif int(seat["chips"]) > 0:
			candidate_count += 1
	if candidate_count <= 0:
		return 0.0
	var search_is_eligible := (
		bool(simulator.seats[search_seat]["participating"])
		and not bool(simulator.seats[search_seat]["folded"])
	) if current_round else int(simulator.seats[search_seat]["chips"]) > 0
	if not search_is_eligible:
		return 0.0
	return float(simulator.pot) / float(candidate_count)

static func _best_candidate_index(
	candidates: Array,
	totals: Array[float],
	counts: Array[int]
) -> int:
	var best_index := -1
	var best_score := -INF
	for index in range(candidates.size()):
		if counts[index] <= 0:
			continue
		var score := totals[index] / float(counts[index])
		if score > best_score:
			best_score = score
			best_index = index
	return best_index

static func _determinized_root(observation: Dictionary, decision_seed: int, sample_index: int):
	var best_root
	var best_score := -INF
	for candidate_index in range(DETERMINIZATION_CANDIDATES):
		var seed_value := _mixed_seed(decision_seed, sample_index, candidate_index)
		var root = RoundSimulatorScript.from_observation(observation, seed_value)
		var score := _history_consistency_score(observation, root)
		if score > best_score:
			best_root = root
			best_score = score
	return best_root

static func _history_consistency_score(observation: Dictionary, simulator) -> float:
	# Check whether sampled hands plausibly explain the opponents' public actions.
	var search_seat := int(observation["actor_seat"])
	var score := 0.0
	for event in observation["structured_action_history"]:
		var actor := int(event["actor_seat"])
		if actor == search_seat or actor < 0 or actor >= simulator.seats.size():
			continue
		var hand: Dictionary = simulator.seats[actor]["hand"]
		if hand.is_empty():
			continue
		var player_count := int(event.get("active_player_count_before", 2))
		var public_seats: Array[Dictionary] = []
		for index in range(player_count):
			public_seats.append({
				"seat_index": index,
				"name": "sample",
				"chips": 100,
				"participating": true,
				"folded": false,
				"has_bet": false,
				"last_bet": 0,
				"last_bet_order": 0
			})
		var chips_before := int(event["chips_before"])
		var pot_before := int(event["pot_before"])
		var has_bet_before := bool(event.get("has_bet_before", false))
		var synthetic_observation := {
			"contract_version": BotContractScript.VERSION,
			"actor_seat": 0,
			"own_cards": simulator.seats[actor]["cards"].duplicate(true),
			"own_hand_result": hand.duplicate(true),
			"pot": pot_before,
			"public_seats": public_seats,
			"active_seat": 0,
			"round_index": int(event["round_index"]),
			"structured_action_history": [],
			"last_bettor_seat": -1,
			"bet_order": 0
		}
		var synthetic_context := {
			"observation": synthetic_observation,
			"legal_actions": BotContractScript.legal_actions(chips_before, pot_before, has_bet_before),
			"decision_seed": _mixed_seed(int(event["sequence"]), actor, 17)
		}
		var predicted := LegacyGeneBotScript.choose_action(synthetic_context)
		var observed_action := str(event["action"])
		if str(predicted["action"]) != observed_action:
			score -= 3.0
		elif observed_action == "bet" and int(predicted["amount"]) != int(event["amount"]):
			score += 0.5
		else:
			score += 2.0
	return score

static func _round_player_count(public_seats: Array) -> int:
	var count := 0
	for seat in public_seats:
		if bool(seat["participating"]):
			count += 1
	return maxi(1, count)

static func _confident_candidate_index(
	best_index: int,
	legacy_index: int,
	scores: Array[Array],
	confidence_z: float
) -> int:
	if best_index < 0 or legacy_index < 0 or best_index == legacy_index:
		return best_index
	var count := mini(scores[best_index].size(), scores[legacy_index].size())
	if count < MINIMUM_DEVIATION_SAMPLES:
		return legacy_index

	var differences: Array[float] = []
	var difference_total := 0.0
	for index in range(count):
		var difference := float(scores[best_index][index]) - float(scores[legacy_index][index])
		differences.append(difference)
		difference_total += difference
	var mean := difference_total / float(count)
	var variance_total := 0.0
	for difference in differences:
		variance_total += pow(difference - mean, 2.0)
	var variance := variance_total / float(count - 1)
	var standard_error := sqrt(variance / float(count))
	if mean > maxf(MINIMUM_ADVANTAGE, confidence_z * standard_error):
		return best_index
	return legacy_index

static func _mixed_seed(base: int, first: int, second: int) -> int:
	return base * 1000003 + first * 9176 + second * 104729 + 486187739

static func _elapsed_ms(started_usec: int) -> float:
	return float(Time.get_ticks_usec() - started_usec) / 1000.0

static func _is_cancelled(control) -> bool:
	return control != null and control.is_cancelled()
