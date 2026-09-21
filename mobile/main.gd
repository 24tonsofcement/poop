extends "res://game/main.gd"

var fingers: Dictionary = {}
var companion_url: String = ""
var companion_token: String = ""
var phone_status: Label
var native_importer: Object
var native_last_status: String = ""
var ai_enabled: bool = false
var model_list: VBoxContainer

func _ready() -> void:
	var config = ConfigFile.new()
	if config.load("user://mobile.cfg") == OK:
		companion_url = str(config.get_value("companion", "url", ""))
		companion_token = str(config.get_value("companion", "token", ""))
	if Engine.has_singleton("PulseNative"):
		native_importer = Engine.get_singleton("PulseNative")
	var native_timer = Timer.new()
	native_timer.wait_time = 0.5
	native_timer.timeout.connect(poll_native_import)
	add_child(native_timer)
	native_timer.start()
	super._ready()
	players_count = 1
	offline_players = 1
	get_tree().auto_accept_quit = false

func button_into(parent: Node, text: String, callback: Callable) -> Button:
	var button = super.button_into(parent, text, callback)
	button.custom_minimum_size.y = 54
	return button

func mobile_page(title: String) -> VBoxContainer:
	clear_ui()
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 44)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	ui.add_child(margin)
	var scroll = ScrollContainer.new()
	margin.add_child(scroll)
	var root = box_into(scroll)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var heading = box_into(root, true)
	var caption = label_into(heading, title, 26)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if screen != "menu":
		button_into(heading, "Back", show_menu)
	return root

