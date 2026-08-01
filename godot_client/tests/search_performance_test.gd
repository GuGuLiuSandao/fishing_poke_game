extends SceneTree

const BotContractScript = preload("res://scripts/game/bot_contract.gd")
const LocalGameScript = preload("res://scripts/game/local_game.gd")
const SearchBotScript = preload("res://scripts/game/search_bot.gd")

func _init() -> void:
	for player_count in [2, 4, 6]:
		_test_budget(player_count)
	print("search_performance_test: ok")
	quit()

func _test_budget(player_count: int) -> void:
	var game = LocalGameScript.new()
	game.set_deferred_search_mode(true)
	game.start_match(player_count - 1, 2, 88000 + player_count)
	var context: Dictionary = game.get_decision_context(game.active_seat_index)

	var standard := SearchBotScript.analyze(context, {"time_budget_ms": 100})
	var expert := SearchBotScript.analyze(context, {"time_budget_ms": 500})
	assert(BotContractScript.is_legal_decision(context["legal_actions"], standard["decision"]))
	assert(BotContractScript.is_legal_decision(context["legal_actions"], expert["decision"]))
	assert(int(standard["stats"]["completed_samples"]) > 0)
	assert(int(expert["stats"]["completed_samples"]) >= int(standard["stats"]["completed_samples"]))
	assert(float(standard["stats"]["elapsed_ms"]) < 350.0)
	assert(float(expert["stats"]["elapsed_ms"]) < 850.0)
	print("  %dp standard=%.1fms/%d samples expert=%.1fms/%d samples" % [
		player_count,
		standard["stats"]["elapsed_ms"],
		standard["stats"]["completed_samples"],
		expert["stats"]["elapsed_ms"],
		expert["stats"]["completed_samples"]
	])
