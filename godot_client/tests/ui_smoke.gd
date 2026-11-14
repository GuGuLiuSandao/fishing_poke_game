extends SceneTree

const HandRulesScript = preload("res://scripts/game/hand_rules.gd")
const CardBack = preload("res://assets/cards/card_back.png")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main._sound_enabled = false
	main._motion_enabled = false
	create_timer(10.0).timeout.connect(func() -> void:
		printerr("ui_smoke: timed out")
		quit(1)
	)
	await process_frame
	assert(main.start_button.is_visible_in_tree())
	main.start_button.pressed.emit()
	assert(main.game.get_state()["seats"].size() == 4)
	main._bot_timer.stop()

	for card in HandRulesScript.build_deck():
		var texture: Texture2D = main.table.texture_for_card(card)
		assert(texture != null and texture != CardBack)

	await _test_layout(main)
	_test_peek_and_actions(main)
	_test_keyboard(main)
	_test_history_pause(main)
	_test_settlement(main)
	_test_staged_bot_turns(main)
	print("ui_smoke: ok")
	quit()

func _test_layout(main) -> void:
	root.size = Vector2i(1024, 600)
	for bot_count in range(1, 6):
		main.game.start_match(bot_count, 20260731)
		main._render()
		await process_frame
		await process_frame
		var views: Array = main.table.views
		assert(views.size() == bot_count + 1)
		var viewport: Rect2 = main.get_global_rect()
		var bar: Rect2 = main.action_bar.get_global_rect()
		assert(viewport.encloses(bar))
		var placed: Array[Rect2] = []
		for view in views:
			var plate: Rect2 = view._plate.get_global_rect()
			assert(viewport.encloses(plate) and not bar.intersects(plate))
			for other in placed:
				assert(not plate.intersects(other))
			placed.append(plate)
			for card in view.cards:
				var bounds: Rect2 = card.get_global_rect()
				assert(viewport.encloses(bounds) and not bar.intersects(bounds))
				if card.visible:
					assert(card.texture != null)
					if view != views[0]:
						assert(card.texture == CardBack)
		for button in [main.history_button, main.rules_button, main.settings_button, main.restart_button]:
			assert(viewport.encloses(button.get_global_rect()))

func _test_peek_and_actions(main) -> void:
	main._manual_peek = true
	main._hand_open = false
	_force_human_turn(main, 10, 100, false)
	var player = main.table.views[0]
	var bar = main.action_bar
	assert(player.open_button.is_visible_in_tree())
	assert(player.cards[0].texture == CardBack)
	assert(player.cards[0].tooltip_text == "牌背")
	var before: Dictionary = main.game.get_state()
	player.open_button.pressed.emit()
	assert(player.cards[0].texture != CardBack)
	assert(not player.open_button.is_visible_in_tree())
	assert(main.game.get_state() == before)

	assert(bar.fold_button.is_visible_in_tree())
	assert(bar.amount_input.text.is_empty() and bar.bet_button.disabled)
	assert(not bar.check_button.is_visible_in_tree())
	assert(not bar.dai_button.is_visible_in_tree())
	bar.slider.drag_ended.emit(false)
	assert(bar.amount_input.text == "1" and not bar.bet_button.disabled)
	bar.slider.value = 3
	assert(bar.amount_input.text == "3")
	assert(bar.bet_button.text == "下注  3 底")
	assert(main.game.get_state() == before)
	for invalid in ["", "0", "-1", "1.5", "11", "下注"]:
		_type_bet(bar.amount_input, invalid)
		assert(bar.bet_button.disabled)
		assert(main.game.get_state() == before)
	_type_bet(bar.amount_input, "7")
	assert(not bar.bet_button.disabled and bar.slider.value == 7)
	_type_bet(bar.amount_input, "10")
	assert(bar.bet_button.text == "吃  10 底")
	assert(main.game.get_state() == before)
	bar.bet_button.pressed.emit()
	assert(main.game.structured_action_history.back()["bet_kind"] == "eat")
	assert(int(main.game.pot) == 20)
	main._bot_timer.stop()

	_force_human_turn(main, 20, 2, false)
	assert(bar.slider.max_value == 3)
	assert(bar.bet_button.disabled)
	_type_bet(bar.amount_input, "3")
	assert(bar.bet_button.text == "下注  3 底")
	bar.bet_button.pressed.emit()
	assert(main.game.structured_action_history.back()["bet_kind"] == "bet")
	assert(main.game.seats[0]["chips"] == -1)
	main._bot_timer.stop()

	_force_human_turn(main, 20, 2, true)
	assert(bar.check_button.is_visible_in_tree())
	assert(not bar.dai_button.is_visible_in_tree())
	assert(not bar.fold_button.is_visible_in_tree())
	assert(not bar.amount_input.is_visible_in_tree())
	_force_human_turn(main, 20, 19, true)
	assert(bar.dai_button.is_visible_in_tree() and bar.dai_button.text == "带  20 底")
	bar.dai_button.pressed.emit()
	assert(main.game.structured_action_history.back()["amount"] == 20)
	assert(main.game.seats[0]["chips"] == -1)
	main._bot_timer.stop()

	_force_human_turn(main, 20, 0, false)
	assert(not bar.slider.editable and bar.bet_button.disabled)
	_type_bet(bar.amount_input, "1")
	assert(bar.bet_button.text == "下注  1 底")

func _type_bet(field: LineEdit, value: String) -> void:
	field.text = value
	field.text_changed.emit(value)