func show_menu() -> void:
	players_count = 1
	fingers.clear()
	screen = "menu"
	audio.stop()
	stop_background_video()
	covers.enabled = true
	var root = mobile_page("PULSE / MOBILE")
	var top = box_into(root, true)
	button_into(top, "Songs", show_mobile_library)
	button_into(top, "Online", open_online)
	button_into(top, "Settings", show_settings)
	var preview_button = button_into(top, "Resume preview" if preview_paused else "Pause preview", toggle_preview)
	preview_button.name = "PreviewToggle"
	var search = LineEdit.new()
	search.placeholder_text = "Search songs"
	search.text = song_search
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(search)
	search.text_submitted.connect(func(value): song_search = value; show_menu())
	filtered = songs.filter(func(song): return song_matches_search(song))
	if not filtered.is_empty() and not selected in filtered:
		selected = filtered[0]
	var carousel = Control.new()
	carousel.name = "Carousel"
	carousel.custom_minimum_size.y = 230
	root.add_child(carousel)
	build_carousel(carousel)
	carousel.resized.connect(func(): layout_carousel(carousel))
	var controls = box_into(root, true)
	button_into(controls, "◀", func(): move_song(-1))
	var play = button_into(controls, "▶  PLAY", func(): start_game())
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.disabled = filtered.is_empty()
	button_into(controls, "▶", func(): move_song(1))
	if not selected.is_empty():
		resolve_player_choice(0)
		var row = box_into(root, true)
		var instruments: Array = selected.charts.keys()
		mobile_choice(row, instruments, str(choices[0].instrument), func(value):
			preferred_choices[0]["instrument"] = value
			resolve_player_choice(0)
			save_settings()
			show_menu())
		mobile_choice(row, selected.charts[choices[0].instrument].keys(), str(choices[0].difficulty), func(value):
			choices[0]["difficulty"] = value
			preferred_choices[0]["difficulty"] = value
			save_settings())
		var profile = LineEdit.new()
		profile.text = profile_names[0]
		profile.placeholder_text = "Player name"
		profile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(profile)
		profile.text_changed.connect(func(value): profile_names[0] = clean_profile(value, 0); save_settings())
		button_into(row, "Records", show_leaderboard)
	status_label = label_into(root, last_message, 16, MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	request_preview()
	queue_redraw()

func mobile_choice(parent: Node, items: Array, current: String, callback: Callable) -> void:
	var field = OptionButton.new()
	field.custom_minimum_size = Vector2(150, 54)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in items:
		field.add_item(str(item))
	field.select(maxi(0, items.find(current)))
	field.item_selected.connect(func(index): callback.call(str(items[index])))
	parent.add_child(field)

func start_game() -> void:
	fingers.clear()
	super.start_game()
	if screen == "game":
		add_pause_button()

func add_pause_button() -> void:
	var button = button_into(ui, "Ⅱ", toggle_pause)
	button.position = Vector2(size.x - 110, 12)
	button.custom_minimum_size = Vector2(64, 54)
	button.disabled = online_game

func lane_at(position: Vector2) -> int:
	# Four broad touch zones span the screen; notes remain centered above them.
	return clampi(int(position.x / (size.x / 4.0)), 0, 3)

func release_finger(index: int) -> void:
	if not fingers.has(index):
		return
	var lane: int = int(fingers[index])
	fingers.erase(index)
	if not fingers.values().has(lane) and not runs.is_empty():
		key_hit(0, lane, false)

func _input(event: InputEvent) -> void:
	if screen == "game" and not paused:
		if event is InputEventScreenTouch:
			if event.pressed and event.position.y >= highway_top():
				var lane = lane_at(event.position)
				var already = fingers.values().has(lane)
				fingers[event.index] = lane
				if not already: key_hit(0, lane, true)
			elif not event.pressed:
				release_finger(event.index)
			return
		# Each finger stays bound to its original lane until lifted, avoiding accidental slides.
		if event is InputEventScreenDrag:
			return
	super._input(event)

func toggle_pause() -> void:
	if online_game: return
	for index in fingers.keys(): release_finger(int(index))
	super.toggle_pause()
	if not paused: add_pause_button()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if screen == "game": toggle_pause()
		elif screen != "menu": show_menu()
		else: get_tree().quit()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		for index in fingers.keys(): release_finger(int(index))
	super._notification(what)

func highway_top() -> float:
	return 94.0

func highway_hit() -> float:
	return size.y - 85.0

func draw_player_hud(r: Dictionary, _p: int, x: float, track_w: float) -> void:
	var acc: float = 100.0 * float(r.raw_score) / maxf(300, float(r.judged) * 300) if r.judged > 0 else 100.0
	text_at(Vector2(x, 85), "%s · %s · %s" % [r.profile, choices[0].instrument, choices[0].difficulty], 16, COLORS[0], track_w * 0.48)
	text_at(Vector2(x + track_w * 0.5, 85), "%06d   %d streak   %d×   %.1f%%" % [r.score, r.combo, r.multiplier, acc], 16, WHITE, track_w * 0.5)

func _draw() -> void:
	super._draw()
	if screen != "game": return
	draw_set_transform(Vector2.ZERO)
	for lane in range(4):
		var rect = Rect2(lane * size.x / 4.0 + 3, size.y - 62, size.x / 4.0 - 6, 58)
		var tint: Color = LANE_COLORS[lane]
		tint.a = 0.45 if fingers.values().has(lane) else 0.13
		draw_rect(rect, tint)
		text_at(rect.position + Vector2(rect.size.x / 2 - 8, 37), str(lane + 1), 24)

func show_settings() -> void:
	screen = "settings"
	var root = mobile_page("SETTINGS")
	var tabs = TabContainer.new()
	tabs.custom_minimum_size.y = 435
	root.add_child(tabs)
	var mix = settings_page(tabs, "Audio", "THE MIX", "Headphones recommended. Bluetooth can add latency.")
	for item in [["Master", "volume"], ["Music", "music_volume"], ["Preview", "preview_volume"], ["Hit", "hit_volume"], ["Miss", "miss_volume"]]:
		add_audio_slider(mix, item[0], item[1])
	var timing = settings_page(tabs, "Play", "TIMING & NOTES", "Tap anywhere below the header in one of four screen columns.")
	label_into(timing, "Note speed (pixels/sec)")
	var speed = LineEdit.new()
	speed.text = str(scroll_speed)
	timing.add_child(speed)
	speed.text_submitted.connect(func(_value): apply_note_speed(speed); save_settings())
	button_into(timing, "Apply speed", func(): apply_note_speed(speed); save_settings())
	mobile_slider(timing, "Input delay (ms)", "offset_ms", -300, 300)
	add_calibration_panel(timing)
	mobile_choice(timing, ["Bar", "Circle", "Arrow", "Square"], note_style, func(value): note_style = value; save_settings())
	var visual = settings_page(tabs, "Visuals", "STAGE", "Adjust effects for battery life and visibility.")
	mobile_slider(visual, "Video brightness", "video_opacity", 0, 1)
	mobile_slider(visual, "Highway opacity", "highway_opacity", 0, 1)
	for key in visual_effects.keys(): add_effect_toggle(visual, str(key).capitalize(), str(key))
	var hype = settings_page(tabs, "Hype", "HYPE", "Song-synced bonus moments.")
	for key in ["bonus", "sensitivity", "glow", "rings", "shake"]: add_hype_slider(hype, key.capitalize(), key)
	var connection = settings_page(tabs, "Songs & AI", "ON-DEVICE IMPORTER", "Six-stem audio analysis runs on this phone. AI is optional and needs internet/API credit.")
	button_into(connection, "Manage / import songs", show_mobile_library)
	if native_importer != null:
		button_into(connection, "Update media downloader", func(): native_importer.update_downloader())
		button_into(connection, "Enter private Claude API key", func(): native_importer.enter_key())
		button_into(connection, "Remove API key", func(): native_importer.clear_key())
		button_into(connection, "Refresh available Claude models", func(): native_importer.list_models())
		label_into(connection, "Selected model: " + str(native_importer.get_model()), 16)
		model_list = box_into(connection)
		native_last_status = ""
		poll_native_import.call_deferred()
	else:
		label_into(connection, "Install the standalone APK to enable phone generation.", 17)

func mobile_slider(parent: Node, title: String, property: String, minimum: float, maximum: float) -> void:
	var caption = label_into(parent, title + ": " + str(get(property)))
	var slider = HSlider.new()
	slider.custom_minimum_size.y = 48
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 1 if maximum > 1 else 0.01
	slider.value = float(get(property))
	parent.add_child(slider)
	slider.value_changed.connect(func(value): set(property, value); caption.text = title + ": " + str(snappedf(value, slider.step)); save_settings())

func show_mobile_library() -> void:
	screen = "library"
	var root = mobile_page("SONGS / DOWNLOADS")
	phone_status = label_into(root, "Full generation runs on this device. Long songs may take several minutes; you can cancel below.", 17)
	phone_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var link = LineEdit.new()
	link.placeholder_text = "YouTube or SoundCloud URL"
	root.add_child(link)
	var ai = CheckBox.new()
	ai.text = "Claude-assisted charts (uses API credit)"
	ai.button_pressed = ai_enabled
	ai.toggled.connect(func(value): ai_enabled = value)
	root.add_child(ai)
	button_into(root, "Generate on this device", func():
		if native_importer != null: native_importer.generate(link.text, song_root, ai_enabled)
		else: message_phone("Install the standalone APK to use this feature."))
	button_into(root, "Regenerate selected chart", func():
		if native_importer != null and not selected.is_empty() and str(selected.get("category", "")) in ["YouTube", "SoundCloud"]:
			native_importer.regenerate(str(selected.folder), song_root, ai_enabled)
		else: message_phone("Select an imported online song first."))
	var cards = box_into(root, true)
	button_into(cards, "Import song cards", func():
		if native_importer != null: native_importer.import_cards(song_root))
	button_into(cards, "Export selected card", func():
		if native_importer != null and not selected.is_empty() and str(selected.get("category", "")) in ["YouTube", "SoundCloud"]:
			native_importer.export_card(str(selected.folder), str(selected.title), song_root)
		else: message_phone("Select an imported YouTube or SoundCloud song first."))
	button_into(cards, "Cancel import", func():
		if native_importer != null: native_importer.cancel())
	label_into(root, "ON THIS DEVICE", 22)
	for song in songs:
		var row = box_into(root, true)
		var title = label_into(row, str(song.title), 18)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.custom_minimum_size.x = 300
		button_into(row, "Select", func(): selected = song; show_menu())
		if str(song.folder).begins_with(song_root + "/"):
			button_into(row, "Delete", func(): confirm_mobile_delete(song))

func confirm_mobile_delete(song: Dictionary) -> void:
	var dialog = ConfirmationDialog.new()
	dialog.dialog_text = "Delete downloaded files for " + str(song.title) + "? Personal bests are kept."
	add_child(dialog)
	dialog.confirmed.connect(func():
		remove_song_dir(str(song.folder))
		scan_songs()
		show_mobile_library()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(600, 180))

func remove_song_dir(path: String) -> void:
	if not path.begins_with(song_root + "/"): return
	for file in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(file))
	for folder in DirAccess.get_directories_at(path): remove_song_dir(path.path_join(folder))
	DirAccess.remove_absolute(path)

