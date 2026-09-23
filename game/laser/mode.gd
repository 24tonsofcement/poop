extends "res://game/main.gd"
const LaserEngine = preload("res://game/laser/engine.gd")
const Controller = preload("res://game/laser/controller.gd")
const CYAN = Color("43e9ff")
const PINK = Color("ff4cb5")
var controls = Controller.new()
var engine = LaserEngine.new()
var laser_difficulty: String = "Normal"
var laser_paused: bool = false
var laser_chart: Dictionary = {}
var laser_clock: float = 0.0
var controller_label: Label
var best_scores: Dictionary = {}
var fx_bus: int = -1
var filter_effect: AudioEffectLowPassFilter
var effects_enabled: bool = true
var tilt_enabled: bool = true
var laser_key: String = ""
var menu_motion: Array = [0.0, 0.0]
var last_menu_move: int = 0

func apply_theme() -> void:
	theme = Theme.new()
	theme.default_font = ThemeDB.fallback_font
	theme.default_font_size = 18
	for kind in ["Button", "OptionButton", "LineEdit"]:
		for state in ["normal", "hover", "pressed", "focus"]:
			var style = StyleBoxFlat.new()
			style.bg_color = Color("101b2e") if state == "normal" else Color("24394c")
			style.border_color = CYAN if state != "pressed" else PINK
			style.set_border_width_all(1 if state == "normal" else 2)
			style.corner_radius_top_left = 10
			style.corner_radius_bottom_right = 10
			style.content_margin_left = 14; style.content_margin_right = 14
			style.content_margin_top = 12; style.content_margin_bottom = 12
			theme.set_stylebox(state, kind, style)
		theme.set_color("font_color", kind, WHITE)
		theme.set_color("font_hover_color", kind, CYAN)

func menu_ink(color: Color) -> Color:
	return color

func button_into(parent: Node, caption: String, callback: Callable) -> Button:
	var button = super.button_into(parent, caption, callback)
	button.resized.connect(func(): button.pivot_offset = button.size / 2)
	button.mouse_entered.connect(func():
		if not reduced_motion: create_tween().tween_property(button, "scale", Vector2(1.025, 1.025), .12))
	button.mouse_exited.connect(func(): create_tween().tween_property(button, "scale", Vector2.ONE, .12))
	return button

func mode_name() -> String:
	return "laser"

func settings_path() -> String:
	return "user://laser-preferences.json"

func library_root() -> String:
	return ProjectSettings.globalize_path("user://laser-songs")

func _ready() -> void:
	super._ready()
	players_count = 1
	for id in Input.get_connected_joypads():
		if controls.profile == Input.get_joy_name(id) + " / " + Input.get_joy_guid(id): controls.device = id
	if FileAccess.file_exists("user://laser-scores.json"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("user://laser-scores.json"))
		if parsed is Dictionary: best_scores = parsed
	var settings = ConfigFile.new()
	if settings.load("user://laser-settings.cfg") == OK:
		laser_difficulty = str(settings.get_value("play", "difficulty", "Normal"))
		effects_enabled = bool(settings.get_value("play", "effects", true))
		tilt_enabled = bool(settings.get_value("play", "tilt", true))
	fx_bus = AudioServer.get_bus_index("LaserDriveFX")
	if fx_bus < 0:
		AudioServer.add_bus()
		fx_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(fx_bus, "LaserDriveFX")
		filter_effect = AudioEffectLowPassFilter.new()
		filter_effect.cutoff_hz = 20000
		AudioServer.add_bus_effect(fx_bus, filter_effect)
		AudioServer.add_bus_effect(fx_bus, AudioEffectChorus.new())
		var distortion = AudioEffectDistortion.new()
		distortion.drive = .35
		distortion.post_gain = -6
		AudioServer.add_bus_effect(fx_bus, distortion)
	else: filter_effect = AudioServer.get_bus_effect(fx_bus, 0)
	AudioServer.set_bus_send(fx_bus, music_visualizer.bus_name)
	audio.bus = "LaserDriveFX"
	Input.joy_connection_changed.connect(controller_connection)
	show_menu()

