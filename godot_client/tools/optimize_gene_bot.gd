extends SceneTree

const LocalGameScript = preload("res://scripts/game/local_game.gd")
const BotPolicyScript = preload("res://scripts/game/bot_policy.gd")
const LegacyGeneBotScript = preload("res://scripts/game/legacy_gene_bot.gd")
const RandomBotScript = preload("res://scripts/game/random_bot.gd")
const BotContractScript = preload("res://scripts/game/bot_contract.gd")

const POPULATION_SIZE := 22
const GENERATIONS := 14
const ELITE_COUNT := 4
const TRAIN_SEEDS_PER_PROFILE := 12
const VALIDATION_SEEDS_PER_PROFILE := 20
const FINAL_TEST_SEEDS_PER_PROFILE := 50
const MAX_ROUNDS_PER_MATCH := 60
const TRAIN_SEED_BASE := 31000
const VALIDATION_SEED_BASE := 91000
const FINAL_TEST_SEED_BASE := 151000

const GENE_LIMITS := {
	"entry_conf": Vector2(0.0, 1.0),
	"counter_conf": Vector2(0.0, 1.0),
	"greed": Vector2(0.5, 3.0),
	"bluff": Vector2(0.0, 0.5)
}

const OPPONENT_PROFILES := [
	{"name": "random_1v1", "kind": "random", "bot_count": 1, "difficulty": 1},
	{"name": "random_4p", "kind": "random", "bot_count": 3, "difficulty": 1},
	{"name": "policy_easy_1v1", "kind": "policy", "bot_count": 1, "difficulty": 1},
	{"name": "policy_standard_4p", "kind": "policy", "bot_count": 3, "difficulty": 2},
	{"name": "policy_expert_6p", "kind": "policy", "bot_count": 5, "difficulty": 3},
	{"name": "legacy_4p", "kind": "legacy", "bot_count": 3, "difficulty": 1}
]

const WARM_START_GENOMES := [
	{
		"entry_conf": 0.302525634877384,
		"counter_conf": 0.74252568371594,
		"greed": 1.45151789486408,
		"bluff": 0.19062261749059
	}
]

var _evolution_rng := RandomNumberGenerator.new()

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_evolution_rng.seed = 20260801
	var training_scenarios := _build_scenarios(TRAIN_SEED_BASE, TRAIN_SEEDS_PER_PROFILE)
	var validation_scenarios := _build_scenarios(VALIDATION_SEED_BASE, VALIDATION_SEEDS_PER_PROFILE)
	var final_test_scenarios := _build_scenarios(FINAL_TEST_SEED_BASE, FINAL_TEST_SEEDS_PER_PROFILE)
	var historical: Dictionary = LegacyGeneBotScript.HISTORICAL_GENOME.duplicate(true)
	if OS.get_cmdline_user_args().has("--smoke"):
		var smoke_scenarios := _build_scenarios(TRAIN_SEED_BASE, 1)
		print("GeneBot optimizer smoke: %s" % _metrics_text(_evaluate_genome(historical, smoke_scenarios)))
		quit()
		return

	print("GeneBot optimization")
	print("training scenarios=%d, validation scenarios=%d, final scenarios=%d" % [
		training_scenarios.size(),
		validation_scenarios.size(),
		final_test_scenarios.size()
	])
	var historical_training := _evaluate_genome(historical, training_scenarios)
	print("historical training: %s" % _metrics_text(historical_training))

	var population: Array[Dictionary] = [historical]
	for genome in WARM_START_GENOMES:
		population.append(genome.duplicate(true))
	while population.size() < POPULATION_SIZE:
		population.append(_random_genome())

	var best_genome := historical
	var best_fitness := -INF
	for generation in range(GENERATIONS):
		var scored := _score_population(population, training_scenarios)
		var leader: Dictionary = scored[0]
		if float(leader["fitness"]) > best_fitness:
			best_fitness = float(leader["fitness"])
			best_genome = leader["genome"].duplicate(true)
		print("generation %02d | fitness=%8.3f | %s" % [
			generation + 1,
			leader["fitness"],
			_genome_text(leader["genome"])
		])
		population = _next_generation(scored, generation)

	var best_training := _evaluate_genome(best_genome, training_scenarios)
	var historical_validation := _evaluate_genome(historical, validation_scenarios)
	var best_validation := _evaluate_genome(best_genome, validation_scenarios)
	var historical_final := _evaluate_genome(historical, final_test_scenarios)
	var best_final := _evaluate_genome(best_genome, final_test_scenarios)

	print("\nRESULT")
	print("historical genome: %s" % _genome_text(historical))
	print("optimized genome:  %s" % _genome_text(best_genome))
	print("historical training: %s" % _metrics_text(historical_training))
	print("optimized training:  %s" % _metrics_text(best_training))
	print("historical validation: %s" % _metrics_text(historical_validation))
	print("optimized validation:  %s" % _metrics_text(best_validation))
	print("historical final: %s" % _metrics_text(historical_final))
	print("optimized final:  %s" % _metrics_text(best_final))
	print("final improvement: score=%+.4f, chips=%+.3f per match" % [
		float(best_final["average_score"]) - float(historical_final["average_score"]),
		float(best_final["average_chips"]) - float(historical_final["average_chips"])
	])
	_print_profile_comparison(historical_final["profiles"], best_final["profiles"])
	print("optimized genome json: %s" % JSON.stringify(best_genome))
	quit()

