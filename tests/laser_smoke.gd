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
	controls.focused = true
	controls.load_profile("smoke-custom-keys")
	controls.keys = controls.DEFAULT_KEYS.duplicate()
	controls.assign_key(7, KEY_Z)
	controls.assign_key(0, KEY_F)
	check(controls.keys[0] == KEY_F and controls.keys[1] == KEY_D, "Duplicate bindings swap instead of hitting two lanes")
	controls.save()
	var reloaded = load("res://game/laser/controller.gd").new()
	check(reloaded.keys[7] == KEY_Z and reloaded.keys[0] == KEY_F, "Custom directions and buttons survive reload")
	var bound = InputEventKey.new(); bound.physical_keycode = KEY_F; bound.pressed = true
	var actions: Array = reloaded.event_actions(bound)
	check(actions.size() == 1 and actions[0].button == 0, "Remapped note key emits exactly one lane action")
	reloaded.assign_key(11, KEY_B)
	bound.physical_keycode = KEY_B
	check(reloaded.event_actions(bound)[0].button == 11, "Pause has its own remappable action")
	controls.load_profile("Keyboard / mouse"); controls.save()
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
	game.show_settings()
	await process_frame
	check(game.ui.find_child("LaserSettings", true, false).get_tab_count() == 5, "Dedicated Laser settings categories")
	var speed = game.ui.find_child("NoteSpeed", true, false)
	speed.text = "20000"
	game.apply_note_speed(speed)
	check(game.scroll_speed == 20000, "Highway speed accepts values above old cap")
	var fast: Vector2 = game.point(.5, .02)
	game.scroll_speed = 4000
	check(game.point(.5, .02).y > fast.y, "High speed changes actual travel, not only saved label")
	game.scroll_speed = 750; game.save_settings()
	game.highway_width = .65; game.note_thickness = 15; game.save_laser_settings()
	var cfg = ConfigFile.new(); cfg.load("user://laser-settings.cfg")
	check(cfg.get_value("stage", "highway_width") == .65 and cfg.get_value("stage", "note_thickness") == 15, "Stage settings persist")
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