func controller_connection(device_id: int, connected: bool) -> void:
	if device_id == controls.device and not connected:
		engine.release_all()
		controls.previous.clear(); controls.rates = [0.0, 0.0]
		if screen == "laser_game" and not laser_paused: toggle_pause()
		last_message = "Controller disconnected. Reconnect and select it in Controllers."

func save_laser_settings() -> void:
	var settings = ConfigFile.new()
	settings.set_value("play", "difficulty", laser_difficulty)
	settings.set_value("play", "effects", effects_enabled)
	settings.set_value("play", "tilt", tilt_enabled)
	settings.save("user://laser-settings.cfg")

func scan_songs() -> void:
	super.scan_songs()
	for song in songs:
		if str(song.folder).begins_with("res://") and not song.has("laser_charts"):
			var diffs: Dictionary = {}
			var source: Dictionary = song.charts.values()[0]
			for difficulty in source:
				var notes: Array = source[difficulty].duplicate(true)
				for i in range(notes.size()):
					if i % 5 == 0: notes[i].lane = 4 + i % 2
				var lasers: Array = [[], []]
				for section in range(3):
					var start: float = 4.0 + section * 12
					var side: int = section % 2
					lasers[side].append({"points": [{"t": start, "x": .2}, {"t": start + 1, "x": .8}, {"t": start + 2, "x": .8}, {"t": start + 2, "x": .2}, {"t": start + 3.5, "x": .7}]})
					var occupied: Array = [0, 1, 4] if side == 0 else [2, 3, 5]
					notes = notes.filter(func(n): return not (int(n.lane) in occupied and float(n.end) >= start - .15 and float(n.t) <= start + 3.65))
				diffs[difficulty] = {"buttons": notes, "lasers": lasers}
			song.laser_charts = diffs

func page(title: String) -> VBoxContainer:
	clear_ui()
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, 70)
	margin.add_theme_constant_override("margin_top", 56)
	margin.add_theme_constant_override("margin_bottom", 28)
	ui.add_child(margin)
	var scroll = ScrollContainer.new()
	margin.add_child(scroll)
	var column = box_into(scroll)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_into(column, title, 36, CYAN)
	return column

func show_menu() -> void:
	screen = "menu"
	laser_paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if audio != null: audio.stop(); audio.stream_paused = false
	stop_background_video()
	engine.release_all()
	disable_fx()
	covers.enabled = true
	var root = page("LASER DRIVE   /   TRACK SELECT")
	var top = box_into(root, true)
	button_into(top, "IMPORT / LIBRARY", show_laser_import)
	button_into(top, "CONTROLLERS", show_controllers)
	button_into(top, "SETTINGS", show_settings)
	button_into(top, "PAUSE PREVIEW" if not preview_paused else "RESUME PREVIEW", toggle_preview)
	var search = LineEdit.new()
	search.placeholder_text = "Search laser tracks"
	search.text = song_search
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(search)
	search.text_submitted.connect(func(value): song_search = value; show_menu())
	filtered = songs.filter(func(song): return song.has("laser_charts") and song_matches_search(song))
	if not selected in filtered: selected = filtered[0] if not filtered.is_empty() else {}
	var carousel = Control.new()
	carousel.name = "SongCarousel"
	carousel.custom_minimum_size.y = 290
	root.add_child(carousel)
	build_carousel(carousel)
	carousel.resized.connect(func(): layout_carousel(carousel))
	var row = box_into(root, true)
	button_into(row, "◀", func(): move_song(-1))
	var play = button_into(row, "▶   START TRACK", start_game)
	play.custom_minimum_size = Vector2(260, 64)
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.disabled = selected.is_empty()
	button_into(row, "▶", func(): move_song(1))
	if not selected.is_empty():
		var diffs: Array = selected.laser_charts.keys()
		if laser_difficulty not in diffs: laser_difficulty = str(diffs[0])
		var choice = OptionButton.new()
		for difficulty in diffs: choice.add_item(str(difficulty))
		choice.select(diffs.find(laser_difficulty))
		row.add_child(choice)
		var profile = LineEdit.new()
		profile.text = profile_names[0]
		profile.placeholder_text = "Player name"
		profile.custom_minimum_size.x = 120
		row.add_child(profile)
		profile.text_changed.connect(func(value): profile_names[0] = clean_profile(value, 0); save_settings())
		choice.item_selected.connect(func(index): laser_difficulty = str(diffs[index]); save_laser_settings(); show_menu())
		laser_key = profile_names[0] + ":" + str(selected.id) + ":" + laser_difficulty + ":" + JSON.stringify(selected.laser_charts[laser_difficulty]).sha256_text()
		label_into(root, "PERSONAL BEST   %08d    /    %s" % [int(best_scores.get(laser_key, 0)), profile_names[0]], 22, PINK)
	label_into(root, "BT  D F J K     FX  C M     LASERS  mouse X/Y or Q W / O P     START Enter     PAUSE Esc", 16, WHITE)
	status_label = label_into(root, last_message, 17, CYAN)
	request_preview()
	queue_redraw()