func _build_scenarios(seed_base: int, seeds_per_profile: int) -> Array[Dictionary]:
	var scenarios: Array[Dictionary] = []
	for profile_index in range(OPPONENT_PROFILES.size()):
		for seed_offset in range(seeds_per_profile):
			var scenario: Dictionary = OPPONENT_PROFILES[profile_index].duplicate(true)
			scenario["seed"] = seed_base + profile_index * 1000 + seed_offset * 37
			scenarios.append(scenario)
	return scenarios

func _score_population(population: Array[Dictionary], scenarios: Array[Dictionary]) -> Array:
	var scored: Array = []
	for genome in population:
		var metrics := _evaluate_genome(genome, scenarios)
		scored.append({
			"genome": genome,
			"fitness": float(metrics["average_score"]),
			"metrics": metrics
		})
	scored.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return float(first["fitness"]) > float(second["fitness"])
	)
	return scored

func _evaluate_genome(genome: Dictionary, scenarios: Array[Dictionary]) -> Dictionary:
	var chip_total := 0.0
	var rounds_total := 0
	var victories := 0
	var defeats := 0
	var survived := 0
	var score_total := 0.0
	var profile_totals := {}
	for scenario in scenarios:
		var result := _play_match(genome, scenario)
		chip_total += float(result["chips"])
		rounds_total += int(result["rounds"])
		victories += int(result["victory"])
		defeats += int(result["defeat"])
		survived += int(result["survived"])
		score_total += float(result["score"])
		var profile_name := str(scenario["name"])
		if not profile_totals.has(profile_name):
			profile_totals[profile_name] = {"count": 0, "chips": 0.0, "score": 0.0}
		profile_totals[profile_name]["count"] += 1
		profile_totals[profile_name]["chips"] += float(result["chips"])
		profile_totals[profile_name]["score"] += float(result["score"])

	var count := float(scenarios.size())
	var profile_metrics := {}
	for profile_name in profile_totals:
		var total: Dictionary = profile_totals[profile_name]
		var profile_count := float(total["count"])
		profile_metrics[profile_name] = {
			"average_chips": float(total["chips"]) / profile_count,
			"average_score": float(total["score"]) / profile_count
		}
	return {
		"average_chips": chip_total / count,
		"average_score": score_total / count,
		"average_rounds": float(rounds_total) / count,
		"victory_rate": float(victories) / count,
		"defeat_rate": float(defeats) / count,
		"survival_rate": float(survived) / count,
		"profiles": profile_metrics
	}

func _play_match(genome: Dictionary, scenario: Dictionary) -> Dictionary:
	var game = LocalGameScript.new()
	var opponent_kind := str(scenario["kind"])
	var opponent_difficulty := int(scenario["difficulty"])
	game.set_bot_action_provider(func(context: Dictionary) -> Dictionary:
		return _opponent_action(context, opponent_kind, opponent_difficulty)
	)
	game.start_match(int(scenario["bot_count"]), opponent_difficulty, int(scenario["seed"]))

	var completed_rounds := 0
	var safety := 0
	while safety < 10000:
		safety += 1
		var phase := str(game.phase)
		if phase == "playing":
			var context: Dictionary = game.get_decision_context(0)
			var decision := LegacyGeneBotScript.choose_action(context, genome)
			if not game.player_action(str(decision["action"]), int(decision["amount"])):
				push_error("候选 GeneBot 返回非法动作：%s" % decision)
				break
		elif phase == "round_end":
			completed_rounds = int(game.round_index)
			if completed_rounds >= MAX_ROUNDS_PER_MATCH:
				break
			game.start_next_round()
		elif phase == "game_over":
			completed_rounds = int(game.round_index)
			break
		else:
			break

	if safety >= 10000:
		push_error("GeneBot 评测超过安全行动上限")

	var chips := int(game.seats[0]["chips"])
	var player_count := int(scenario["bot_count"]) + 1
	return {
		"chips": chips,
		"score": _normalized_stack_score(chips, player_count),
		"rounds": completed_rounds,
		"victory": 1 if str(game.match_result) == "victory" else 0,
		"defeat": 1 if str(game.match_result) == "defeat" else 0,
		"survived": 1 if chips > 0 else 0
	}

