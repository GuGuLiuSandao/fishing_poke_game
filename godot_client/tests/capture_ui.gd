extends SceneTree

var _output_dir: String

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_output_dir = args[0] if not args.is_empty() else OS.get_user_data_dir()
	if DirAccess.make_dir_recursive_absolute(_output_dir) != OK:
		printerr("capture_ui: cannot create %s" % _output_dir)
		quit(1)
		return
	root.size = Vector2i(1440, 810)
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main._sound_enabled = false
	await _capture("table-setup")

	main.game.start_match(3, 20260732)
	main._begin_deal()
	await _wait_for_action(main)
	await create_timer(0.30).timeout
	await _capture("table-4p")
	main.history_button.pressed.emit()
	await _capture("table-history")
	main._close_dialog()

	root.size = Vector2i(1024, 600)
	main.game.start_match(5, 20260731)
	main._begin_deal()
	await _wait_for_action(main)
	await create_timer(0.30).timeout
	await _capture("table-6p-compact")

	while main.game.phase == "playing":
		var actions: Array = main.game.get_available_actions()
		if actions.has("bet"):
			main._play_action("bet", 1)
		elif actions.has("check"):
			main._play_action("check", 0)
		await _wait_for_action(main)
	await create_timer(0.49).timeout
	await _capture("table-settlement")
	print("capture_ui: previews saved to %s" % _output_dir)
	quit()

func _wait_for_action(main) -> void:
	while main._dealing or (main.game.phase == "playing" and main.game.get_available_actions().is_empty()):
		await process_frame

func _capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(not image.is_empty())
	assert(image.save_png(_output_dir.path_join("%s.png" % name)) == OK)