func _force_human_turn(main, pot: int, chips: int, has_bet: bool) -> void:
	main.game.start_match(3, 20260731)
	main.game.active_seat_index = 0
	main.game.pot = pot
	main.game.seats[0]["chips"] = chips
	main.game.seats[0]["has_bet"] = has_bet
	main._render()

func _test_history_pause(main) -> void:
	main.game.active_seat_index = 1
	main._render()
	main._schedule_bot()
	assert(not main._bot_timer.is_stopped())
	main.history_button.pressed.emit()
	assert(main._overlay.visible and main._bot_timer.is_stopped())
	assert(not main._history.text.is_empty())
	main._dialog_close.pressed.emit()
	assert(not main._overlay.visible and not main._bot_timer.is_stopped())
	main._bot_timer.stop()

func _test_keyboard(main) -> void:
	_force_human_turn(main, 9, 100, false)
	main._focus_for_turn()
	var slider: HSlider = main.action_bar.slider
	assert(slider.has_focus() and main.action_bar._slider_focus.visible)
	_press_key(KEY_RIGHT)
	assert(slider.value == 2)

	main.settings_button.pressed.emit()
	assert(main._dialog_close.has_focus())
	_press_key(KEY_TAB, true)
	var focussed := root.gui_get_focus_owner()
	assert(focussed is Button and focussed.accessibility_name == "每局手动看牌")
	_press_key(KEY_TAB)
	assert(main._dialog_close.has_focus())
	_press_key(KEY_ESCAPE)
	assert(not main._overlay.visible and slider.has_focus())

func _press_key(key: Key, backward: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	event.shift_pressed = backward
	root.push_input(event, true)

func _test_settlement(main) -> void:
	var game = main.game
	game.start_match(3, 20260731)
	game.pot = 23
	game.seats[1]["has_bet"] = true
	game.seats[1]["last_bet"] = 3
	game.seats[0]["folded"] = true
	game.seats[2]["folded"] = true
	game.seats[3]["folded"] = true
	game._finish_single_player([1])
	main._render()
	assert(int(game.pot) == 17)
	assert(main.table.result_title.text == "阿浪赢得本局")
	assert(main.table.result_meta.text.contains("17 底"))
	assert(main.table.views[1].cards[0].texture == CardBack)
	assert(not main.table.views[2].cards[0].visible)
	assert(main.action_bar.next_button.is_visible_in_tree())

	game.start_match(3, 20260731)
	game.seats[0]["folded"] = true
	game.seats[1]["has_bet"] = true
	game.seats[1]["last_bet"] = 3
	game._finish_showdown()
	main._render()
	assert(main.table.views[1].cards[0].texture != CardBack)
	assert(main.table.views[2].cards[0].texture != CardBack)
	assert(main.table.views[3].cards[0].texture != CardBack)

	_test_special_settlements(main)
	game.start_match(1, 20260731)
	game.seats[0]["chips"] = 0
	game.seats[0]["folded"] = true
	game._finish_single_player([1])
	main._render()
	assert(main.table.result_title.text == "挑战失败")
	assert(main.action_bar.restart_button.is_visible_in_tree())

func _test_special_settlements(main) -> void:
	var game = main.game
	game.start_match(1, 20260731)
	game.pot = 13
	_set_cards(game.seats[1], ["♥J", "♦7"])
	game.seats[0]["folded"] = true
	game._finish_single_player([1])
	main._render()
	assert(main.table.result_title.text == "捡天水成功")
	assert(main.table.result_detail.text.contains("13 底"))
	assert(main.table.views[1].cards[0].texture != CardBack)

	game.start_match(1, 20260731)
	game.pot = 13
	_set_cards(game.seats[1], ["♠6", "♣4"])
	game.seats[0]["folded"] = true
	game._finish_single_player([1])
	main._render()
	assert(main.table.result_title.text == "捡天水失败")
	assert(main.table.result_meta.text.contains("13 底"))
	assert(main.table.views[1].cards[0].texture != CardBack)

	game.start_match(1, 20260731)
	game.pot = 13
	_set_cards(game.seats[0], ["♥J", "♦J"])
	_set_cards(game.seats[1], ["♥7", "♦7"])
	game._finish_showdown()
	main._render()
	assert(main.table.result_title.text == "平局")
	assert(main.table.result_meta.text.contains("13 底"))
	assert(main.table.views[1].cards[0].texture != CardBack)

func _set_cards(seat: Dictionary, labels: Array) -> void:
	var cards: Array = []
	for card in HandRulesScript.build_deck():
		if card["label"] in labels:
			cards.append(card)
	seat["cards"] = cards
	seat["hand"] = HandRulesScript.evaluate(cards)

func _test_staged_bot_turns(main) -> void:
	const LocalGameScript = preload("res://scripts/game/local_game.gd")
	for bot_count in [1, 3, 5]:
		for fixed_seed in range(20260731, 20260736):
			var auto := LocalGameScript.new()
			auto.start_match(bot_count, fixed_seed)
			main.game.start_match(bot_count, fixed_seed)
			assert(main.game.structured_action_history.is_empty())
			while main.game.phase == "playing" and main.game.get_available_actions().is_empty():
				var history_size: int = main.game.structured_action_history.size()
				main._step_bot()
				assert(main.game.structured_action_history.size() == history_size + 1)
			main._bot_timer.stop()
			assert(main.game.get_state() == auto.get_state())