func show_laser_import() -> void:
	screen = "laser_import"
	var root = page("LASER LIBRARY   /   SEPARATE COLLECTION")
	label_into(root, "Imports create six-button / dual-laser charts here. Your Arcade library is unchanged.", 17)
	var link = LineEdit.new()
	link.placeholder_text = "YouTube or SoundCloud song URL"
	root.add_child(link)
	button_into(root, "IMPORT & GENERATE LASER CHARTS", func(): start_import("link", link.text))
	var row = box_into(root, true)
	button_into(row, "Import osu!mania + generate lasers", choose_osu)
	button_into(row, "Import PNG cards", choose_song_card)
	button_into(row, "Export selected card", export_song_card)
	button_into(row, "Song storage", func(): show_song_manager(true))
	if not selected.is_empty() and str(selected.get("category", "")) in GENERATED_CATEGORIES:
		button_into(root, "Regenerate selected laser chart", func(): start_import("regenerate", str(selected.folder)))
	button_into(root, "Cancel import", cancel_import)
	button_into(root, "BACK TO TRACKS", show_menu)
	status_label = label_into(root, last_message, 17, CYAN)

func show_controllers() -> void:
	screen = "controllers"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var root = page("CONTROL SYSTEM   /   CALIBRATION")
	var devices = OptionButton.new()
	devices.add_item("Keyboard / mouse or any controller", -1)
	for id in Input.get_connected_joypads(): devices.add_item(Input.get_joy_name(id), id)
	root.add_child(devices)
	devices.item_selected.connect(func(index):
		controls.device = -1 if index == 0 else devices.get_item_id(index)
		controls.load_profile("Keyboard / mouse" if controls.device < 0 else Input.get_joy_name(controls.device) + " / " + Input.get_joy_guid(controls.device))
		controls.save(); show_controllers())
	for i in range(devices.item_count):
		if (i == 0 and controls.device < 0) or (i > 0 and devices.get_item_id(i) == controls.device): devices.select(i)
	var source = OptionButton.new()
	for label in ["HID keyboard + mouse knobs", "Joystick / gamepad axes", "Keyboard only"]: source.add_item(label)
	source.select(controls.source)
	root.add_child(source)
	source.item_selected.connect(func(index): controls.source = index; controls.previous.clear(); controls.save())
	var row = box_into(root, true)
	for lane in range(7):
		var label: String = ["BT-A", "BT-B", "BT-C", "BT-D", "FX-L", "FX-R", "START"][lane]
		button_into(row, label + "\n" + OS.get_keycode_string(int(controls.keys[lane])) + " / J" + str(controls.joy_buttons[lane]), func(): controls.learning = lane; controls.learning_axis = -1; controls.feedback = "Press the new key or controller button for " + label)
	var knobs = box_into(root, true)
	for side in range(2):
		button_into(knobs, "Learn " + ("LEFT" if side == 0 else "RIGHT") + " axis (currently %d)" % controls.axes[side], func(): controls.learning_axis = side; controls.learning = -1)
		var invert = CheckBox.new()
		invert.text = "Invert " + str(side + 1)
		invert.button_pressed = controls.inverted[side]
		knobs.add_child(invert)
		invert.toggled.connect(func(value): controls.inverted[side] = value; controls.save())
	var modes = OptionButton.new()
	for label in ["Wrapping encoder", "Non-wrapping analog", "Spring-centered stick"]: modes.add_item(label)
	modes.select(controls.axis_mode)
	root.add_child(modes)
	modes.item_selected.connect(func(index): controls.axis_mode = index; controls.previous.clear(); controls.rates = [0.0, 0.0]; controls.save())
	controller_slider(root, "Sensitivity", .1, 10, controls.sensitivity, func(value): controls.sensitivity = value; controls.save())
	controller_slider(root, "Jitter threshold", 0, .1, controls.deadzone, func(value): controls.deadzone = value; controls.save())
	for item in [["Music FX", effects_enabled, "effects"], ["Highway tilt / slam animation", tilt_enabled, "tilt"]]:
		var toggle = CheckBox.new()
		toggle.text = item[0]; toggle.button_pressed = item[1]
		root.add_child(toggle)
		toggle.toggled.connect(func(value):
			if item[2] == "effects": effects_enabled = value
			else: tilt_enabled = value
			save_laser_settings())
	controller_label = label_into(root, controls.feedback, 20, CYAN)
	label_into(root, "Use the controller's keyboard/mouse or joystick firmware mode. Mouse X = left knob, Y = right knob.\nCustom USB protocols and cabinet lighting are not supported. Press Esc to cancel binding.", 16)
	button_into(root, "BACK TO TRACKS", func(): controls.learning = -1; controls.learning_axis = -1; show_menu())

