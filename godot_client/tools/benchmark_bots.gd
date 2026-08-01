extends SceneTree

const BotContractScript = preload("res://scripts/game/bot_contract.gd")
const LegacyGeneBotScript = preload("res://scripts/game/legacy_gene_bot.gd")
const LocalGameScript = preload("res://scripts/game/local_game.gd")
const RandomBotScript = preload("res://scripts/game/random_bot.gd")
const SearchBotScript = preload("res://scripts/game/search_bot.gd")

const PLAYER_COUNTS := [2, 4, 6]
const FULL_SEEDS_PER_ROTATION := 2
const QUICK_SEEDS_PER_ROTATION := 2
const FULL_SEARCH_SAMPLES := 30
const QUICK_SEARCH_SAMPLES := 2
const MAX_ROUNDS_PER_MATCH := 60

var _quick := false

func _init() -> void:
	_quick = OS.get_cmdline_user_args().has("--quick")
	call_deferred("_run")

func _run() -> void:
	var seeds_per_rotation := QUICK_SEEDS_PER_ROTATION if _quick else FULL_SEEDS_PER_ROTATION
	var search_samples := QUICK_SEARCH_SAMPLES if _quick else FULL_SEARCH_SAMPLES
	var selected_opponent := ""
	var selected_player_count := 0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seeds="):
			seeds_per_rotation = maxi(1, int(argument.trim_prefix("--seeds=")))
		elif argument.begins_with("--samples="):
			search_samples = maxi(1, int(argument.trim_prefix("--samples=")))
		elif argument.begins_with("--opponent="):
			selected_opponent = argument.trim_prefix("--opponent=")
		elif argument.begins_with("--players="):
			selected_player_count = int(argument.trim_prefix("--players="))
	var rows: Array[Dictionary] = []
	print("Bot benchmark: seeds/rotation=%d search_samples=%d" % [seeds_per_rotation, search_samples])
	for opponent_kind in ["random", "legacy"]:
		if not selected_opponent.is_empty() and opponent_kind != selected_opponent:
			continue
		for player_count in PLAYER_COUNTS:
			if selected_player_count > 0 and player_count != selected_player_count:
				continue
			var baseline := _evaluate(
				opponent_kind,
				opponent_kind,
				player_count,
				seeds_per_rotation,
				search_samples
			)
			var search := _evaluate(
				"search",
				opponent_kind,
				player_count,
				seeds_per_rotation,
				search_samples
			)
			rows.append({
				"opponent": opponent_kind,
				"player_count": player_count,
				"baseline": baseline,
				"search": search
			})
			print(_comparison_text(opponent_kind, player_count, baseline, search))

	var passed := true
	var total_baseline_score := 0.0
	var total_search_score := 0.0
	var by_opponent := {}
	for row in rows:
		var baseline: Dictionary = row["baseline"]
		var search: Dictionary = row["search"]
		var opponent := str(row["opponent"])
		if not by_opponent.has(opponent):
			by_opponent[opponent] = {"baseline": 0.0, "search": 0.0, "count": 0}
		by_opponent[opponent]["baseline"] += float(baseline["average_score"])
		by_opponent[opponent]["search"] += float(search["average_score"])
		by_opponent[opponent]["count"] += 1
		total_baseline_score += float(baseline["average_score"])
		total_search_score += float(search["average_score"])
		passed = passed and int(search["illegal_actions"]) == 0
		passed = passed and int(search["hidden_information_leaks"]) == 0
	for opponent in by_opponent:
		var group: Dictionary = by_opponent[opponent]
		var improvement := float(group["search"]) - float(group["baseline"])
		print("%s aggregate improvement=%+.4f" % [opponent, improvement / int(group["count"])])
		passed = passed and improvement > 0.0

	print("aggregate score: baseline=%+.4f search=%+.4f improvement=%+.4f" % [
		total_baseline_score / rows.size(),
		total_search_score / rows.size(),
		(total_search_score - total_baseline_score) / rows.size()
	])
	print("benchmark result: %s" % ("PASS" if passed else "FAIL"))
	print("benchmark json: %s" % JSON.stringify(rows))
	quit(0 if passed else 1)

