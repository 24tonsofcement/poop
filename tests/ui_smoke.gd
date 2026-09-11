extends SceneTree
var failures: int = 0
func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)
func _initialize() -> void:
	call_deferred("run_checks")
func run_checks() -> void:
	var scene = load("res://game/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.reduced_motion = false
	scene.ui_motion.reduced = false
	await create_timer(0.5).timeout
	var play = scene.ui.find_child("PlaySong", true, false)
	check(play != null and play.get("spin") == 0.0, "Play is a vector CD control")
	play.mouse_entered.emit()
	await create_timer(0.22).timeout
	check(play.scale.x > 1.0, "Hover makes button pop out")
	play.mouse_exited.emit()
	await create_timer(0.22).timeout
	check(play.scale.is_equal_approx(Vector2.ONE), "Mouse exit restores original scale")
	var previous: Control = scene.ui
	scene.show_settings()
	check(previous.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Outgoing screen stops receiving pointer input")
	check(scene.ui.modulate.a < 1.0, "New screen fades in")
	scene.show_menu()
	scene.show_settings()
	scene.show_menu()
	await create_timer(0.6).timeout
	check(not is_instance_valid(previous), "Rapid navigation frees obsolete screens")
	check(is_equal_approx(scene.ui.modulate.a, 1.0) and is_zero_approx(scene.ui.position.y), "Incoming menu settles at full opacity and original position")
	var selected_id: String = str(scene.selected.id)
	scene.show_menu()
	check(is_equal_approx(scene.ui.modulate.a, 1.0), "Same-screen refresh never restarts a page fade")
	await process_frame
	play = scene.ui.find_child("PlaySong", true, false)
	scene.request_play(play)
	var first_tween = scene.ui_motion.launch_tween
	scene.request_play(play)
	check(scene.ui_motion.launch_tween == first_tween, "Double click launches only once")
	await create_timer(0.25).timeout
	check(play.spin > 0.0 and scene.screen == "menu", "CD spins before the song transition")
	await create_timer(1.0).timeout
	check(scene.screen == "game" and str(scene.selected.id) == selected_id, "Fade enters the selected song")
	check(not scene.ui_motion.launching and not is_instance_valid(scene.ui_motion.veil), "Launch veil and input lock are removed")
	scene.show_menu()
	scene.reduced_motion = true
	scene.ui_motion.reduced = true
	scene.show_settings()
	check(is_equal_approx(scene.ui.modulate.a, 1.0) and scene.ui.position == Vector2.ZERO, "Reduced motion removes slide transitions")
	check(scene.ui.find_child("ReducedMotion", true, false) != null, "Reduced motion is exposed in Settings")
	scene.show_menu()
	await process_frame
	play = scene.ui.find_child("PlaySong", true, false)
	play.mouse_entered.emit()
	check(play.scale == Vector2.ONE, "Reduced motion disables hover scaling")
	scene.request_play(play)
	await create_timer(0.4).timeout
	check(scene.screen == "game" and not scene.ui_motion.launching, "Reduced-motion launch still opens the game")
	scene.queue_free()
	await process_frame
	await process_frame
	print("UI smoke failures: ", failures)
	quit(1 if failures else 0)