func controller_slider(parent: Node, title: String, minimum: float, maximum: float, value: float, callback: Callable) -> void:
	var caption = label_into(parent, title + "  %.3f" % value, 17)
	var slider = HSlider.new()
	slider.min_value = minimum; slider.max_value = maximum; slider.step = .001; slider.value = value
	slider.custom_minimum_size = Vector2(500, 26)
	parent.add_child(slider)
	slider.value_changed.connect(func(amount): caption.text = title + "  %.3f" % amount; callback.call(amount))

func start_game() -> void:
	if selected.is_empty() or not selected.has("laser_charts"): return
	stop_preview()
	laser_key = profile_names[0] + ":" + str(selected.id) + ":" + laser_difficulty + ":" + JSON.stringify(selected.laser_charts[laser_difficulty]).sha256_text()
	laser_chart = selected.laser_charts[laser_difficulty]
	var timing: Array = selected.get("timing", []) if selected.get("timing", []) is Array else []
	if selected.get("timing", []) is Dictionary and not selected.timing.is_empty(): timing = selected.timing.values()[0].get(laser_difficulty, [])
	engine.setup(laser_chart, timing)
	audio.stop(); audio.stream_paused = false
	audio.stream = load_song_audio()
	if audio.stream == null: last_message = "Audio missing; reimport the song."; show_menu(); return
	laser_clock = -2.0; laser_paused = false; playing = false
	screen = "laser_game"
	prepare_background_video()
	clear_ui()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if controls.source == 0 else Input.MOUSE_MODE_VISIBLE
	queue_redraw()

func toggle_pause() -> void:
	if screen != "laser_game": return
	laser_paused = not laser_paused
	engine.release_all()
	controls.rates = [0.0, 0.0]; controls.previous.clear()
	audio.stream_paused = laser_paused
	background_video.paused = laser_paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if laser_paused or controls.source != 0 else Input.MOUSE_MODE_CAPTURED
	clear_ui()
	if laser_paused:
		var root = page("LASER DRIVE   /   PAUSED")
		button_into(root, "RESUME", toggle_pause)
		button_into(root, "RESTART", start_game)
		button_into(root, "TRACK SELECT", show_menu)
		button_into(root, "GAME MODE SELECT", return_to_modes)