func _evaluate(
	candidate_kind: String,
	opponent_kind: String,
	player_count: int,
	seeds_per_rotation: int,
	search_samples: int
) -> Dictionary:
	var totals := _empty_totals()
	for seat_index in range(player_count):
		for seed_offset in range(seeds_per_rotation):
			var seed_value := 73000 + player_count * 1000 + seed_offset * 37
			var result := _play_match(
				candidate_kind,
				opponent_kind,
				player_count,
				seat_index,
				seed_value,
				search_samples
			)
			_accumulate(totals, result)
	return _metrics(totals)

func _play_match(
	candidate_kind: String,
	opponent_kind: String,
	player_count: int,
	candidate_seat: int,
	seed_value: int,
	search_samples: int
) -> Dictionary:
	var game = LocalGameScript.new()
	game.set_human_seat_index(candidate_seat)
	game.set_bot_action_provider(func(context: Dictionary) -> Dictionary:
		return _choose_baseline(opponent_kind, context)
	)
	game.start_match(player_count - 1, 1, seed_value)

	var action_counts := {"fold": 0, "bet": 0, "check": 0, "dai": 0}
	var illegal_actions := 0
	var hidden_leaks := 0
	var decision_count := 0
	var decision_time_total_ms := 0.0
	var decision_time_max_ms := 0.0
	var search_fallbacks := 0
	var completed_rounds := 0
	var safety := 0
	while safety < 10000:
		safety += 1
		match str(game.phase):
			"playing":
				var context: Dictionary = game.get_decision_context(candidate_seat)
				hidden_leaks += _count_hidden_leaks(context)
				var started := Time.get_ticks_usec()
				var decision: Dictionary
				if candidate_kind == "search":
					var analysis := SearchBotScript.analyze(context, {"fixed_samples": search_samples})
					decision = analysis["decision"]
					search_fallbacks += 1 if bool(analysis["stats"]["used_legacy_fallback"]) else 0
				else:
					decision = _choose_baseline(candidate_kind, context)
				var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
				decision_count += 1
				decision_time_total_ms += elapsed_ms
				decision_time_max_ms = maxf(decision_time_max_ms, elapsed_ms)
				var action := str(decision.get("action", ""))
				if action_counts.has(action):
					action_counts[action] += 1
				if not game.player_action(action, int(decision.get("amount", 0))):
					illegal_actions += 1
					break
			"round_end":
				completed_rounds = int(game.round_index)
				if completed_rounds >= MAX_ROUNDS_PER_MATCH:
					break
				game.start_next_round()
			"game_over":
				completed_rounds = int(game.round_index)
				break
			_:
				break

	var chips := int(game.seats[candidate_seat]["chips"])
	return {
		"chips": chips,
		"score": _normalized_stack_score(chips, player_count),
		"rounds": completed_rounds,
		"round_chip_change": float(chips - LocalGameScript.STARTING_CHIPS) / maxi(1, completed_rounds),
		"victory": 1 if str(game.match_result) == "victory" else 0,
		"defeat": 1 if str(game.match_result) == "defeat" else 0,
		"survived": 1 if chips > 0 else 0,
		"illegal_actions": illegal_actions,
		"hidden_information_leaks": hidden_leaks,
		"decision_count": decision_count,
		"decision_time_total_ms": decision_time_total_ms,
		"decision_time_max_ms": decision_time_max_ms,
		"search_fallbacks": search_fallbacks,
		"action_counts": action_counts
	}

func _choose_baseline(kind: String, context: Dictionary) -> Dictionary:
	if kind == "random":
		return RandomBotScript.choose_action(context)
	return LegacyGeneBotScript.choose_action(context)

