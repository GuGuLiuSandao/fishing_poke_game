extends SceneTree

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
	var round_label: Label = main.get_node(
		"RootMargin/RootVBox/Header/HeaderMargin/HeaderRow/RoundBox/Value"
	)
	assert(round_label.text == "1")

	print("ui_smoke: ok")
	quit()