func _input(event: InputEvent) -> void:
	if not controls.focused: return
	if screen == "menu" and get_viewport().gui_get_focus_owner() is LineEdit: return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if controls.learning >= 0 or controls.learning_axis >= 0: controls.learning = -1; controls.learning_axis = -1; return
		if screen == "laser_game": toggle_pause(); return
		if screen != "menu": show_menu(); return
	if screen not in ["laser_game", "controllers", "menu"]:
		super._input(event); return
	var actions: Array = controls.event_actions(event)
	if screen == "controllers":
		if is_instance_valid(controller_label): controller_label.text = controls.feedback
		return
	for action in actions:
		if screen == "menu" and action.has("knob"):
			var side: int = int(action.knob)
			menu_motion[side] += float(action.delta)
			if absf(float(menu_motion[side])) >= .12 and Time.get_ticks_msec() - last_menu_move > 130:
				var direction: int = 1 if float(menu_motion[side]) > 0 else -1
				menu_motion[side] = 0.0; last_menu_move = Time.get_ticks_msec()
				if side == 1: move_song(direction)
				elif not selected.is_empty():
					var diffs: Array = selected.laser_charts.keys()
					laser_difficulty = str(diffs[posmod(diffs.find(laser_difficulty) + direction, diffs.size())])
					save_laser_settings(); show_menu()
			continue
		if action.has("button"):
			if int(action.button) == 6 and bool(action.down):
				if screen == "menu": start_game()
				else: toggle_pause()
			elif screen == "laser_game" and not laser_paused:
				var previous_hits: int = engine.critical + engine.near
				engine.press(int(action.button), bool(action.down), laser_clock - offset_ms / 1000.0)
				if engine.critical + engine.near > previous_hits: play_feedback(false)
		elif screen == "laser_game" and not laser_paused: engine.turn(int(action.knob), float(action.delta), laser_clock - offset_ms / 1000.0)

func _process(delta: float) -> void:
	if screen != "laser_game": super._process(delta); return
	if laser_paused: return
	ui_clock += delta
	if not playing:
		laser_clock += delta
		if laser_clock >= 0:
			audio.play(); playing = true; laser_clock = 0
			if background_video.stream != null: background_video.play(); background_video.visible = true
	elif audio.playing:
		laser_clock = maxf(laser_clock, audio.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency())
	else: laser_clock += delta
	var at: float = laser_clock - offset_ms / 1000.0
	var movement: Array = controls.continuous(delta)
	for side in range(2): engine.turn(side, float(movement[side]), at)
	var before: int = engine.critical + engine.near
	var missed: int = engine.misses
	engine.advance(at)
	if engine.critical + engine.near > before: play_feedback(false)
	elif engine.misses > missed: play_feedback(true)
	update_fx(delta)
	music_visualizer.sample(delta, visual_effects.audio_visualizer)
	if playing and laser_clock > audio.stream.get_length() + .4: finish_laser()
	queue_redraw()

func disable_fx() -> void:
	fx_bus = AudioServer.get_bus_index("LaserDriveFX")
	if fx_bus < 0: return
	for index in range(AudioServer.get_bus_effect_count(fx_bus)): AudioServer.set_bus_effect_enabled(fx_bus, index, false)

func update_fx(delta: float) -> void:
	if fx_bus < 0: return
	var active: bool = false
	var value: float = .5
	for side in range(2):
		for path in engine.paths[side]:
			if laser_clock >= float(path.points[0].t) and laser_clock <= float(path.points[-1].t):
				active = true; value = float(engine.positions[side])
	AudioServer.set_bus_effect_enabled(fx_bus, 0, effects_enabled and active)
	filter_effect.cutoff_hz = lerpf(filter_effect.cutoff_hz, 500 + pow(value, 2) * 18500, minf(1, delta * 20))
	for side in range(2):
		var engaged: bool = false
		for note in engine.buttons:
			if int(note.lane) == 4 + side and int(note.state) == 1 and laser_clock >= float(note.t) and laser_clock <= maxf(float(note.end), float(note.t) + .12): engaged = true; break
		AudioServer.set_bus_effect_enabled(fx_bus, side + 1, effects_enabled and engaged and engine.held[side + 4])

