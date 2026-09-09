extends SceneTree

const HandRulesScript = preload("res://scripts/game/hand_rules.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn")
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var start_button: Button = main.get_node(
		"RootMargin/RootVBox/Content/Sidebar/SideMargin/SideVBox/SetupPanel/StartButton"
	)
	start_button.emit_signal("pressed")
	await process_frame
	await process_frame

	var seat_layer: Control = main.get_node(
		"RootMargin/RootVBox/Content/TableWrap/TableArea/SeatLayer"
	)
	assert(seat_layer.get_child_count() == 4)
	var state: Dictionary = main.game.get_state()
	assert(state["seats"][0]["cards"].size() == 2)
	assert(not bool(state["seats"][0]["cards"][0].get("hidden", false)))
	for seat_index in range(1, state["seats"].size()):
		if not bool(state["seats"][seat_index]["revealed"]):
			assert(bool(state["seats"][seat_index]["cards"][0].get("hidden", false)))
			assert(not state["seats"][seat_index]["cards"][0].has("rank"))
	var human_cards: Array = main.seat_views[0]["cards"]
	assert(human_cards[0].texture != null)
	assert(human_cards[1].texture != null)
	for card in HandRulesScript.build_deck():
		var card_texture: Texture2D = main._texture_for_card(card)
		assert(card_texture != null)
		assert(card_texture.resource_path != "res://assets/cards/card_back.png")
	var round_label: Label = main.get_node(
		"RootMargin/RootVBox/Header/HeaderMargin/HeaderRow/RoundBox/Value"
	)
	assert(round_label.text == "1")

	print("ui_smoke: ok")
	quit()