func message_phone(message: String) -> void:
	last_message = message
	if is_instance_valid(phone_status): phone_status.text = message
	if is_instance_valid(status_label): status_label.text = message

func companion_request(path: String, method: int = HTTPClient.METHOD_GET, body: String = "") -> Dictionary:
	if not companion_url.begins_with("http://") and not companion_url.begins_with("https://"):
		message_phone("Set your companion address and token in Settings > Songs.")
		return {}
	var request = HTTPRequest.new()
	request.timeout = 25
	add_child(request)
	var error = request.request(companion_url + path, ["Authorization: Bearer " + companion_token, "Content-Type: application/json"], method, body)
	if error != OK:
		request.queue_free()
		message_phone("Cannot start connection: " + error_string(error))
		return {}
	var response: Array = await request.request_completed
	request.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200:
		message_phone("Companion unavailable or rejected request (%s). Check address, token and Wi-Fi." % response[1])
		return {}
	var parser = JSON.new()
	if parser.parse(response[3].get_string_from_utf8()) != OK or not parser.data is Dictionary: return {}
	return parser.data

func browse_companion(root: Node) -> void:
	message_phone("Loading companion library…")
	var data = await companion_request("/songs")
	if not is_instance_valid(root): return
	for song in data.get("songs", []):
		button_into(root, "Download · " + str(song.title), func(): download_mobile_song(str(song.id)))
	message_phone("Choose a song to download. Existing downloads are preserved.")

