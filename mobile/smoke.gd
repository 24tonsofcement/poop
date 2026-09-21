extends SceneTree
var failures: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://mobile/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	check(game.songs.size() > 0, "bundled demo loaded")
	check(game.screen == "menu", "mobile menu opened")
	game.start_game()
	await process_frame
	check(game.screen == "game", "demo playable")
	if game.runs.is_empty():
		quit(1)
		return
	# Simultaneous chords, shared-lane fingers and independent release.
	for index in range(4):
		var touch = InputEventScreenTouch.new()
		touch.index = index
		touch.pressed = true
		touch.position = Vector2((index + 0.5) * game.size.x / 4.0, game.size.y - 30)
		game._input(touch)
	check(game.runs[0].held == [true, true, true, true], "four-finger chord")
	game.fingers[5] = 0
	game.release_finger(0)
	check(game.runs[0].held[0], "second finger retains hold")
	game.release_finger(5)
	check(not game.runs[0].held[0] and game.runs[0].held[1], "independent finger release")
	game.toggle_pause()
	check(game.fingers.is_empty(), "pause clears touch state")
	game.show_settings()
	await process_frame
	game.show_mobile_library()
	await process_frame
	game.show_menu()
	game.queue_free()
	await process_frame
	print("Android smoke failures: ", failures)
	quit(failures)
