extends SceneTree

const LocalGameScript = preload("res://scripts/game/local_game.gd")

func _init() -> void:
	var game = LocalGameScript.new()
	var found_human_turn := false

	for seed_value in range(1, 100):
		game.start_match(1, seed_value)
		var state: Dictionary = game.get_state()
		if str(state["phase"]) == "playing" and int(state["active_seat_index"]) == 0:
			found_human_turn = true
			break

	assert(found_human_turn)
	var started: Dictionary = game.get_state()
	assert(started["available_actions"].has("bet"))
	assert(started["available_actions"].has("fold"))
	assert(not started["available_actions"].has("check"))
	assert(int(started["pot"]) == 2)
	assert(int(started["max_bet"]) == 2)
	assert(not game.player_action("check"))
	assert(not game.player_action("bet", 3))
	assert(game.player_action("bet", 1))
	assert(_has_log_fragment(game.get_state()["action_log"], "你 下注 1"))

	var after_bet: Dictionary = game.get_state()
	if str(after_bet["phase"]) == "playing":
		assert(after_bet["available_actions"].has("check"))
		assert(not after_bet["available_actions"].has("fold"))
		assert(game.player_action("check"))

	print("player_actions_smoke: ok")
	quit()

func _has_log_fragment(lines: Array, expected: String) -> bool:
	for line in lines:
		if str(line).contains(expected):
			return true
	return false