func request_generation(source: String) -> void:
	var result = await companion_request("/generate", HTTPClient.METHOD_POST, JSON.stringify({"source": source}))
	if not result.has("job"): return
	while is_inside_tree():
		await get_tree().create_timer(3).timeout
		var status = await companion_request("/jobs/" + str(result.job))
		if status.is_empty(): return
		message_phone(str(status.get("message", "Generating…")))
		if status.get("state") == "error": return
		if status.get("state") == "done":
			message_phone("Song ready. Browse companion songs to download it.")
			return

func download_mobile_song(id: String) -> void:
	var request = HTTPRequest.new()
	request.timeout = 600
	var archive = "user://song-" + str(Time.get_ticks_usec()) + ".zip"
	request.download_file = archive
	add_child(request)
	message_phone("Downloading song… keep the app open.")
	var error = request.request(companion_url + "/pack/" + id.uri_encode(), ["Authorization: Bearer " + companion_token])
	if error != OK: request.queue_free(); return
	var response: Array = await request.request_completed
	request.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200:
		DirAccess.remove_absolute(archive)
		message_phone("Song download failed. Your existing songs are unchanged.")
		return
	var result = install_mobile_pack(archive)
	DirAccess.remove_absolute(archive)
	message_phone(result)
	scan_songs()