func finish_laser() -> void:
	disable_fx()
	screen = "laser_results"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	stop_background_video()
	var score: int = engine.score()
	if score > int(best_scores.get(laser_key, 0)):
		best_scores[laser_key] = score
		var file = FileAccess.open("user://laser-scores.json", FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(best_scores)); file.close()
	var root = page("TRACK COMPLETE" if engine.gauge >= .7 else "TRACK FAILED")
	label_into(root, "%08d" % score, 58, CYAN)
	var grade: String = "S" if score >= 9900000 else "AAA" if score >= 9700000 else "AA" if score >= 9300000 else "A" if score >= 8700000 else "B" if score >= 7500000 else "C"
	label_into(root, "%s   /   BEST CHAIN %d   /   RATE %.1f%%" % [grade, engine.best, engine.gauge * 100], 26, PINK)
	label_into(root, "CRITICAL %d     NEAR %d     ERROR %d" % [engine.critical, engine.near, engine.misses], 22)
	button_into(root, "RETRY", start_game)
	button_into(root, "TRACK SELECT", show_menu)
	button_into(root, "GAME MODE SELECT", return_to_modes)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		controls.focused = false
		engine.release_all(); controls.previous.clear(); controls.rates = [0.0, 0.0]
		if screen == "laser_game" and not laser_paused: toggle_pause()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN: controls.focused = true
	super._notification(what)

func _exit_tree() -> void:
	disable_fx()
	if fx_bus >= 0: AudioServer.remove_bus(fx_bus)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func point(lane: float, seconds: float) -> Vector2:
	var hit: float = size.y - 130
	var top: float = 120
	var lookahead: float = clampf(1100.0 / maxf(scroll_speed, 100), .35, 6)
	var depth: float = clampf(1.0 - seconds / lookahead, 0, 1.18)
	var y: float = lerpf(top, hit, pow(depth, 1.5))
	var width: float = lerpf(size.x * .12, size.x * .53, depth)
	return Vector2(size.x / 2 + (lane - .5) * width, y)

func note_quad(a: float, b: float, seconds: float, thickness: float, tint: Color) -> void:
	var p: Vector2 = point(a, seconds)
	var q: Vector2 = point(b, seconds)
	draw_colored_polygon(PackedVector2Array([p, q, q + Vector2(0, thickness), p + Vector2(0, thickness)]), tint)

