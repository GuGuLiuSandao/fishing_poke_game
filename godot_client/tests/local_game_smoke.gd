extends SceneTree

const LocalGameScript = preload("res://scripts/game/local_game.gd")

func _init() -> void:
	var game = LocalGameScript.new()
	assert(game.get_state()["phase"] == "setup")

	game.start_match(3, 20260728)
	var initial: Dictionary = game.get_state()
	assert(initial["round_index"] == 1)
	assert(initial["seats"].size() == 4)
	assert(initial["pot"] >= 0)
	assert(int(initial["seats"][0]["chips"]) >= -1)
	assert(str(initial["seats"][0]["cards_text"]) != "?? ??")

	var completed_rounds := 0
	var safety := 0
	while completed_rounds < 20 and str(game.get_state()["phase"]) != "game_over":
		safety += 1
		assert(safety < 500)
		var state: Dictionary = game.get_state()
		_assert_invariants(state)
		match str(state["phase"]):
			"playing":
				var actions: Array = state["available_actions"]
				assert(not actions.is_empty())
				if actions.has("bet"):
					assert(game.player_action("bet", 1))
				elif actions.has("check"):
					assert(game.player_action("check"))
				else:
					assert(game.player_action("fold"))
			"round_end":
				completed_rounds += 1
				assert(game.start_next_round())
			_:
				assert(false, "出现未知阶段：%s" % state["phase"])

	assert(completed_rounds > 0)
	game.restart_match()
	var restarted: Dictionary = game.get_state()
	assert(restarted["round_index"] == 1)
	assert(restarted["seats"].size() == 4)
	assert(restarted["pot"] >= 0)

	print("local_game_smoke: ok")
	quit()

func _assert_invariants(state: Dictionary) -> void:
	assert(int(state["pot"]) >= 0)
	for seat in state["seats"]:
		assert(int(seat["chips"]) >= -1)
	if str(state["phase"]) == "playing":
		assert(int(state["active_seat_index"]) == 0)