func _count_hidden_leaks(context: Dictionary) -> int:
	if not BotContractScript.validate_context(context):
		return 1
	var leaks := 0
	var observation: Dictionary = context["observation"]
	for seat in observation["public_seats"]:
		if seat.has("cards") or seat.has("hand"):
			leaks += 1
	return leaks

func _normalized_stack_score(chips: int, player_count: int) -> float:
	var starting_share := 1.0 / float(player_count)
	var current_share := float(chips) / float(player_count * LocalGameScript.STARTING_CHIPS)
	if current_share >= starting_share:
		return clampf((current_share - starting_share) / (1.0 - starting_share), -1.0, 1.0)
	return clampf((current_share - starting_share) / starting_share, -1.0, 1.0)

func _empty_totals() -> Dictionary:
	return {
		"matches": 0,
		"chips": 0.0,
		"score": 0.0,
		"rounds": 0,
		"round_chip_change": 0.0,
		"victories": 0,
		"defeats": 0,
		"survived": 0,
		"illegal_actions": 0,
		"hidden_information_leaks": 0,
		"decision_count": 0,
		"decision_time_total_ms": 0.0,
		"decision_time_max_ms": 0.0,
		"search_fallbacks": 0,
		"action_counts": {"fold": 0, "bet": 0, "check": 0, "dai": 0}
	}

func _accumulate(totals: Dictionary, result: Dictionary) -> void:
	totals["matches"] += 1
	for key in [
		"chips",
		"score",
		"rounds",
		"round_chip_change",
		"illegal_actions",
		"hidden_information_leaks",
		"decision_count",
		"decision_time_total_ms",
		"search_fallbacks"
	]:
		totals[key] += result[key]
	totals["victories"] += result["victory"]
	totals["defeats"] += result["defeat"]
	totals["survived"] += result["survived"]
	totals["decision_time_max_ms"] = maxf(
		float(totals["decision_time_max_ms"]),
		float(result["decision_time_max_ms"])
	)
	for action in totals["action_counts"]:
		totals["action_counts"][action] += result["action_counts"][action]

func _metrics(totals: Dictionary) -> Dictionary:
	var matches := float(totals["matches"])
	var decisions := float(totals["decision_count"])
	return {
		"matches": int(totals["matches"]),
		"average_chips": float(totals["chips"]) / matches,
		"average_score": float(totals["score"]) / matches,
		"victory_rate": float(totals["victories"]) / matches,
		"defeat_rate": float(totals["defeats"]) / matches,
		"survival_rate": float(totals["survived"]) / matches,
		"average_survival_rounds": float(totals["rounds"]) / matches,
		"average_round_chip_change": float(totals["round_chip_change"]) / matches,
		"average_decision_ms": float(totals["decision_time_total_ms"]) / maxf(1.0, decisions),
		"max_decision_ms": float(totals["decision_time_max_ms"]),
		"search_fallback_rate": float(totals["search_fallbacks"]) / maxf(1.0, decisions),
		"illegal_actions": int(totals["illegal_actions"]),
		"hidden_information_leaks": int(totals["hidden_information_leaks"]),
		"action_counts": totals["action_counts"].duplicate(true)
	}

func _comparison_text(
	opponent: String,
	player_count: int,
	baseline: Dictionary,
	search: Dictionary
) -> String:
	return "%s %dp | baseline score=%+.4f chips=%7.2f win=%5.1f%% | search score=%+.4f chips=%7.2f win=%5.1f%% time=%.2f/%.2fms" % [
		opponent,
		player_count,
		baseline["average_score"],
		baseline["average_chips"],
		float(baseline["victory_rate"]) * 100.0,
		search["average_score"],
		search["average_chips"],
		float(search["victory_rate"]) * 100.0,
		search["average_decision_ms"],
		search["max_decision_ms"]
	]
