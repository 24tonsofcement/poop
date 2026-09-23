extends SceneTree
var failures: int = 0
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var engine = load("res://game/laser/engine.gd").new()
	engine.setup({"buttons": [{"t": 1.0, "end": 1.0, "lane": 0}, {"t": 1.0, "end": 1.5, "lane": 4}], "lasers": [[], []]})
	engine.press(0, true, 1.0); engine.press(4, true, 1.0)
	check(engine.critical == 2, "BT and FX simultaneous judgment")
	engine.advance(1.13)
	check(engine.critical == 3, "FX hold tick")
	engine.press(4, false, 1.14); engine.advance(1.26)
	check(engine.misses == 1 and engine.combo == 0, "Early FX release breaks chain on missed ticks")
	engine.setup({"buttons": [], "lasers": [[{"points": [{"t": 1.0, "x": .2}, {"t": 2.0, "x": .8}, {"t": 2.0, "x": .2}, {"t": 3.0, "x": .2}]}], []]})
	engine.turn(0, .1, 1.0); engine.advance(1.0)
	check(engine.critical > 0, "Correct knob direction acquires laser")
	engine.turn(0, -.5, 2.0); engine.advance(2.16)
	check(engine.message == "SLAM" or engine.critical > 1, "Laser slam accepted")
	var controls = load("res://game/laser/controller.gd").new()
	controls.previous = {0: .98}; controls.axis_mode = 0; controls.inverted[0] = false; controls.sensitivity = 1
	check(controls.axis_delta(0, -.98) > 0 and controls.axis_delta(0, -.96) < .1, "Encoder wraps in correct direction")
	controls.focused = false
	var input = InputEventKey.new(); input.physical_keycode = KEY_D; input.pressed = true
	check(controls.event_actions(input).is_empty(), "Unfocused controller is ignored")
	var game = load("res://game/laser/mode.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	check(game.song_root.ends_with("laser-songs"), "Independent library")
	check(game.selected.has("laser_charts"), "Laser demo available")
	game.start_game()
	await process_frame
	check(game.screen == "laser_game", "Laser gameplay starts")
	game.toggle_pause()
	check(game.laser_paused, "Laser pause")
	game.show_controllers()
	await process_frame
	check(game.screen == "controllers", "Controller configuration renders")
	game.show_menu()
	await process_frame
	game.queue_free()
	await process_frame
	var selector = load("res://game/mode_select.tscn").instantiate()
	root.add_child(selector)
	await process_frame
	check(selector.get_child_count() > 0, "Mode selector renders")
	selector.queue_free()
	print("Laser smoke failures: ", failures)
	quit(1 if failures else 0)