func _draw() -> void:
	var backdrop := Color("080d19")
	if screen == "laser_game" and ((is_instance_valid(background_video) and background_video.visible) or (is_instance_valid(background_image) and background_image.visible)):
		backdrop.a = .25
	draw_rect(Rect2(Vector2.ZERO, size), backdrop)
	for index in range(14):
		var x: float = fmod(index * 160 + ui_clock * 30, size.x + 250) - 125
		draw_line(Vector2(x, 0), Vector2(x - 220, size.y), Color(.2, .5, .7, .10), 2)
	if screen != "laser_game":
		draw_arc(size / 2, size.y * .42, ui_clock * .1, ui_clock * .1 + 4.8, 90, Color(.8, .2, .6, .18), 3)
		return
	var angle: float = 0.0
	if tilt_enabled: angle = (float(engine.positions[0]) + float(engine.positions[1]) - 1) * .035
	draw_set_transform(size / 2, angle, Vector2.ONE)
	draw_set_transform_matrix(Transform2D(angle, size / 2 - Vector2(size / 2).rotated(angle)))
	var road = PackedVector2Array([point(0, 10), point(1, 10), point(1, -.3), point(0, -.3)])
	draw_colored_polygon(road, Color(.06, .08, .14, highway_opacity))
	for lane in range(5): draw_line(point(lane / 4.0, 10), point(lane / 4.0, -.3), Color(.5, .7, .9, .25), 2)
	for side in range(2):
		draw_line(point(float(side), 10), point(float(side), -.3), CYAN if side == 0 else PINK, 4)
	var at: float = laser_clock - offset_ms / 1000.0
	var ahead: float = clampf(1100.0 / maxf(scroll_speed, 100), .35, 6)
	for note in engine.buttons:
		if float(note.end) < at - .15: continue
		if float(note.t) > at + ahead: break
		var lane: int = int(note.lane)
		var a: float = lane / 4.0 + .02 if lane < 4 else (lane - 4) / 2.0 + .02
		var b: float = a + (.21 if lane < 4 else .46)
		var tint: Color = Color("ecf4ff") if lane < 4 else Color("ffb12f")
		if float(note.end) > float(note.t) + .05:
			var upper: float = float(note.end) - at
			var lower: float = maxf(0, float(note.t) - at)
			draw_colored_polygon(PackedVector2Array([point(a, upper), point(b, upper), point(b, lower), point(a, lower)]), Color(tint, .5))
		if int(note.state) == 0: note_quad(a, b, float(note.t) - at, 9, tint)
	for side in range(2):
		var tint: Color = CYAN if side == 0 else PINK
		for path in engine.paths[side]:
			var points: Array = path.points
			for index in range(1, points.size()):
				var a: Dictionary = points[index - 1]
				var b: Dictionary = points[index]
				if float(b.t) < at or float(a.t) > at + ahead: continue
				var p: Vector2 = point(float(a.x), maxf(0, float(a.t) - at))
				var q: Vector2 = point(float(b.x), float(b.t) - at)
				draw_line(p, q, Color(tint, .18), 24, true)
				draw_line(p, q, tint, 9, true)
				draw_line(p, q, Color.WHITE, 2, true)
		var cursor: Vector2 = point(float(engine.positions[side]), 0)
		draw_colored_polygon(PackedVector2Array([cursor + Vector2(-13, 20), cursor + Vector2(0, -4), cursor + Vector2(13, 20)]), tint)
	draw_line(point(0, 0), point(1, 0), Color.WHITE, 4)
	for effect in engine.effects:
		var age: float = at - float(effect.t)
		var lane: int = int(effect.lane)
		var location: float = (lane + .5) / 4.0 if lane < 4 else (lane - 4 + .5) / 2.0 if lane < 6 else float(engine.positions[lane - 6])
		var color: Color = CYAN if int(effect.points) > 0 else Color("ff334c")
		draw_arc(point(location, 0), 10 + age * 120, 0, TAU, 32, Color(color, maxf(0, 1 - age * 2)), 3)
	draw_set_transform(Vector2.ZERO)
	if visual_effects.audio_visualizer:
		for index in range(music_visualizer.levels.size()):
			var value: float = music_visualizer.levels[index].x
			draw_rect(Rect2(40, 200 + index * 14, 10 + value * 110, 7), Color(CYAN, .35 + value * .45))
	for lane in range(6):
		var x: float = size.x * .27 + lane * size.x * .075
		var tint: Color = WHITE if lane < 4 else Color("ffb12f")
		draw_rect(Rect2(x, size.y - 105, size.x * .065, 20), Color(tint, .8 if engine.held[lane] else .12))
	text_at(Vector2(65, 78), "LASER DRIVE", 30, CYAN)
	text_at(Vector2(65, 115), str(selected.get("title", "")), 19, WHITE, size.x - 360)
	text_at(Vector2(size.x - 270, 75), "%08d" % engine.score(), 32, WHITE)
	text_at(Vector2(size.x - 270, 111), laser_difficulty.to_upper(), 18, PINK)
	text_at(Vector2(size.x * .5 - 75, size.y - 66), "%04d CHAIN" % engine.combo, 28, WHITE)
	text_at(Vector2(size.x * .5 - 70, size.y - 35), engine.message, 19, CYAN)
	var meter = Rect2(size.x - 90, 170, 26, size.y - 350)
	draw_rect(meter, Color("192538"))
	draw_rect(Rect2(meter.position + Vector2(0, meter.size.y * (1 - engine.gauge)), Vector2(meter.size.x, meter.size.y * engine.gauge)), PINK if engine.gauge >= .7 else CYAN)
	draw_line(meter.position + Vector2(-8, meter.size.y * .3), meter.position + Vector2(34, meter.size.y * .3), Color.WHITE, 2)
	text_at(Vector2(size.x - 110, size.y - 140), "%d%%" % (engine.gauge * 100), 18)
	if laser_clock < 0: text_at(Vector2(size.x / 2 - 110, size.y / 2), "READY  %d" % ceili(-laser_clock), 40, PINK)