func install_mobile_pack(archive: String) -> String:
	var reader = ZIPReader.new()
	if reader.open(archive) != OK: return "Invalid song pack."
	var metadata = JSON.new()
	if metadata.parse(reader.read_file("song.json").get_string_from_utf8()) != OK or not valid_song(metadata.data):
		reader.close()
		return "Invalid song metadata."
	var song: Dictionary = metadata.data
	for installed in songs:
		if str(installed.get("id", "")) == str(song.get("id", "")):
			reader.close()
			return "This song is already downloaded. Delete it first to replace its chart."
	var destination = song_root.path_join("mobile-" + str(song.id).sha256_text().left(24))
	if DirAccess.dir_exists_absolute(destination):
		reader.close()
		return "This song is already downloaded."
	var staging = song_root.path_join(".incoming-" + str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(staging)
	var total: int = 0
	var ok = true
	for file in reader.get_files():
		if file.ends_with("/"): continue
		if file.contains("/") or file.contains("\\") or file.contains(":") or file.begins_with("."):
			ok = false
			break
		var bytes = reader.read_file(file)
		total += bytes.size()
		if total > 1073741824: ok = false; break
		var output = FileAccess.open(staging.path_join(file), FileAccess.WRITE)
		if output == null: ok = false; break
		output.store_buffer(bytes)
		output.close()
	reader.close()
	if not FileAccess.file_exists(staging.path_join(str(song.audio))): ok = false
	if not ok:
		remove_song_dir(staging)
		return "Song installation failed; pack invalid or storage full."
	if DirAccess.rename_absolute(staging, destination) != OK:
		remove_song_dir(staging)
		return "Could not finish installation."
	return "Downloaded " + str(song.title) + ". Available offline."

func start_import(_kind: String, _source: String, _extra: Dictionary = {}) -> void:
	show_mobile_library()

func show_online_menu() -> void:
	super.show_online_menu()
	# Hosting uses an existing companion/lobby server, never a Windows executable.
	mobile_online_labels(ui)

func mobile_online_labels(node: Node) -> void:
	if node is OptionButton and node.item_count == 2 and node.get_item_text(0) == "LAN":
		if not node.has_meta("phone_mode"):
			node.set_meta("phone_mode", true)
			node.item_selected.connect(func(_index): mobile_online_labels.call_deferred(ui))
	if node is Label and "Up to four PCs" in node.text:
		node.text = "One touch player per device · LAN or internet server"
	if node is CheckBox and "Start a LAN server" in node.text:
		node.button_pressed = false
		node.disabled = true
		node.hide()
	for child in node.get_children(): mobile_online_labels(child)

func network_source_song() -> Dictionary:
	var song: Dictionary = selected.duplicate(true)
	if str(song.get("folder", "")).begins_with("res://"):
		var destination = ProjectSettings.globalize_path("user://shared-demo")
		DirAccess.make_dir_recursive_absolute(destination)
		var path = destination.path_join("audio.wav")
		if not FileAccess.file_exists(path):
			var stream = load(str(song.folder).path_join("audio.wav")) as AudioStreamWAV
			if stream != null: stream.save_to_wav(path)
		song.folder = destination
	return song

func show_results() -> void:
	super.show_results()
	# Reuse score/calibration persistence, but allow the result card to scroll on phones.
	for child in ui.get_children():
		if child is CenterContainer and child.get_child_count() > 0:
			var panel = child.get_child(0)
			child.remove_child(panel)
			ui.remove_child(child)
			child.queue_free()
			var scroll = ScrollContainer.new()
			scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			scroll.offset_left = 44
			scroll.offset_right = -44
			scroll.offset_top = 12
			scroll.offset_bottom = -12
			ui.add_child(scroll)
			scroll.add_child(panel)
			panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			break

func apply_window_mode() -> void:
	if OS.has_feature("android"):
		fullscreen = true
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		super.apply_window_mode()

func poll_native_import() -> void:
	if native_importer == null: return
	var raw: String = str(native_importer.get_status())
	if raw == native_last_status: return
	native_last_status = raw
	var status = JSON.parse_string(raw)
	if not status is Dictionary: return
	message_phone(str(status.get("message", "")))
	if status.get("state") == "done":
		scan_songs()
		if not status.get("warnings", []).is_empty(): message_phone(last_message + " · " + str(status.warnings))
	if status.get("state") == "models" and is_instance_valid(model_list):
		for child in model_list.get_children(): child.queue_free()
		for entry in status.get("models", []):
			var model_id: String = str(entry.get("id", ""))
			button_into(model_list, str(entry.get("display_name", model_id)), func():
				native_importer.set_model(model_id)
				show_settings())