func _normalized_stack_score(chips: int, player_count: int) -> float:
	var starting_share := 1.0 / float(player_count)
	var current_share := float(chips) / float(player_count * LocalGameScript.STARTING_CHIPS)
	if current_share >= starting_share:
		return clampf((current_share - starting_share) / (1.0 - starting_share), -1.0, 1.0)
	return clampf((current_share - starting_share) / starting_share, -1.0, 1.0)

func _opponent_action(context: Dictionary, kind: String, difficulty: int) -> Dictionary:
	match kind:
		"random":
			return RandomBotScript.choose_action(context)
		"legacy":
			return LegacyGeneBotScript.choose_action(context)
		_:
			var observation: Dictionary = context["observation"]
			var legal_names := BotContractScript.action_names(context["legal_actions"])
			var bet_spec := BotContractScript.find_action(context["legal_actions"], "bet")
			var max_bet := int(bet_spec.get("max_amount", 0))
			return BotPolicyScript.choose_action(
				legal_names,
				int(observation["pot"]),
				max_bet,
				observation["own_hand_result"],
				difficulty,
				BotContractScript.rng_for_context(context)
			)

func _random_genome() -> Dictionary:
	var result := {}
	for key in GENE_LIMITS:
		var limits: Vector2 = GENE_LIMITS[key]
		result[key] = _evolution_rng.randf_range(limits.x, limits.y)
	return result

func _next_generation(scored: Array, generation: int) -> Array[Dictionary]:
	var next: Array[Dictionary] = []
	for index in range(ELITE_COUNT):
		next.append(scored[index]["genome"].duplicate(true))

	var progress := float(generation + 1) / float(GENERATIONS)
	var mutation_scale := lerpf(0.18, 0.025, progress)
	while next.size() < POPULATION_SIZE:
		var first := _tournament_select(scored)
		var second := _tournament_select(scored)
		var child := {}
		for key in GENE_LIMITS:
			child[key] = first[key] if _evolution_rng.randf() < 0.5 else second[key]
			if _evolution_rng.randf() < 0.45:
				var limits: Vector2 = GENE_LIMITS[key]
				var range_size := limits.y - limits.x
				child[key] = clampf(
					float(child[key]) + _evolution_rng.randfn(0.0, mutation_scale * range_size),
					limits.x,
					limits.y
				)
		next.append(child)
	return next

func _tournament_select(scored: Array) -> Dictionary:
	var winner: Dictionary = scored[_evolution_rng.randi_range(0, scored.size() - 1)]
	for draw in range(3):
		var candidate: Dictionary = scored[_evolution_rng.randi_range(0, scored.size() - 1)]
		if float(candidate["fitness"]) > float(winner["fitness"]):
			winner = candidate
	return winner["genome"]

func _genome_text(genome: Dictionary) -> String:
	return "entry=%.6f counter=%.6f greed=%.6f bluff=%.6f" % [
		genome["entry_conf"],
		genome["counter_conf"],
		genome["greed"],
		genome["bluff"]
	]

func _metrics_text(metrics: Dictionary) -> String:
	return "score=%+.4f chips=%.3f rounds=%.2f win=%.1f%% defeat=%.1f%% survive=%.1f%%" % [
		metrics["average_score"],
		metrics["average_chips"],
		metrics["average_rounds"],
		float(metrics["victory_rate"]) * 100.0,
		float(metrics["defeat_rate"]) * 100.0,
		float(metrics["survival_rate"]) * 100.0
	]

func _print_profile_comparison(historical: Dictionary, optimized: Dictionary) -> void:
	print("final test by profile:")
	for profile in OPPONENT_PROFILES:
		var name := str(profile["name"])
		var old: Dictionary = historical[name]
		var current: Dictionary = optimized[name]
		print("  %-20s old=%+.4f/%7.2f chips  new=%+.4f/%7.2f chips" % [
			name,
			old["average_score"],
			old["average_chips"],
			current["average_score"],
			current["average_chips"]
		])
