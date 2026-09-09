extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1600, 900)
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
	await RenderingServer.frame_post_draw

	_save_viewport("res://tests/table_preview_4p.png")

	main.game.start_match(5, 20260728)
	main._render()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://tests/table_preview_6p.png")

	root.size = Vector2i(1280, 720)
	main.game.start_match(3, 20260728)
	main._render()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://tests/table_preview_1280.png")

	print("capture_ui: previews saved")
	quit()

func _save_viewport(project_path: String) -> void:
	var image := root.get_texture().get_image()
	assert(not image.is_empty())
	var output_path := ProjectSettings.globalize_path(project_path)
	assert(image.save_png(output_path) == OK)
