extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame

	var found_bot_start := false
	for seed_value in range(1, 100):
		main._cancel_searches()
		main.game.start_match(5, 3, seed_value)
		if main.game.needs_search_bot_action():
			found_bot_start = true
			break
	if not _require(found_bot_start, "没有找到 Bot 先手的固定种子"):
		return
	main._render()
	await process_frame
	if not _require(main._has_current_search(), "老练 SearchBot 后台任务没有启动"):
		return

	var old_pending: Dictionary
	for pending in main._pending_searches:
		if int(pending["generation"]) == main._search_generation:
			old_pending = pending
			break
	if not _require(not old_pending.is_empty(), "找不到正在运行的搜索任务"):
		return
	var old_task_id := int(old_pending["task_id"])
	var old_control = old_pending["control"]

	var started_usec := Time.get_ticks_usec()
	main._on_restart_pressed()
	var restart_ms := float(Time.get_ticks_usec() - started_usec) / 1000.0
	if not _require(restart_ms < 50.0, "重新开始被旧搜索阻塞了 %.2fms" % restart_ms):
		return
	if not _require(old_control.is_cancelled(), "重新开始没有取消旧搜索"):
		return
	if not _require(int(main.game.round_index) == 1, "重新开始没有立即创建新挑战"):
		return

	var cancellation_started := Time.get_ticks_msec()
	while not WorkerThreadPool.is_task_completed(old_task_id):
		if not _require(Time.get_ticks_msec() - cancellation_started < 500, "旧搜索取消后 500ms 内仍未退出"):
			return
		await process_frame
	await process_frame
	for pending in main._pending_searches:
		if not _require(int(pending["task_id"]) != old_task_id, "旧搜索完成后没有被回收"):
			return

	main._cancel_searches()
	print("search_cancellation_test: restart=%.2fms ok" % restart_ms)
	quit()

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	printerr("search_cancellation_test: FAILED: %s" % message)
	quit(1)
	return false
