extends Control

const GraphicSkin = preload("res://game/graphic_skin.gd")
const COLORS = [Color("64bbff"), Color("ff745f"), Color("ffda56"), Color("79dfaa")]
const LANE_COLORS = [Color("64bbff"), Color("ff745f"), Color("ffda56"), Color("79dfaa")]
const WHITE = Color("f3f6ff")
const MUTED = Color("abb4e0")
const WINDOW = 0.160
const CoverPlaceholder = preload("res://game/ui/cover_placeholder.svg")
const DiscButton = preload("res://game/disc_button.gd")
var ui_motion = preload("res://game/ui_motion.gd").new()
var fullscreen: bool = false
var last_card_export_dir: String = ""
var settings_tab: int = 0
var import_expanded: bool = false
var reduced_motion: bool = false
var ui_clock: float = 0.0
var ui_redraw_time: float = 0.0
const Calibration = preload("res://game/calibration.gd")
var last_timing: Array = []
const Hype = preload("res://game/hype.gd")
var hype_settings: Dictionary = {"enabled": true, "bonus": 2.0, "sensitivity": 0.5, "glow": 0.6, "rings": 0.6, "shake": 0.3}

const ScoreStore = preload("res://game/score_store.gd")
const NOTE_TEXTURES = {"Circle": preload("res://game/notes/circle.svg"), "Arrows": preload("res://game/notes/arrow.svg"), "Square": preload("res://game/notes/square.svg")}
const NOTE_STYLES = ["Bar", "Circle", "Arrows", "Square"]
var note_style: String = "Bar"
var profile_names: Array = ["Player 1", "Player 2", "Player 3", "Player 4"]
var score_store = ScoreStore.new()
var results_recorded: bool = false
var board_instrument: String = ""
var board_difficulty: String = ""
const DEFAULT_KEYS = [[KEY_A, KEY_S, KEY_D, KEY_F], [KEY_J, KEY_K, KEY_L, KEY_SEMICOLON], [KEY_Q, KEY_W, KEY_E, KEY_R], [KEY_U, KEY_I, KEY_O, KEY_P]]
var bindings: Array = DEFAULT_KEYS.duplicate(true)
var players_count: int = 1
var choices: Array = [{}, {}, {}, {}]
var preferred_choices: Array = [{}, {}, {}, {}]
var preview: AudioStreamPlayer
var preview_id: String = ""
var preview_start: float = 0.0
var preview_elapsed: float = 0.0
var preview_delay: float = 0.0
var carousel_direction: int = 0
var covers = preload("res://game/song_covers.gd").new()
var songs: Array = []
var filtered: Array = []
var selected: Dictionary = {}
var category: String = "All songs"
var screen: String = "menu"
var ui: Control
var audio: AudioStreamPlayer
var background_image: TextureRect
var background_video: VideoStreamPlayer
var video_opacity: float = 0.22
var highway_opacity: float = 0.82
var status_label: Label
var import_progress: ProgressBar
var file_dialog: FileDialog
var pending_key: Vector2i = Vector2i(-1, -1)
var offset_ms: float = 0.0
var scroll_speed: float = 515.0 / 1.7
var volume: float = 0.8
var music_volume: float = 1.0
var preview_volume: float = 0.55
var hit_volume: float = 0.7
var miss_volume: float = 0.6
var preview_paused: bool = false
var song_search: String = ""
var hit_audio: AudioStreamPlayer
var miss_audio: AudioStreamPlayer
var last_sound: Array = [-1000, -1000]
var visual_effects: Dictionary = {"lane_flashes": true, "hit_rings": true, "hit_sparks": true, "combo_glow": true, "judgements": true, "note_trails": false, "miss_flash": false, "hold_shimmer": true, "audio_visualizer": true, "bass_glow": false}
var music_visualizer = preload("res://game/music_visualizer.gd").new()
var time_s: float = -2.0
var run_length: float = 0.0
var playing: bool = false
var paused: bool = false
var runs: Array = []
var worker_pid: int = -1
var job_result: String = ""
var job_timer: float = 0.0
var last_message: String = "Choose a song, invite a friend, and press Play."
var song_root: String
var font: Font
var online = preload("res://game/online_client.gd").new()
var pack_transfer = preload("res://game/pack_transfer.gd").new()
var online_game: bool = false
var online_launch: bool = false
var online_start_at: float = 0.0
var offline_players: int = 1
var online_fingerprint: String = ""
var online_message: String = ""
var online_url: String = "http://127.0.0.1:27440"
var online_room: String = ""
var online_mode: int = 0


func _ready() -> void:
	call_deferred("cleanup_old_installs")
	add_child(ui_motion)
	add_child(online)
	pack_transfer.lobby = online
	add_child(pack_transfer)
	pack_transfer.progress.connect(func(message):
		online_message = message
		update_online_lobby())
	pack_transfer.failed.connect(func(message):
		online_message = message
		update_online_lobby())
	pack_transfer.downloaded.connect(install_online_pack)
	pack_transfer.published.connect(update_online_lobby)
	online.joined.connect(func():
		online_message = "Connected to lobby."
		offline_players = players_count
		players_count = 1
		show_online_menu()
		if online.is_host():
			pack_transfer.begin_upload(network_source_song()))
	online.changed.connect(update_online_lobby)
	online.problem.connect(func(message):
		online_message = message
		update_online_lobby())
	online.disconnected.connect(abort_online)
	online.round_started.connect(begin_online_round)
	online.round_cancelled.connect(func():
		online_game = false
		online_start_at = 0.0
		audio.stop()
		stop_background_video()
		show_online_menu())
	font = ThemeDB.fallback_font
	song_root = ProjectSettings.globalize_path("user://songs")
	DirAccess.make_dir_recursive_absolute(song_root)
	audio = AudioStreamPlayer.new()
	add_child(audio)
	add_child(music_visualizer)
	audio.bus = music_visualizer.bus_name
	preview = AudioStreamPlayer.new()
	add_child(preview)
	hit_audio = AudioStreamPlayer.new()
	miss_audio = AudioStreamPlayer.new()
	add_child(hit_audio)
	add_child(miss_audio)
	hit_audio.max_polyphony = 8
	miss_audio.max_polyphony = 2
	hit_audio.stream = make_feedback_sound(false)
	miss_audio.stream = make_feedback_sound(true)
	add_child(covers)
	covers.available.connect(func(_id):
		if screen == "menu":
			refresh_carousel_covers())
	background_image = TextureRect.new()
	background_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	background_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_image.show_behind_parent = true
	background_image.visible = false
	add_child(background_image)
	background_video = VideoStreamPlayer.new()
	background_video.expand = true
	background_video.show_behind_parent = true
	background_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_video.volume = 0.0
	background_video.visible = false
	add_child(background_video)
	resized.connect(layout_background_video)
	layout_background_video()
	get_window().files_dropped.connect(func(files):
		if files.size() == 1 and str(files[0]).get_extension().to_lower() == "png" and worker_pid <= 0 and screen != "game":
			start_import("card_import", str(files[0])))
	load_settings()
	score_store.load_data()
	apply_theme()
	scan_songs()
	show_menu()
	get_window().focus_exited.connect(func():
		if screen == "game" and not paused and not online_game:
			toggle_pause())

func apply_theme() -> void:
	theme = GraphicSkin.make_theme()

func menu_ink(color: Color) -> Color:
	if color == WHITE: return GraphicSkin.INK
	if color == MUTED: return GraphicSkin.QUIET
	if color == Color("fa7f96"): return GraphicSkin.RED
	for index in range(COLORS.size()):
		if color == COLORS[index]: return [GraphicSkin.BLUE, GraphicSkin.RED, GraphicSkin.OCHRE, GraphicSkin.GREEN][index]
	return color

func load_settings() -> void:
	if FileAccess.file_exists("user://last-timing.json"):
		var parser = JSON.new()
		if parser.parse(FileAccess.get_file_as_string("user://last-timing.json")) == OK and parser.data is Array:
			last_timing = parser.data
	if FileAccess.file_exists("user://settings.json"):
		var data = JSON.parse_string(FileAccess.get_file_as_string("user://settings.json"))
		if data is Dictionary:
			offset_ms = clampf(float(data.get("offset", 0)), -300, 300)
			var old_travel: float = float(data.get("approach", 1.7))
			if not is_finite(old_travel) or old_travel <= 0:
				old_travel = 1.7
			var saved_speed: float = float(data.get("scroll_speed", 515.0 / old_travel))
			if is_finite(saved_speed) and saved_speed > 0:
				scroll_speed = saved_speed
			volume = clampf(float(data.get("volume", 0.8)), 0, 1)
			for property in ["music_volume", "preview_volume", "hit_volume", "miss_volume"]:
				var amount: float = float(data.get(property, get(property)))
				if is_finite(amount):
					set(property, clampf(amount, 0, 1))
			preview_paused = bool(data.get("preview_paused", false))
			reduced_motion = bool(data.get("reduced_motion", false))
			fullscreen = bool(data.get("fullscreen", false))
			last_card_export_dir = str(data.get("last_card_export_dir", ""))
			var saved_effects = data.get("visual_effects", {})
			if saved_effects is Dictionary:
				for effect in visual_effects:
					visual_effects[effect] = bool(saved_effects.get(effect, visual_effects[effect]))
			var saved_hype = data.get("hype_settings", {})
			if saved_hype is Dictionary:
				hype_settings.enabled = bool(saved_hype.get("enabled", true))
				for key in ["bonus", "sensitivity", "glow", "rings", "shake"]:
					var amount: float = float(saved_hype.get(key, hype_settings[key]))
					if is_finite(amount):
						hype_settings[key] = clampf(amount, 1.0 if key == "bonus" else 0.0, 3.0 if key == "bonus" else 1.0)
			players_count = clampi(int(data.get("players_count", 1)), 1, 4)
			highway_opacity = clampf(float(data.get("highway_opacity", 0.82)), 0, 1)
			video_opacity = clampf(float(data.get("video_opacity", 0.22)), 0, 1.0)
			if str(data.get("note_style", "Bar")) in NOTE_STYLES:
				note_style = str(data.get("note_style", "Bar"))
			var preferences = data.get("player_choices", [])
			if preferences is Array and preferences.size() == 4:
				for p in range(4):
					if preferences[p] is Dictionary:
						preferred_choices[p] = preferences[p].duplicate()
			var names = data.get("profiles", [])
			if names is Array and names.size() == 4:
				for p in range(4):
					profile_names[p] = clean_profile(str(names[p]), p)
			var keys = data.get("bindings", [])
			var seen: Array = []
			var valid: bool = keys is Array and keys.size() == 4
			if valid:
				for row in keys:
					if not row is Array or row.size() != 4:
						valid = false
						break
					for key in row:
						if int(key) <= 0 or int(key) in seen or int(key) in [KEY_ESCAPE, KEY_F5, KEY_F11]:
							valid = false
						seen.append(int(key))
			if valid:
				bindings = keys
	ui_motion.reduced = reduced_motion
	apply_window_mode()
	apply_audio_levels()

func save_settings() -> void:
	var f = FileAccess.open("user://settings.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"last_card_export_dir": last_card_export_dir, "fullscreen": fullscreen, "reduced_motion": reduced_motion, "hype_settings": hype_settings, "music_volume": music_volume, "preview_volume": preview_volume, "hit_volume": hit_volume, "miss_volume": miss_volume, "preview_paused": preview_paused, "visual_effects": visual_effects, "player_choices": preferred_choices, "offset": offset_ms, "scroll_speed": scroll_speed, "volume": volume, "bindings": bindings, "note_style": note_style, "profiles": profile_names, "video_opacity": video_opacity, "highway_opacity": highway_opacity, "players_count": offline_players if online.connected() else players_count}))

func valid_song(data) -> bool:
	if not data is Dictionary or data.get("schema", 0) != 1 or not data.get("charts") is Dictionary:
		return false
	if data.get("audio", "") != "audio.wav":
		return false
	var count: int = 0
	for instrument in data.charts:
		if not data.charts[instrument] is Dictionary:
			return false
		for difficulty in data.charts[instrument]:
			var notes = data.charts[instrument][difficulty]
			if not notes is Array or notes.size() > 100000:
				return false
			var last: float = -1.0
			for note in notes:
				if not note is Dictionary:
					return false
				var at: float = float(note.get("t", -1))
				var lane: int = int(note.get("lane", -1))
				var end: float = float(note.get("end", -1))
				if not is_finite(at) or not is_finite(end) or at < last or at < 0 or end < at or lane < 0 or lane > 3:
					return false
				last = at
			count += notes.size()
	return count > 0

func scan_songs() -> void:
	songs.clear()
	var demo = JSON.parse_string(FileAccess.get_file_as_string("res://game/demo/song.json"))
	if valid_song(demo):
		demo["folder"] = "res://game/demo"
		songs.append(demo)
	for folder in DirAccess.get_directories_at(song_root):
		if folder.begins_with("."):
			continue
		var path = song_root.path_join(folder)
		if not FileAccess.file_exists(path.path_join("song.json")):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(path.path_join("song.json")))
		if valid_song(data) and FileAccess.file_exists(path.path_join(data.audio)):
			var readable_path: String = song_root.path_join(song_folder_name(data))
			if path != readable_path and not DirAccess.dir_exists_absolute(readable_path):
				if DirAccess.rename_absolute(path, readable_path) == OK:
					path = readable_path
			data["folder"] = path
			cap_generated_holds(data)
			songs.append(data)
	if not selected.is_empty():
		for song in songs:
			if song.id == selected.id:
				selected = song
				break
	if selected.is_empty() and not songs.is_empty():
		selected = songs[0]

func clear_ui() -> void:
	if screen != "menu" and not ui_motion.launching:
		stop_preview()
	var previous: Control = ui if is_instance_valid(ui) else null
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(ui)
	ui_motion.swap(previous, ui, "pause" if screen == "game" and paused else screen)

func label_into(parent: Node, text: String, size_px: int = 18, color: Color = WHITE) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	if size_px >= 24:
		l.add_theme_font_override("font", GraphicSkin.font(true))
	l.add_theme_color_override("font_color", menu_ink(color))
	parent.add_child(l)
	return l

func button_into(parent: Node, text: String, callback: Callable) -> Button:
	var b = Button.new()
	b.text = text
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func box_into(parent: Node, horizontal: bool = false) -> BoxContainer:
	var box: BoxContainer = HBoxContainer.new() if horizontal else VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	parent.add_child(box)
	return box

func show_menu() -> void:
	if online.connected() and not online.leaving:
		show_online_menu()
		return
	if screen == "menu":
		commit_player_names()
	if screen == "settings" and not commit_preferences():
		return
	filtered.clear()
	for song in songs:
		if (category == "All songs" or song.category == category) and song_matches_search(song):
			filtered.append(song)
	if not selected.is_empty() and not filtered.any(func(song): return song.id == selected.id):
		selected = {}
	if selected.is_empty() and not filtered.is_empty():
		selected = filtered[0]
	for p in range(4):
		resolve_player_choice(p)
	var retained_carousel: Control = null
	if screen == "menu" and carousel_direction != 0 and is_instance_valid(ui):
		retained_carousel = ui.find_child("SongCarousel", true, false) as Control
		if retained_carousel != null:
			retained_carousel.get_parent().remove_child(retained_carousel)
	screen = "menu"
	paused = false
	audio.stop()
	stop_background_video()
	clear_ui()
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	ui.add_child(margin)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var root = box_into(scroll)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header = box_into(root, true)
	var body = box_into(root, true)
	body.name = "CabinetBody"
	var stage = box_into(body)
	stage.name = "MusicStage"
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var library_row = box_into(stage, true)
	var cats = OptionButton.new()
	cats.name = "SongCategory"
	var category_values: Array = ["All songs", "YouTube", "osu!mania"]
	for item in ["All songs", "YouTube songs", "osu beatmaps"]:
		cats.add_item(item)
	cats.select(maxi(0, category_values.find(category)))
	cats.custom_minimum_size.x = 190
	cats.item_selected.connect(func(i):
		category = category_values[i]
		show_menu())
	library_row.add_child(cats)
	var search = LineEdit.new()
	search.name = "SongSearch"
	search.placeholder_text = "Search songs or artists…"
	search.text = song_search
	search.clear_button_enabled = true
	search.custom_minimum_size.x = 190
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_row.add_child(search)
	search.text_changed.connect(func(value):
		var caret: int = search.caret_column
		song_search = value
		show_menu()
		var replacement = ui.find_child("SongSearch", true, false) as LineEdit
		replacement.grab_focus()
		replacement.caret_column = caret)
	var logo = label_into(header, "PULSE FOUR //", 38, COLORS[0])
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	logo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var multiplayer_menu = MenuButton.new()
	multiplayer_menu.name = "MultiplayerMenu"
	multiplayer_menu.text = "Multiplayer  ▾"
	header.add_child(multiplayer_menu)
	multiplayer_menu.get_popup().add_item("Host / join LAN lobby", 0)
	multiplayer_menu.get_popup().add_item("Host / join Internet lobby", 1)
	multiplayer_menu.get_popup().id_pressed.connect(func(id):
		online_mode = id
		online_url = "http://127.0.0.1:27440" if id == 0 else online_url
		open_online())
	multiplayer_menu.disabled = selected.is_empty() or worker_pid > 0
	button_into(header, "Settings", show_settings)
	var masthead = box_into(stage)
	label_into(masthead, "MUSIC SELECT", 30, WHITE)
	var subtitle = label_into(masthead, "STAGE 01    /    SELECT YOUR TRACK", 13, COLORS[0])
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var board = box_into(stage)
	board.name = "MenuLeaderboard"
	refresh_menu_leaderboard()
	var carousel: Control = retained_carousel if retained_carousel != null else Control.new()
	carousel.name = "SongCarousel"
	carousel.custom_minimum_size.y = 300
	carousel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.add_child(carousel)
	if retained_carousel == null:
		carousel.resized.connect(func():
			if not bool(carousel.get_meta("transition_pending", false)):
				layout_carousel(carousel))
	build_carousel(carousel)
	var play_row = box_into(stage, true)
	play_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_into(play_row, "◀", func(): move_song(-1)).disabled = filtered.size() < 2
	var play = DiscButton.new()
	play_row.add_child(play)
	play.pressed.connect(func(): request_play(play))
	play.name = "PlaySong"
	play.custom_minimum_size = Vector2(188, 72)
	play.disabled = selected.is_empty()
	var preview_button = button_into(play_row, "Resume preview" if preview_paused else "Pause preview", toggle_preview)
	preview_button.name = "PreviewToggle"
	preview_button.tooltip_text = "Pause stays enabled while browsing and after restarting the game."
	button_into(play_row, "▶", func(): move_song(1)).disabled = filtered.size() < 2
	stage.move_child(board, -1)
	var panel = PanelContainer.new()
	panel.name = "PlayerDock"
	panel.custom_minimum_size.x = 340
	body.add_child(panel)
	var player_scroll = ScrollContainer.new()
	player_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	player_scroll.custom_minimum_size.y = 530
	panel.add_child(player_scroll)
	var setup = box_into(player_scroll)
	setup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var count_row = box_into(setup)
	label_into(count_row, "PLAYER ENTRY", 24, COLORS[1])
	label_into(count_row, "Players", 16)
	var count = OptionButton.new()
	count.name = "PlayerCount"
	for i in range(1, 5):
		count.add_item(str(i))
	count.select(players_count - 1)
	count.item_selected.connect(func(i):
		players_count = i + 1
		save_settings()
		show_menu())
	count_row.add_child(count)
	button_into(count_row, "Reset keys", func():
		bindings = DEFAULT_KEYS.duplicate(true)
		save_settings()
		show_menu())
	for p in range(players_count):
		player_setup(setup, p)
	var import_panel = PanelContainer.new()
	root.add_child(import_panel)
	var import_content = box_into(import_panel)
	var import_toggle = button_into(import_content, "SONG LIBRARY  /  IMPORT & TOOLS", func():
		import_expanded = not import_expanded
		show_menu())
	import_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var import_drawer = box_into(import_content)
	import_drawer.visible = import_expanded or worker_pid > 0
	var cards_row = box_into(import_content, true)
	var import_card_button = button_into(cards_row, "Import song card", choose_song_card)
	import_card_button.name = "ImportSongCard"
	import_card_button.disabled = worker_pid > 0
	var export_button = button_into(cards_row, "Export card", export_song_card)
	export_button.name = "ExportSongCard"
	export_button.disabled = worker_pid > 0 or selected.get("category", "") != "YouTube"
	export_button.tooltip_text = "Share the thumbnail, charts and YouTube link. The receiver downloads the audio and video."
	label_into(import_drawer, "Send PNG cards as original files/documents; photo compression can remove their charts.", 13, MUTED)
	var import_row = box_into(import_drawer, true)
	label_into(import_row, "IMPORT", 16, COLORS[0])
	button_into(import_row, "osu / osz", choose_osu).disabled = worker_pid > 0
	var url = LineEdit.new()
	url.placeholder_text = "YouTube video link…"
	url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_row.add_child(url)
	button_into(import_row, "Import YouTube", func(): start_import("youtube", url.text.strip_edges())).disabled = worker_pid > 0
	button_into(import_row, "Songs folder", func(): OS.shell_open(song_root))
	if not selected.is_empty() and selected.get("category", "") == "YouTube":
		var regen_row = box_into(import_drawer, true)
		button_into(regen_row, "Regenerate chart", func(): start_import("regenerate", str(selected.folder))).disabled = worker_pid > 0
		if not FileAccess.file_exists(str(selected.folder).path_join("background.ogv")) and not FileAccess.file_exists(str(selected.folder).path_join("background.png")):
			button_into(regen_row, "Download video", func(): start_import("video", str(selected.folder))).disabled = worker_pid > 0
	status_label = label_into(root, last_message, 14, COLORS[0])
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	import_progress = ProgressBar.new()
	import_progress.custom_minimum_size.y = 8
	import_progress.show_percentage = false
	import_progress.visible = worker_pid > 0
	root.add_child(import_progress)
	if worker_pid > 0:
		button_into(root, "Cancel import", cancel_import)
	request_preview()
	queue_redraw()

func resolve_player_choice(p: int) -> void:
	if selected.is_empty():
		return
	var instruments: Array = selected.charts.keys()
	if instruments.is_empty():
		return
	var preferred: Dictionary = preferred_choices[p]
	var part: String = str(preferred.get("instrument", choices[p].get("instrument", "")))
	if not part in instruments:
		part = str(instruments[mini(p, instruments.size() - 1)])
	var diffs: Array = selected.charts[part].keys()
	var diff: String = str(preferred.get("difficulty", choices[p].get("difficulty", "")))
	if not diff in diffs:
		diff = str(diffs[0]) if not diffs.is_empty() else ""
	choices[p] = {"instrument": part, "difficulty": diff}
	if not preferred.has("instrument"):
		preferred["instrument"] = part
	if not preferred.has("difficulty"):
		preferred["difficulty"] = diff

func song_matches_search(song: Dictionary) -> bool:
	var haystack: String = (str(song.get("title", "")) + " " + str(song.get("artist", ""))).to_lower()
	for word in song_search.to_lower().split(" ", false):
		if not word in haystack:
			return false
	return true

func toggle_preview() -> void:
	preview_paused = not preview_paused
	preview.stream_paused = preview_paused
	var button = ui.find_child("PreviewToggle", true, false) as Button
	if button != null:
		button.text = "Resume preview" if preview_paused else "Pause preview"
	save_settings()

func move_song(direction: int) -> void:
	if filtered.is_empty() or direction == 0:
		return
	var index: int = 0
	for i in range(filtered.size()):
		if filtered[i].id == selected.get("id", ""):
			index = i
	carousel_direction = direction
	selected = filtered[posmod(index + direction, filtered.size())]
	show_menu()

func build_carousel(carousel: Control) -> void:
	carousel.set_meta("transition_pending", true)
	var old_cards: Dictionary = {}
	for child in carousel.get_children():
		if child.has_meta("song") and not child.get_meta("exiting", false):
			old_cards[str(child.get_meta("song").id)] = child
	if filtered.is_empty():
		var empty = label_into(carousel, "No matching songs. Clear your search or import a song below.", 22, MUTED)
		empty.position = Vector2(40, 90)
		return
	var index: int = 0
	for i in range(filtered.size()):
		if filtered[i].id == selected.id:
			index = i
	var offsets: Array = [0]
	if filtered.size() >= 2:
		offsets.append(1)
	if filtered.size() >= 3:
		offsets.append(-1)
	if filtered.size() >= 4:
		offsets.append(2)
	if filtered.size() >= 5:
		offsets.append(-2)
	offsets.sort_custom(func(a, b): return absi(int(a)) > absi(int(b)))
	for offset in offsets:
		var song: Dictionary = filtered[posmod(index + int(offset), filtered.size())]
		if old_cards.has(str(song.id)):
			var existing: Button = old_cards[str(song.id)]
			var previous_offset: int = int(existing.get_meta("offset"))
			# Cards crossing the wrap seam leave at one edge and enter at the other.
			if absi(previous_offset - int(offset)) <= 2:
				old_cards.erase(str(song.id))
				existing.set_meta("offset", int(offset))
				existing.z_index = (3 - absi(int(offset))) * 10
				existing.get_node("Caption").add_theme_font_size_override("font_size", 16 if offset == 0 else 13)
				carousel.move_child(existing, -1)
				continue
		var card = preload("res://game/song_card.gd").new()
		card.motion_source = self
		card.set_meta("entering", true)
		card.set_meta("offset", int(offset))
		card.set_meta("song", song)
		card.z_index = (3 - absi(int(offset))) * 10
		card.clip_contents = true
		card.tooltip_text = str(song.title) + " / " + str(song.artist)
		card.pressed.connect(func(): move_song(int(card.get_meta("offset"))))
		carousel.add_child(card)
		var cover = TextureRect.new()
		cover.name = "Cover"
		cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cover.offset_left = 5
		cover.offset_top = 5
		cover.offset_right = -5
		cover.offset_bottom = -62
		card.add_child(cover)
		cover.texture = covers.texture_for(song)
		if cover.texture == null:
			cover.texture = CoverPlaceholder
		var caption = Label.new()
		caption.name = "Caption"
		caption.text = str(song.title) + "\n" + str(song.artist)
		caption.add_theme_font_size_override("font_size", 16 if offset == 0 else 13)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(caption)
		caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		caption.offset_left = 8
		caption.offset_right = -8
		caption.offset_top = -58
		caption.offset_bottom = -8
	for card in old_cards.values():
		card.set_meta("exiting", true)
		card.disabled = true
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.z_index = 0
		stop_card_tween(card)
		var exit_motion = card.create_tween().set_parallel(true)
		card.set_meta("motion", exit_motion)
		exit_motion.tween_property(card, "position:x", card.position.x - carousel_direction * (0 if reduced_motion else 140), 0.32)
		exit_motion.tween_property(card, "modulate:a", 0.0, 0.32)
		exit_motion.chain().tween_callback(card.queue_free)
	var direction: int = carousel_direction
	carousel_direction = 0
	var generation: int = int(carousel.get_meta("generation", 0)) + 1
	carousel.set_meta("generation", generation)
	call_deferred("animate_carousel", carousel, direction, generation)

func animate_carousel(carousel, direction: int, generation: int) -> void:
	if not is_instance_valid(carousel) or not carousel.is_inside_tree() or int(carousel.get_meta("generation", -1)) != generation:
		return
	carousel.set_meta("transition_pending", false)
	carousel_direction = direction
	layout_carousel(carousel, true)
	carousel_direction = 0

func stop_card_tween(card: Control) -> void:
	# Godot logs an error for a missing key even with an explicit null default.
	if not card.has_meta("motion"):
		return
	var motion = card.get_meta("motion")
	card.remove_meta("motion")
	if motion is Tween and motion.is_valid():
		motion.kill()

func layout_carousel(carousel: Control, animate: bool = false) -> void:
	var center: float = carousel.size.x / 2.0
	var spacing: float = minf(190.0, carousel.size.x / 6.5)
	for card in carousel.get_children():
		if not card.has_meta("offset") or card.get_meta("exiting", false):
			continue
		var offset: int = int(card.get_meta("offset"))
		var factor: float = 1.0 - 0.18 * absi(offset)
		var target_size: Vector2 = Vector2(300, 220) * factor
		var target: Vector2 = Vector2(center + offset * spacing - target_size.x / 2, (carousel.size.y - target_size.y) / 2)
		var shade: float = 1.0 - 0.09 * absi(offset)
		var tint: Color = Color(shade, shade, shade, 1.0)
		stop_card_tween(card)
		if animate and carousel_direction != 0 and not reduced_motion:
			if card.get_meta("entering", false):
				card.position = target + Vector2(carousel_direction * spacing, 0)
				card.size = target_size * 0.8
				card.modulate.a = 0.0
			var motion = card.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			card.set_meta("motion", motion)
			motion.tween_property(card, "position", target, 0.36)
			motion.tween_property(card, "size", target_size, 0.36)
			motion.tween_property(card, "modulate", tint, 0.36)
		else:
			card.position = target
			card.size = target_size
			card.modulate = tint
		card.set_meta("entering", false)

func refresh_carousel_covers() -> void:
	var carousel = ui.find_child("SongCarousel", true, false)
	if carousel == null:
		return
	for card in carousel.get_children():
		if card.has_meta("song"):
			var texture = covers.texture_for(card.get_meta("song"))
			card.get_node("Cover").texture = texture if texture != null else CoverPlaceholder

func refresh_menu_leaderboard() -> void:
	var board = ui.find_child("MenuLeaderboard", true, false)
	if board == null:
		return
	for child in board.get_children():
		board.remove_child(child)
		child.queue_free()
	if selected.is_empty() or choices[0].is_empty():
		return
	var part: String = str(choices[0].instrument)
	var diff: String = str(choices[0].difficulty)
	var title_row = box_into(board, true)
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var board_title = label_into(title_row, "RECORDS  /  " + part + " · " + diff, 16, COLORS[2])
	board_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button_into(title_row, "All scores", func():
		board_instrument = part
		board_difficulty = diff
		show_leaderboard())
	var rows: Array = score_store.entries(chart_key_for(part, diff))
	var scores = HFlowContainer.new()
	board.add_child(scores)
	if rows.is_empty():
		label_into(scores, "No scores yet — set the first record!", 15, MUTED)
	for i in range(mini(3, rows.size())):
		label_into(scores, "%d. %s  ·  %s  ·  %d" % [i + 1, rows[i].name, ScoreStore.grade(float(rows[i].accuracy)), int(rows[i].score)], 16, COLORS[i])

func request_preview() -> void:
	var id: String = str(selected.get("id", "")) + ":" + str(selected.get("folder", ""))
	if id == preview_id:
		return
	preview.stop()
	preview.stream_paused = false
	preview.stream = null
	preview_id = id
	preview_delay = 0.3 if not selected.is_empty() else 0.0
	preview_elapsed = 0.0

func stop_preview() -> void:
	preview.stop()
	preview.stream = null
	preview_id = ""
	preview_delay = 0.0

func process_preview(delta: float) -> void:
	if screen != "menu":
		if not preview_id.is_empty():
			stop_preview()
		return
	if preview_paused:
		return
	preview.stream_paused = false
	if preview_delay > 0:
		preview_delay -= delta
		if preview_delay <= 0 and not selected.is_empty():
			preview.stream = load_song_audio()
			if preview.stream != null:
				var duration: float = preview.stream.get_length()
				preview_start = clampf(float(selected.get("preview_time", duration * 0.3)), 0.0, maxf(0.0, duration - 12.0))
				preview.play(preview_start)
				preview_elapsed = 0.0
	if preview.stream != null:
		preview_elapsed += delta
		var snippet: float = minf(12.0, maxf(0.2, preview.stream.get_length() - preview_start))
		var fade: float = minf(clampf(preview_elapsed / 0.4, 0, 1), clampf((snippet - preview_elapsed) / 0.6, 0, 1))
		preview.volume_db = linear_to_db(maxf(0.0001, volume * preview_volume * fade))
		if preview_elapsed >= snippet:
			preview_elapsed = 0.0
			preview.play(preview_start)

func apply_window_mode() -> void:
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	apply_window_mode()
	save_settings()
	if is_instance_valid(ui):
		var selector = ui.find_child("WindowMode", true, false) as OptionButton
		if selector != null: selector.select(1 if fullscreen else 0)

func settings_page(tabs: TabContainer, title: String, heading: String, description: String) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	scroll.add_child(margin)
	var content = box_into(margin) as VBoxContainer
	label_into(content, heading, 26, COLORS[tabs.get_tab_count() % 4])
	var hint = label_into(content, description, 16, MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return content

func show_settings() -> void:
	stop_preview()
	if screen == "menu":
		commit_player_names()
	if screen == "settings" and not commit_preferences():
		return
	screen = "settings"
	clear_ui()
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	ui.add_child(margin)
	var root = box_into(margin)
	var heading = box_into(root, true)
	var title = label_into(heading, "CONTROL ROOM.", 36, COLORS[0])
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_into(heading, "Back to songs", show_menu)
	var tabs = TabContainer.new()
	tabs.name = "SettingsCategories"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	var display = settings_page(tabs, "Display", "YOUR STAGE", "Choose how Pulse Four fills your screen.")
	var settings = settings_page(tabs, "Timing", "FIND YOUR FEEL", "Tune note travel and calibrate your last performance.")
	var audio_settings = settings_page(tabs, "Audio", "THE MIX", "Balance the song, previews and feedback.")
	var visuals = settings_page(tabs, "Notes & Video", "READ THE RHYTHM", "Shape your notes and the space behind them.")
	var effects = settings_page(tabs, "Effects", "LIGHT SHOW", "Choose which gameplay effects you want to see.")
	var hype_panel = settings_page(tabs, "Hype", "PEAK ENERGY", "Bonus scoring and song-synced celebrations.")
	var accessibility = settings_page(tabs, "Accessibility", "COMFORT FIRST", "Keep the interface comfortable for you.")
	label_into(display, "Window mode", 18)
	var mode = OptionButton.new()
	mode.name = "WindowMode"
	mode.add_item("Windowed")
	mode.add_item("Fullscreen")
	mode.select(1 if fullscreen else 0)
	mode.item_selected.connect(func(index): set_fullscreen(index == 1))
	display.add_child(mode)
	label_into(display, "F11 toggles fullscreen at any time. Your choice is saved.", 16, MUTED)
	tabs.current_tab = settings_tab
	tabs.tab_changed.connect(func(index):
		settings_tab = index
		var page = tabs.get_tab_control(index)
		if page.has_meta("tab_tween"):
			var old = page.get_meta("tab_tween") as Tween
			if old != null and old.is_valid(): old.kill()
		page.modulate.a = 1.0 if reduced_motion else 0.25
		var tween = create_tween()
		page.set_meta("tab_tween", tween)
		tween.tween_property(page, "modulate:a", 1.0, 0.22))
	var motion_toggle = CheckButton.new()
	motion_toggle.name = "ReducedMotion"
	motion_toggle.text = "Reduced motion — stop hover scaling, disc spin and moving backgrounds"
	motion_toggle.button_pressed = reduced_motion
	motion_toggle.toggled.connect(func(value):
		reduced_motion = value
		ui_motion.reduced = value
		save_settings())
	accessibility.add_child(motion_toggle)
	add_calibration_panel(settings)
	label_into(settings, "TIMING AND AUDIO", 16, COLORS[2])
	label_into(settings, "Offset (ms)", 14)
	var offset = SpinBox.new()
	offset.min_value = -300
	offset.max_value = 300
	offset.step = 5
	offset.value = offset_ms
	offset.value_changed.connect(func(v):
		offset_ms = v
		save_settings())
	settings.add_child(offset)
	label_into(settings, "Speed (px/s)", 14)
	var speed = LineEdit.new()
	speed.name = "NoteSpeed"
	speed.custom_minimum_size.x = 125
	speed.text = str(scroll_speed)
	speed.tooltip_text = "Any positive speed; no upper limit. Higher = faster. Press Enter to apply."
	speed.text_submitted.connect(func(_text): apply_note_speed(speed))
	speed.focus_exited.connect(func(): apply_note_speed(speed))
	settings.add_child(speed)
	label_into(audio_settings, "AUDIO MIX", 16, COLORS[0])
	for item in [["Master volume", "volume"], ["Song volume", "music_volume"], ["Preview volume", "preview_volume"], ["Hit sounds", "hit_volume"], ["Miss sounds", "miss_volume"]]:
		add_audio_slider(audio_settings, str(item[0]), str(item[1]))
	var test_sounds = box_into(audio_settings, true)
	button_into(test_sounds, "Test hit", func(): play_feedback(false))
	button_into(test_sounds, "Test miss", func(): play_feedback(true))
	label_into(audio_settings, "Set hit or miss volume to 0% to mute that sound.", 14, MUTED)
	label_into(hype_panel, "HYPE MOMENTS", 20, COLORS[0])
	var hype_toggle = CheckButton.new()
	hype_toggle.text = "Enable hype scoring bonus"
	hype_toggle.button_pressed = bool(hype_settings.enabled)
	hype_toggle.toggled.connect(func(value):
		hype_settings.enabled = value
		save_settings())
	hype_panel.add_child(hype_toggle)
	for item in [["Bonus multiplier", "bonus"], ["Detection sensitivity", "sensitivity"], ["Beat glow intensity", "glow"], ["Beat ring intensity", "rings"], ["Screen shake intensity", "shake"]]:
		add_hype_slider(hype_panel, str(item[0]), str(item[1]))
	label_into(hype_panel, "Effect sliders at 0 turn that effect off. A miss removes the bonus until the next hype section.", 14, MUTED)
	label_into(hype_panel, "Online scoring uses standard 2× hype and 50% sensitivity. Personal bests separate scoring settings.", 14, MUTED)
	if not selected.is_empty() and not str(selected.get("folder", "")).begins_with("res://") and not online.connected():
		button_into(hype_panel, "Analyze hype for selected song", func(): start_import("hype", str(selected.folder)))
	label_into(hype_panel, "Analyze older imports here; charts stay unchanged. New imports include hype automatically.", 14, MUTED)
	label_into(effects, "EFFECTS", 16, COLORS[1])
	var effects_grid = GridContainer.new()
	effects_grid.columns = 2
	effects.add_child(effects_grid)
	for item in [["Lane flashes", "lane_flashes"], ["Hit rings", "hit_rings"], ["Hit sparks", "hit_sparks"], ["Combo glow and celebrations", "combo_glow"], ["Judgement popups", "judgements"], ["Note trails", "note_trails"], ["Miss border flash", "miss_flash"], ["Hold shimmer", "hold_shimmer"], ["Song spectrum visualizers", "audio_visualizer"], ["Bass-reactive edge glow", "bass_glow"]]:
		add_effect_toggle(effects_grid, str(item[0]), str(item[1]))
	label_into(visuals, "Notes", 14)
	var styles = OptionButton.new()
	styles.name = "NoteStyle"
	for style in NOTE_STYLES:
		styles.add_item(style)
	styles.select(NOTE_STYLES.find(note_style))
	styles.item_selected.connect(func(i):
		note_style = NOTE_STYLES[i]
		save_settings()
		queue_redraw())
	visuals.add_child(styles)
	label_into(visuals, "Background video dimming", 14)
	var opacity = HSlider.new()
	opacity.custom_minimum_size.x = 360
	opacity.min_value = 0
	opacity.max_value = 1.0
	opacity.step = 0.01
	opacity.name = "VideoDimming"
	opacity.value = 1.0 - video_opacity
	visuals.add_child(opacity)
	var percentage = label_into(visuals, "%d%%" % int((1.0 - video_opacity) * 100), 14, MUTED)
	opacity.value_changed.connect(func(v):
		video_opacity = 1.0 - v
		percentage.text = "%d%%" % int(v * 100)
		save_settings())
	label_into(visuals, "0% = full brightness · 100% = video off", 14, MUTED)
	label_into(visuals, "Highway transparency", 16, COLORS[2])
	var road_alpha = HSlider.new()
	road_alpha.name = "HighwayTransparency"
	road_alpha.custom_minimum_size.x = 360
	road_alpha.max_value = 1.0
	road_alpha.step = 0.01
	road_alpha.value = 1.0 - highway_opacity
	visuals.add_child(road_alpha)
	var road_label = label_into(visuals, "%d%% transparent" % int(road_alpha.value * 100), 14, MUTED)
	road_alpha.value_changed.connect(func(value):
		highway_opacity = 1.0 - value
		road_label.text = "%d%% transparent" % int(value * 100)
		save_settings()
		queue_redraw())
	label_into(visuals, "Notes and hit effects stay bright at every transparency level.", 14, MUTED)
	label_into(visuals, "20 streak = 2×   ·   50 = 3×   ·   100 = 4×   ·   Miss resets", 14, COLORS[2])
	status_label = label_into(root, last_message, 15, COLORS[0])
	queue_redraw()

func commit_preferences() -> bool:
	var field = ui.find_child("NoteSpeed", true, false) as LineEdit
	if field != null and not apply_note_speed(field):
		return false
	for p in range(4):
		var profile = ui.find_child("ProfileName%d" % p, true, false) as LineEdit
		if profile != null:
			profile_names[p] = clean_profile(profile.text, p)
	save_settings()
	return true

func apply_note_speed(field: LineEdit) -> bool:
	var raw: String = field.text.strip_edges()
	var value: float = raw.to_float()
	if not raw.is_valid_float() or not is_finite(value) or value <= 0:
		field.text = str(scroll_speed)
		last_message = "Enter a positive note speed. There is no upper limit."
		if is_instance_valid(status_label):
			status_label.text = last_message
		return false
	scroll_speed = value
	save_settings()
	return true

func commit_player_names() -> void:
	if not is_instance_valid(ui):
		return
	for p in range(4):
		var field = ui.find_child("ProfileName%d" % p, true, false) as LineEdit
		if field != null:
			profile_names[p] = clean_profile(field.text, p)
	save_settings()

func player_setup(parent: Node, p: int) -> void:
	var compact: bool = screen == "menu"
	var profile_box = box_into(parent) if compact else parent
	var row = box_into(profile_box, true)
	label_into(row, "P" + str(p + 1), 18, COLORS[p])
	for lane in range(4):
		var key = button_into(row, OS.get_keycode_string(int(bindings[p][lane])), func():
			pending_key = Vector2i(p, lane)
			last_message = "Press a new key for P%d lane %d. Esc cancels." % [p + 1, lane + 1]
			status_label.text = last_message)
		key.custom_minimum_size.x = 44
		if compact: key.clip_text = true
	if compact:
		row = box_into(profile_box)
	if not selected.is_empty():
		var instruments: Array = selected.charts.keys()
		if not choices[p].get("instrument", "") in instruments:
			choices[p]["instrument"] = instruments[mini(p, instruments.size() - 1)]
		var instrument = OptionButton.new()
		instrument.name = "Instrument%d" % p
		if compact: instrument.fit_to_longest_item = false
		for item in instruments:
			instrument.add_item(str(item))
		instrument.select(instruments.find(choices[p].instrument))
		instrument.item_selected.connect(func(i):
			choices[p]["instrument"] = instruments[i]
			preferred_choices[p]["instrument"] = instruments[i]
			save_settings()
			show_menu())
		row.add_child(instrument)
		var diffs: Array = selected.charts[choices[p].instrument].keys()
		if not choices[p].get("difficulty", "") in diffs:
			choices[p]["difficulty"] = diffs[0]
		var difficulty = OptionButton.new()
		difficulty.name = "Difficulty%d" % p
		if compact: difficulty.fit_to_longest_item = false
		for item in diffs:
			difficulty.add_item(str(item))
		difficulty.select(diffs.find(choices[p].difficulty))
		difficulty.item_selected.connect(func(i):
			choices[p]["difficulty"] = diffs[i]
			preferred_choices[p]["difficulty"] = diffs[i]
			save_settings()
			refresh_menu_leaderboard())
		row.add_child(difficulty)
	var profile = LineEdit.new()
	profile.name = "ProfileName%d" % p
	profile.text = profile_names[p]
	profile.max_length = 16
	profile.custom_minimum_size.x = 95
	profile.tooltip_text = "Player name used for personal bests"
	profile.text_changed.connect(func(value):
		profile_names[p] = clean_profile(value, p)
		save_settings())
	profile.focus_exited.connect(func(): profile.text = profile_names[p])
	row.add_child(profile)
	if compact:
		profile_box.add_child(HSeparator.new())

func choose_song_card() -> void:
	var picker = FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	picker.filters = PackedStringArray(["*.png ; Pulse Four data cards"])
	picker.file_selected.connect(func(path):
		start_import("card_import", path)
		picker.queue_free())
	picker.canceled.connect(picker.queue_free)
	add_child(picker)
	picker.popup_centered_ratio(0.75)

func export_song_card() -> void:
	if selected.get("category", "") != "YouTube" or worker_pid > 0: return
	var texture = covers.texture_for(selected)
	if texture == null:
		last_message = "The YouTube thumbnail is not ready. Wait for it to load, then export again."
		show_menu()
		return
	var snapshot: Dictionary = selected.duplicate(true)
	snapshot.erase("folder")
	var thumbnail: Image = texture.get_image()
	var picker = FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	picker.filters = PackedStringArray(["*.png ; Pulse Four data card"])
	if not last_card_export_dir.is_empty() and DirAccess.dir_exists_absolute(last_card_export_dir):
		picker.current_dir = last_card_export_dir
	var filename = str(selected.title).validate_filename().strip_edges()
	while filename.ends_with("."):
		filename = filename.trim_suffix(".")
	if filename.is_empty(): filename = "Song"
	picker.current_file = filename + ".png"
	picker.file_selected.connect(func(path):
		var folder = ProjectSettings.globalize_path("user://jobs")
		DirAccess.make_dir_recursive_absolute(folder)
		var image_path = folder.path_join("card-thumbnail-%d.png" % Time.get_ticks_msec())
		if thumbnail.save_png(image_path) != OK:
			last_message = "Could not prepare the thumbnail."
			show_menu()
		else:
			start_import("card_export", str(snapshot.source), {"destination": path, "thumbnail": image_path, "song": snapshot})
		picker.queue_free())
	picker.canceled.connect(picker.queue_free)
	add_child(picker)
	picker.popup_centered_ratio(0.75)

func choose_osu() -> void:
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray(["*.osu,*.osz ; osu!mania beatmaps"])
	file_dialog.file_selected.connect(func(path):
		start_import("osu", path)
		file_dialog.queue_free())
	file_dialog.canceled.connect(func(): file_dialog.queue_free())
	add_child(file_dialog)
	file_dialog.popup_centered_ratio(0.75)

func start_import(kind: String, source: String, extra: Dictionary = {}) -> void:
	if worker_pid > 0:
		return
	if source.is_empty():
		last_message = "Enter a YouTube video link first."
		show_menu()
		return
	var base: String = OS.get_executable_path().get_base_dir()
	var executable: String = base.path_join("importer/PulseImporter.exe")
	var args: PackedStringArray = []
	if OS.has_feature("editor"):
		executable = OS.get_environment("PULSE_PYTHON")
		if executable.is_empty():
			executable = "python" if OS.get_name() == "Windows" else "python3"
		args.append(ProjectSettings.globalize_path("res://importer/worker.py"))
	elif not FileAccess.file_exists(executable):
		last_message = "Importer missing. Use a full release build; see BUILD-WINDOWS.md."
		show_menu()
		return
	var job_dir: String = ProjectSettings.globalize_path("user://jobs")
	DirAccess.make_dir_recursive_absolute(job_dir)
	var name: String = str(Time.get_ticks_msec())
	job_result = job_dir.path_join(name + ".result.json")
	var request: String = job_dir.path_join(name + ".request.json")
	var f = FileAccess.open(request, FileAccess.WRITE)
	if not f:
		last_message = "Could not write import request. Check free disk space."
		show_menu()
		return
	var request_data = {"kind": kind, "source": source, "library": song_root, "result": job_result}
	request_data.merge(extra, true)
	f.store_string(JSON.stringify(request_data))
	f.close()
	args.append_array(["--request", request])
	worker_pid = OS.create_process(executable, args)
	last_message = "Starting importer…" if worker_pid > 0 else "Could not launch importer. See BUILD-WINDOWS.md."
	show_menu()

func cancel_import() -> void:
	if worker_pid > 0:
		var f = FileAccess.open(job_result.get_basename() + ".cancel", FileAccess.WRITE)
		if f:
			f.store_string("cancel")
		last_message = "Cancelling import…"
		if is_instance_valid(status_label):
			status_label.text = last_message

func poll_import() -> void:
	var data = null
	if FileAccess.file_exists(job_result):
		data = JSON.parse_string(FileAccess.get_file_as_string(job_result))
	if data is Dictionary:
		last_message = str(data.get("message", "Working…"))
		if screen == "menu" and is_instance_valid(status_label):
			status_label.text = last_message
			import_progress.value = float(data.get("progress", 0))
		if data.get("state") in ["done", "error"]:
			worker_pid = -1
			if data.state == "done":
				var exported_path: String = str(data.get("exported_path", ""))
				if not exported_path.is_empty():
					last_card_export_dir = exported_path.get_base_dir()
					save_settings()
					DirAccess.remove_absolute(job_result)
				if not data.get("warnings", []).is_empty():
					last_message += " · Skipped: " + "; ".join(data.warnings)
				scan_songs()
			if screen == "menu":
				show_menu()
			return
	if not OS.is_process_running(worker_pid):
		worker_pid = -1
		last_message = "Importer stopped unexpectedly. Check Python/dependencies or use a full release build."
		if screen == "menu":
			show_menu()

func load_song_audio() -> AudioStream:
	var path: String = str(selected.folder).path_join(str(selected.audio))
	if path.begins_with("res://"):
		return load(path) as AudioStream
	return AudioStreamWAV.load_from_file(path)

func start_game() -> void:
	stop_preview()
	if online.connected() and not online_launch:
		show_online_menu()
		return
	if screen == "menu" and is_instance_valid(ui):
		var speed_field = ui.find_child("NoteSpeed", true, false) as LineEdit
		if speed_field != null and not apply_note_speed(speed_field):
			return
	if selected.is_empty():
		return
	if screen == "menu":
		for p in range(players_count):
			var field = ui.find_child("ProfileName%d" % p, true, false) as LineEdit
			if field != null:
				profile_names[p] = clean_profile(field.text, p)
		save_settings()
	for p in range(players_count):
		if choices[p].is_empty() or selected.charts[choices[p].instrument][choices[p].difficulty].is_empty():
			last_message = "P%d has an empty chart. Choose another instrument or difficulty." % (p + 1)
			show_menu()
			return
	audio.stop()
	audio.stream = load_song_audio()
	if audio.stream == null:
		last_message = "Could not load this song's audio. Reimport the beatmap."
		show_menu()
		return
	runs.clear()
	results_recorded = false
	run_length = audio.stream.get_length()
	for p in range(players_count):
		var notes: Array = selected.charts[choices[p].instrument][choices[p].difficulty].duplicate(true)
		for n in notes:
			n["state"] = 0
			n["points"] = 0
			n["hold_ticks"] = 0
		run_length = maxf(run_length, float(notes[-1].end) + offset_ms / 1000.0)
		runs.append({"timing_samples": [], "start_offset": offset_ms, "hype_sections": Hype.sections(selected, str(choices[p].instrument), hype_sensitivity()), "hype_index": -1, "hype_broken": false, "notes": notes, "timing": timing_for(str(choices[p].instrument), str(choices[p].difficulty)), "chart_key": chart_key_for(str(choices[p].instrument), str(choices[p].difficulty)), "profile": profile_names[p], "raw_score": 0, "multiplier": 1, "combo_pulse": 0.0, "milestone": "", "new_best": false, "save_error": "", "cursor": 0, "score": 0, "combo": 0, "best": 0, "judged": 0,
			"perfect": 0, "great": 0, "good": 0, "miss": 0, "flash": 0.0, "message": "READY", "held": [false, false, false, false], "lane_flash": [0.0, 0.0, 0.0, 0.0], "effects": []})
	time_s = online.server_time() - online_start_at if online_game else -2.0
	playing = false
	paused = false
	prepare_background_video()
	screen = "game"
	clear_ui()
	queue_redraw()

func chart_time() -> float:
	var current: float = time_s
	if screen == "game" and playing and not paused and audio.playing:
		current = maxf(current, audio.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency())
	return current - offset_ms / 1000.0

func emit_hit_effect(p: int, lane: int, points: int) -> void:
	var r: Dictionary = runs[p]
	r.lane_flash[lane] = 0.28
	r.effects.append({"lane": lane, "age": 0.0, "points": points, "power": int(r.multiplier)})
	if r.effects.size() > 32:
		r.effects.pop_front()

func timing_for(instrument: String, difficulty: String) -> Array:
	var source = selected.get("timing", [])
	if source is Dictionary:
		source = source.get(instrument, {}).get(difficulty, [])
	var result: Array = []
	if source is Array:
		for point in source:
			if not point is Dictionary:
				continue
			var at: float = float(point.get("t", 0))
			var beat: float = float(point.get("beat_length", 0))
			var meter: int = int(point.get("meter", 4))
			if is_finite(at) and is_finite(beat) and beat > 0 and meter >= 1 and meter <= 32:
				result.append({"t": at, "beat_length": beat, "meter": meter})
	result.sort_custom(func(a, b): return float(a.t) < float(b.t))
	if result.is_empty():
		result.append({"t": 0.0, "beat_length": 0.5, "meter": 4})
	return result

func bars_between(start: float, finish: float, timing: Array) -> float:
	if finish <= start:
		return 0.0
	var bar_seconds: float = 2.0
	if not timing.is_empty():
		bar_seconds = float(timing[0].beat_length) * int(timing[0].meter)
	var cursor: float = start
	var bars: float = 0.0
	for point in timing:
		var at: float = float(point.t)
		if at <= start:
			bar_seconds = float(point.beat_length) * int(point.meter)
		elif at < finish:
			bars += (at - cursor) / bar_seconds
			cursor = at
			bar_seconds = float(point.beat_length) * int(point.meter)
		else:
			break
	return bars + (finish - cursor) / bar_seconds

func award_hold_bars(p: int, n: Dictionary, now: float) -> void:
	if int(n.state) != 1:
		return
	var r: Dictionary = runs[p]
	var elapsed: float = bars_between(float(n.t), minf(now, float(n.end)), r.get("timing", []))
	var earned: int = maxi(0, int(floor(elapsed + 0.000001)))
	var previous: int = int(n.get("hold_ticks", 0))
	if earned > previous:
		n["hold_ticks"] = earned
		Hype.refresh(r, chart_time())
		var awarded: int = int(round((earned - previous) * 300 * int(r.multiplier) * hype_multiplier(r)))
		r.score += awarded
		r.message = "HOLD  +%d" % awarded
		r.flash = 0.4
		emit_hit_effect(p, int(n.lane), 300)

func finish_hold(p: int, n: Dictionary, now: float) -> void:
	if int(n.state) != 1:
		return
	var complete: bool = now >= float(n.end) - 0.080
	award_hold_bars(p, n, float(n.end) if complete else now)
	n.state = 2
	var r: Dictionary = runs[p]
	if complete:
		r.message = "HOLD COMPLETE"
		emit_hit_effect(p, int(n.lane), 300)
	else:
		# Releasing preserves the streak. The original tail becomes a required
		# tap, which can later break the streak if missed. Never duplicate it.
		var tail: Dictionary = {"t": float(n.end), "end": float(n.end), "lane": int(n.lane), "state": 0, "points": 0, "recovery": true}
		r.notes.append(tail)
		r.notes.sort_custom(func(a, b): return float(a.t) < float(b.t) if float(a.t) != float(b.t) else int(a.lane) < int(b.lane))
		r.message = "RELEASED  /  HIT TAIL"
	r.flash = 0.5

func judge(p: int, n: Dictionary, points: int) -> void:
	# Resolved notes cannot be judged twice.
	if int(n.state) >= 2:
		return
	var r: Dictionary = runs[p]
	n.state = 2 if points > 0 else 3
	r.judged += 1
	play_feedback(points == 0)
	r.raw_score += points
	Hype.refresh(r, chart_time())
	var recovery: bool = bool(n.get("recovery", false))
	if points == 0:
		r.combo = 0
		if int(r.get("hype_index", -1)) >= 0:
			r["hype_broken"] = true
	elif not recovery:
		r.combo += 1
	r.multiplier = multiplier_for(int(r.combo))
	# A recovery tail preserves the streak but cannot farm extra score/combo.
	if not recovery:
		r.score += int(round(points * int(r.multiplier) * hype_multiplier(r)))
	r.best = maxi(r.best, r.combo)
	if points == 0:
		r.combo_pulse = 0.0
		r.milestone = ""
	elif not recovery and (r.combo in [20, 50, 100] or (r.combo > 100 and int(r.combo) % 50 == 0)):
		r.combo_pulse = 1.2
		r.milestone = "%d STREAK  /  %d×" % [r.combo, r.multiplier]
	var judgement: String = "perfect" if points == 300 else "great" if points == 200 else "good" if points > 0 else "miss"
	r[judgement] += 1
	r.message = judgement.to_upper()
	r.flash = 0.6
	if points > 0:
		emit_hit_effect(p, int(n.lane), points)

func key_hit(p: int, lane: int, pressed: bool) -> void:
	var r: Dictionary = runs[p]
	r.held[lane] = pressed
	var now: float = chart_time()
	if not pressed:
		for i in range(r.cursor, r.notes.size()):
			var n: Dictionary = r.notes[i]
			if float(n.t) > now + WINDOW:
				break
			if n.lane == lane and n.state == 1:
				finish_hold(p, n, now)
				return
		return
	for i in range(r.cursor, r.notes.size()):
		var n: Dictionary = r.notes[i]
		if float(n.t) > now + WINDOW:
			break
		if n.lane != lane or n.state != 0 or absf(float(n.t) - now) > WINDOW:
			continue
		if not bool(n.get("recovery", false)):
			r.timing_samples.append((now - float(n.t)) * 1000.0)
		var error: float = absf(float(n.t) - now)
		var points: int = 300 if error <= 0.045 else 200 if error <= 0.090 else 100
		if float(n.end) > float(n.t):
			judge(p, n, points)
			n.state = 1
			n.points = points
			n["hold_ticks"] = 0
			r.message = "HOLD"
			r.flash = 0.4
		else:
			judge(p, n, points)
		return

func toggle_pause() -> void:
	if online_game:
		return
	paused = not paused
	audio.stream_paused = paused
	background_video.paused = paused
	clear_ui()
	if paused:
		var shade = ColorRect.new()
		shade.color = Color(0.02, 0.03, 0.07, 0.88)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ui.add_child(shade)
		var center = CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ui.add_child(center)
		var panel = box_into(center)
		label_into(panel, "TAKE A BREATH", 36, COLORS[0])
		label_into(panel, "Keep any active hold keys pressed when resuming.", 16)
		button_into(panel, "Resume  /  Esc", toggle_pause)
		button_into(panel, "Restart  /  F5", start_game)
		button_into(panel, "Song library", show_menu)
	else:
		for p in range(players_count):
			for lane in range(4):
				runs[p].held[lane] = Input.is_physical_key_pressed(int(bindings[p][lane]))
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F11 and pending_key.x < 0:
		set_fullscreen(not fullscreen)
		get_viewport().set_input_as_handled()
		return
	if ui_motion.launching:
		return
	if not event is InputEventKey or event.echo:
		return
	var key: int = event.physical_keycode
	if pending_key.x >= 0 and event.pressed:
		if key == KEY_ESCAPE:
			pending_key = Vector2i(-1, -1)
			last_message = "Rebind cancelled."
		elif key in [KEY_F5, KEY_F11, 0]:
			last_message = "That key is reserved. Choose another key."
		else:
			var used: bool = false
			for p in range(4):
				for lane in range(4):
					if Vector2i(p, lane) != pending_key and int(bindings[p][lane]) == key:
						used = true
			if used:
				last_message = "Key already assigned. Choose an unused key (or Esc to cancel)."
			else:
				bindings[pending_key.x][pending_key.y] = key
				pending_key = Vector2i(-1, -1)
				last_message = "Key saved."
				save_settings()
		get_viewport().set_input_as_handled()
		show_menu()
		return
	if screen == "settings" and key == KEY_ESCAPE and event.pressed:
		show_menu()
		get_viewport().set_input_as_handled()
		return
	if screen != "game":
		return
	if key == KEY_ESCAPE and event.pressed:
		if online_game:
			online.leave()
			abort_online("Left online round.")
		else:
			toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if key == KEY_F5 and event.pressed:
		if not online_game:
			start_game()
		get_viewport().set_input_as_handled()
		return
	if paused:
		return
	for p in range(players_count):
		for lane in range(4):
			if int(bindings[p][lane]) == key:
				key_hit(p, lane, event.pressed)
				get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not reduced_motion:
		ui_clock += delta
	if screen != "game":
		ui_redraw_time += delta
		if ui_redraw_time >= 1.0 / 30.0:
			ui_redraw_time = 0.0
			queue_redraw()
	music_visualizer.sample(delta, screen == "game" and playing and not paused and (visual_effects.audio_visualizer or visual_effects.bass_glow or float(hype_settings.glow) > 0))
	if not ui_motion.launching:
		process_preview(delta)
	if online_game and not runs.is_empty() and screen in ["game", "results"]:
		var local_run: Dictionary = runs[0]
		online.report = {"score": local_run.score, "combo": local_run.combo, "accuracy": 100.0 * float(local_run.raw_score) / maxf(300, float(local_run.judged) * 300), "finished": screen == "results"}
	if worker_pid > 0:
		job_timer += delta
		if job_timer > 0.4:
			job_timer = 0
			poll_import()
	if screen != "game" or paused:
		return
	if not playing:
		time_s = online.server_time() - online_start_at if online_game else time_s + delta
		if time_s >= 0:
			audio.play(maxf(0.0, time_s) if online_game else 0.0)
			if background_video.stream != null and video_opacity > 0:
				background_video.visible = true
				background_video.play()
			playing = true
			if not online_game:
				time_s = 0
	elif audio.playing:
		var audio_time: float = audio.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
		time_s = maxf(time_s, audio_time)
	else:
		time_s += delta
	var now: float = chart_time()
	for p in range(players_count):
		var r: Dictionary = runs[p]
		Hype.refresh(r, now)
		r.flash = maxf(0, r.flash - delta)
		r.combo_pulse = maxf(0, r.combo_pulse - delta)
		for lane in range(4):
			r.lane_flash[lane] = maxf(0, r.lane_flash[lane] - delta)
		for effect_index in range(r.effects.size() - 1, -1, -1):
			r.effects[effect_index].age += delta
			if r.effects[effect_index].age >= 0.45:
				r.effects.remove_at(effect_index)
		for i in range(r.cursor, r.notes.size()):
			var n: Dictionary = r.notes[i]
			if float(n.t) > now + WINDOW:
				break
			if n.state == 0 and now - float(n.t) > WINDOW:
				judge(p, n, 0)
			elif n.state == 1:
				if not r.held[int(n.lane)] or now >= float(n.end):
					finish_hold(p, n, now)
				else:
					award_hold_bars(p, n, now)
		while r.cursor < r.notes.size() and r.notes[r.cursor].state >= 2:
			r.cursor += 1
	if time_s > run_length + 1.2:
		show_results()
	queue_redraw()

func format_time(seconds: float) -> String:
	return "%d:%02d" % [int(maxf(0, seconds)) / 60, int(maxf(0, seconds)) % 60]

func text_at(pos: Vector2, text: String, px: int = 20, color: Color = WHITE, width: float = -1) -> void:
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, width, px, color)

func layout_background_video() -> void:
	if not is_instance_valid(background_video):
		return
	var display_size: Vector2 = Vector2(size.x, size.x * 9.0 / 16.0)
	if display_size.y > size.y:
		display_size = Vector2(size.y * 16.0 / 9.0, size.y)
	background_image.size = size
	background_video.size = display_size
	background_video.position = (size - display_size) / 2

func stop_background_video() -> void:
	background_image.visible = false
	background_image.texture = null
	background_video.stop()
	background_video.visible = false
	background_video.paused = false

func prepare_background_video() -> void:
	stop_background_video()
	background_video.stream = null
	background_video.modulate = Color(1, 1, 1, video_opacity)
	if video_opacity > 0 and selected.get("background_image", "") == "background.png":
		var image_path: String = str(selected.folder).path_join("background.png")
		if FileAccess.file_exists(image_path):
			var still = Image.load_from_file(image_path)
			if still != null:
				background_image.texture = ImageTexture.create_from_image(still)
				background_image.modulate = Color(1, 1, 1, video_opacity)
				background_image.visible = true
				layout_background_video()
		return
	if video_opacity <= 0 or selected.get("video", "") != "background.ogv":
		return
	var path: String = str(selected.folder).path_join("background.ogv")
	if not FileAccess.file_exists(path):
		return
	var stream = VideoStreamTheora.new()
	stream.file = path
	background_video.stream = stream
	layout_background_video()

func clean_profile(value: String, p: int) -> String:
	var cleaned: String = value.strip_edges().substr(0, 16)
	return "Player %d" % (p + 1) if cleaned.is_empty() else cleaned

func multiplier_for(streak: int) -> int:
	if streak >= 100:
		return 4
	if streak >= 50:
		return 3
	if streak >= 20:
		return 2
	return 1

func cap_generated_holds(song: Dictionary) -> void:
	if song.get("category", "") != "YouTube":
		return
	for part in song.charts:
		for difficulty in song.charts[part]:
			var active: Array = []
			for note in song.charts[part][difficulty]:
				for i in range(active.size() - 1, -1, -1):
					if float(active[i]) <= float(note.t):
						active.remove_at(i)
				if float(note.end) <= float(note.t):
					continue
				if active.size() >= 2:
					note.end = note.t
				else:
					active.append(note.end)

func chart_key_for(instrument: String, difficulty: String) -> String:
	var note_hash: String = JSON.stringify(selected.charts[instrument][difficulty]).sha256_text()
	var base: Array = ["bar-bonus-recovery-v3", selected.id, instrument, difficulty, note_hash, timing_for(instrument, difficulty)]
	var hype_ranges: Array = Hype.sections(selected, instrument, hype_sensitivity())
	if hype_enabled() and not hype_ranges.is_empty():
		base.append(["hype-v1", hype_bonus(), hype_ranges])
	return JSON.stringify(base).sha256_text()

func record_completed_runs() -> void:
	if results_recorded:
		return
	results_recorded = true
	for p in range(runs.size()):
		var r: Dictionary = runs[p]
		if r.notes.is_empty() or int(r.judged) != r.notes.size() or r.notes.any(func(note): return int(note.state) < 2):
			continue
		var accuracy: float = 100.0 * float(r.raw_score) / (300.0 * r.notes.size())
		var entry: Dictionary = {"name": r.profile, "score": r.score, "accuracy": accuracy, "grade": ScoreStore.grade(accuracy), "combo": r.best, "date": Time.get_datetime_string_from_system()}
		var meta: Dictionary = {"song_id": selected.id, "title": selected.title, "instrument": choices[p].instrument, "difficulty": choices[p].difficulty}
		var result: Dictionary = score_store.submit(str(r.chart_key), meta, entry)
		r.new_best = result.improved
		r.save_error = result.error

func draw_note_sprite(center: Vector2, width: float, tint: Color) -> void:
	var body_width: float = width * 0.8
	var height: float = body_width * 0.38
	draw_rect(Rect2(center - Vector2(body_width * 0.53, height * 0.6), Vector2(body_width * 1.06, height * 1.2)), Color(tint, tint.a * 0.12))
	if note_style == "Bar":
		var origin: Vector2 = center - Vector2(body_width, height) / 2
		draw_rect(Rect2(origin + Vector2(0, 3), Vector2(body_width, height)), Color("0a1011"))
		for band in range(4):
			var shades: Array = [1.0, 0.78, 0.42, 0.66]
			draw_rect(Rect2(origin + Vector2(0, height * band / 4), Vector2(body_width, height / 4 + 1)), Color(tint * float(shades[band]), tint.a))
		draw_line(origin, origin + Vector2(body_width, 0), Color(WHITE, tint.a * 0.8), 2)
		draw_rect(Rect2(origin + Vector2(3, 3), Vector2(maxf(1, body_width - 6), maxf(1, height - 6))), Color("303938"), false, 1.5)
		draw_rect(Rect2(center - Vector2(body_width * 0.09, height * 0.2), Vector2(body_width * 0.18, height * 0.4)), Color(WHITE, tint.a))
	else:
		var ink_width: float = 52.0 if note_style == "Square" else 54.0
		var side: float = body_width * 64.0 / ink_width
		draw_texture_rect(NOTE_TEXTURES[note_style], Rect2(center - Vector2(side, side * 0.55) / 2, Vector2(side, side * 0.55)), false, tint)

# Project the highway into depth. Judgements remain tied to audio time.
func road_point(x: float, width: float, top: float, hit: float, lane: float, y: float) -> Vector2:
	var depth: float = clampf((y - top) / maxf(1, hit - top), 0, 1.08)
	var projected: float = depth / (2.3 - 1.3 * depth)
	var scale: float = lerpf(0.38, 1.0, projected)
	return Vector2(x + width / 2 + (lane / 4 - 0.5) * width * scale, top + projected * (hit - top))

func road_quad(x: float, width: float, top: float, hit: float, lane_a: float, lane_b: float, y_a: float, y_b: float, tint: Color) -> void:
	draw_colored_polygon(PackedVector2Array([road_point(x, width, top, hit, lane_a, y_a), road_point(x, width, top, hit, lane_b, y_a), road_point(x, width, top, hit, lane_b, y_b), road_point(x, width, top, hit, lane_a, y_b)]), tint)

func show_leaderboard() -> void:
	if selected.is_empty():
		return
	screen = "leaderboard"
	audio.stop()
	stop_background_video()
	clear_ui()
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	ui.add_child(margin)
	var scroll = ScrollContainer.new()
	margin.add_child(scroll)
	var root = box_into(scroll)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_into(root, "PERSONAL BESTS", 34, COLORS[0])
	label_into(root, str(selected.title), 24)
	label_into(root, "One best per player name. Scores compare the same part, difficulty and chart layout.", 16, MUTED)
	var parts: Array = selected.charts.keys()
	if not board_instrument in parts:
		board_instrument = str(parts[0])
	var diffs: Array = selected.charts[board_instrument].keys()
	if not board_difficulty in diffs:
		board_difficulty = str(diffs[0])
	var filters = box_into(root, true)
	var part = OptionButton.new()
	for item in parts:
		part.add_item(str(item))
	part.select(parts.find(board_instrument))
	part.item_selected.connect(func(i):
		board_instrument = str(parts[i])
		board_difficulty = ""
		show_leaderboard())
	filters.add_child(part)
	var difficulty = OptionButton.new()
	for item in diffs:
		difficulty.add_item(str(item))
	difficulty.select(diffs.find(board_difficulty))
	difficulty.item_selected.connect(func(i):
		board_difficulty = str(diffs[i])
		show_leaderboard())
	filters.add_child(difficulty)
	var rows: Array = score_store.entries(chart_key_for(board_instrument, board_difficulty))
	var grid = GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 14)
	root.add_child(grid)
	for heading in ["Rank", "Player", "Grade", "Points", "Accuracy", "Best streak"]:
		label_into(grid, heading, 17, COLORS[1])
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		for cell in [str(i + 1), str(row.name), ScoreStore.grade(float(row.accuracy)), str(int(row.score)), "%.2f%%" % float(row.accuracy), str(int(row.get("combo", 0)))]:
			label_into(grid, cell, 20)
	if rows.is_empty():
		label_into(root, "No scores yet. Finish this chart to set your first personal best.", 18, MUTED)
	if not score_store.warning.is_empty():
		label_into(root, score_store.warning, 16, Color("fa7f96"))
	button_into(root, "Song library", show_menu)
	queue_redraw()

func _draw() -> void:
	draw_set_transform(hype_shake())
	draw_arcade_backdrop()
	if screen != "game":
		return
	var w: float = size.x
	var h: float = size.y
	text_at(Vector2(28, 40), "PULSE / FOUR", 24, COLORS[0])
	text_at(Vector2(245, 40), str(selected.title), 20, WHITE, w - 500)
	text_at(Vector2(w - 235, 40), format_time(time_s) + " / " + format_time(run_length), 18, MUTED)
	draw_rect(Rect2(28, 60, w - 56, 3), Color("23304a"))
	draw_rect(Rect2(28, 60, (w - 56) * clampf(time_s / maxf(1, run_length), 0, 1), 3), COLORS[0])
	var track_w: float = minf(460, (w - 48 - (players_count - 1) * 18) / players_count)
	var start_x: float = (w - (track_w * players_count + 18 * (players_count - 1))) / 2
	draw_song_visualizer(start_x)
	var top: float = 170
	var hit: float = h - 115
	var pixels: float = scroll_speed
	var visible_seconds: float = (hit - top) / scroll_speed
	for p in range(players_count):
		var x: float = start_x + p * (track_w + 18)
		var lane_w: float = track_w / 4
		var r: Dictionary = runs[p]
		text_at(Vector2(x, 101), "%s  /  %s" % [r.profile, choices[p].instrument], 19, COLORS[p], track_w)
		var acc: float = 100.0 * float(r.raw_score) / maxf(300, float(r.judged) * 300) if r.judged > 0 else 100.0
		text_at(Vector2(x, 127), "%s · %.1f%%" % [choices[p].difficulty, acc], 15, MUTED, track_w)
		text_at(Vector2(x, 153), "%06d   %d streak   %d×" % [r.score, r.combo, r.multiplier], 17 if players_count >= 3 else 21, WHITE)
		road_quad(x, track_w, top, hit, 0, 4, top, hit + 12, Color(Color("171b1c"), highway_opacity))
		draw_hype(r, x, track_w, top, hit, COLORS[p])
		if visual_effects.combo_glow and r.multiplier > 1:
			road_quad(x, track_w, top, hit, 0, 4, top, hit, Color(COLORS[p], highway_opacity * 0.025 * (int(r.multiplier) - 1)))
		if visual_effects.combo_glow and r.combo_pulse > 0:
			var pulse: float = float(r.combo_pulse) / 1.2
			road_quad(x, track_w, top, hit, 0, 4, top, hit, Color(COLORS[p], highway_opacity * pulse * 0.12))
			text_at(Vector2(x + 10, top + 38), str(r.milestone), 18, Color(WHITE, pulse), track_w - 20)
		for lane in range(4):
			var left: float = x + lane * lane_w
			road_quad(x, track_w, top, hit, lane + 0.02, lane + 0.98, top, hit, Color(LANE_COLORS[lane], highway_opacity * 0.065))
			if visual_effects.lane_flashes and r.held[lane]:
				road_quad(x, track_w, top, hit, lane + 0.03, lane + 0.97, top, hit, Color(LANE_COLORS[lane], 0.12))
			var flash: float = float(r.lane_flash[lane]) / 0.28
			if visual_effects.lane_flashes and flash > 0:
				road_quad(x, track_w, top, hit, lane + 0.03, lane + 0.97, top, hit, Color(LANE_COLORS[lane], flash * 0.15))
				draw_rect(Rect2(left + 3, hit - 22, lane_w - 6, 44), Color(LANE_COLORS[lane], flash * 0.45))
			draw_line(road_point(x, track_w, top, hit, lane, top), road_point(x, track_w, top, hit, lane, hit), Color(WHITE, highway_opacity * 0.38), 1.5, true)
			draw_note_sprite(Vector2(left + lane_w / 2, hit), lane_w, Color(LANE_COLORS[lane], 0.55))
			var name: String = OS.get_keycode_string(int(bindings[p][lane]))
			text_at(Vector2(left + 12, hit + 35), name, 16, LANE_COLORS[lane], lane_w - 15)
		draw_line(road_point(x, track_w, top, hit, 4, top), road_point(x, track_w, top, hit, 4, hit), Color(WHITE, highway_opacity * 0.38), 1.5, true)
		var now: float = chart_time()
		var visible_end: int = int(r.cursor)
		while visible_end < r.notes.size() and float(r.notes[visible_end].t) <= now + visible_seconds:
			visible_end += 1
		# Draw far notes first so nearer note heads stay readable.
		for i in range(visible_end - 1, int(r.cursor) - 1, -1):
			var n: Dictionary = r.notes[i]
			if n.state >= 2:
				continue
			var lane: float = float(n.lane)
			var y: float = hit - (float(n.t) - now) * pixels
			var tail: float = hit - (float(n.end) - now) * pixels
			if n.state == 1:
				y = hit
			if float(n.end) > float(n.t):
				var a: float = clampf(tail, top, hit + 12)
				var b: float = clampf(y, top, hit + 12)
				if b > a:
					road_quad(x, track_w, top, hit, lane + 0.3, lane + 0.7, a, b, Color(LANE_COLORS[int(lane)], 0.65))
				if visual_effects.hold_shimmer and n.state == 1 and b > a:
					var shimmer_y: float = lerpf(b, a, fposmod(time_s * 1.5, 1.0))
					draw_line(road_point(x, track_w, top, hit, lane + 0.3, shimmer_y), road_point(x, track_w, top, hit, lane + 0.7, shimmer_y), Color(WHITE, 0.65), 3, true)
				if tail >= top and tail <= hit + 12:
					draw_line(road_point(x, track_w, top, hit, lane + 0.1, tail), road_point(x, track_w, top, hit, lane + 0.9, tail), LANE_COLORS[int(lane)], 4, true)
			if y >= top and y <= hit + 12:
				var center: Vector2 = road_point(x, track_w, top, hit, lane + 0.5, y)
				var note_width: float = road_point(x, track_w, top, hit, lane + 1, y).x - road_point(x, track_w, top, hit, lane, y).x
				if visual_effects.note_trails:
					for trail in range(1, 4):
						var trail_y: float = y - trail * 9
						if trail_y >= top:
							draw_note_sprite(road_point(x, track_w, top, hit, lane + 0.5, trail_y), note_width * (1.0 - trail * 0.1), Color(LANE_COLORS[int(lane)], 0.16 / trail))
				draw_note_sprite(center, note_width, LANE_COLORS[int(lane)])
				if bool(n.get("recovery", false)):
					draw_arc(center, note_width * 0.43, 0, TAU, 24, WHITE, 2.0, true)
		for edge in [0, 4]:
			var far = road_point(x, track_w, top, hit, edge, top)
			var near = road_point(x, track_w, top, hit, edge, hit)
			draw_line(far, near, Color(COLORS[p], highway_opacity * 0.12), 9, true)
			draw_line(far, near, Color(COLORS[p], highway_opacity * 0.8), 2, true)
		draw_line(Vector2(x, hit + 4), Vector2(x + track_w, hit + 4), Color(COLORS[p], 0.16), 12)
		draw_line(Vector2(x, hit), Vector2(x + track_w, hit), COLORS[p], 2)
		for effect in r.effects:
			var progress: float = float(effect.age) / 0.45
			var fade: float = 1.0 - progress
			var center: Vector2 = Vector2(x + (int(effect.lane) + 0.5) * lane_w, hit)
			var burst_color: Color = LANE_COLORS[int(effect.lane)]
			if visual_effects.hit_rings:
				draw_arc(center, 8 + progress * 38, 0, TAU, 24, Color(burst_color, fade * 0.8), 2.0, true)
			var power: int = int(effect.get("power", 1))
			if visual_effects.hit_rings and power > 1:
				draw_arc(center, 14 + progress * (45 + power * 9), 0, TAU, 32, Color(burst_color, fade * 0.6), 2.0, true)
			var sparks: int = 4 + 4 * power
			for spark in range(sparks if visual_effects.hit_sparks else 0):
				var angle: float = float(spark) * TAU / float(sparks)
				var pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * (12 + progress * (36 + power * 12)) + Vector2(0, -progress * (12 + power * 6))
				draw_circle(pos, 1.5 + fade * 1.5, Color(burst_color, fade))
		if visual_effects.judgements and r.flash > 0:
			text_at(Vector2(x + 15, hit - 48), str(r.message), 25 + int(5 * float(r.flash) / 0.6), Color("fa7f96") if r.message == "MISS" else WHITE)
		if visual_effects.miss_flash and r.message == "MISS" and r.flash > 0:
			draw_rect(Rect2(x, top, track_w, hit - top), Color(1, 0.18, 0.3, float(r.flash) * 0.6), false, 3.0)
		text_at(Vector2(x, h - 36), "BEST %d×   MISSES %d" % [r.best, r.miss], 14, MUTED)
	if time_s < 0:
		text_at(Vector2(w / 2 - 55, h / 2), str(int(ceil(-time_s))), 82, WHITE)
	if online_game:
		text_at(Vector2(28, 185), "LIVE LOBBY", 17, COLORS[0])
		var remote_y: float = 212
		for peer in online.state.get("players", []):
			text_at(Vector2(28, remote_y), str(peer.name), 16, WHITE, 245)
			text_at(Vector2(28, remote_y + 23), "%d pts · %d streak" % [int(peer.score), int(peer.combo)], 14, MUTED, 245)
			remote_y += 60
	text_at(Vector2(28, h - 16), "ESC  Leave online round" if online_game else "ESC  Pause       F5  Restart", 13, MUTED)

func show_results() -> void:
	last_timing.clear()
	for run in runs:
		var summary: Dictionary = Calibration.summarize(run.get("timing_samples", []), float(run.get("start_offset", offset_ms)))
		summary["profile"] = str(run.profile)
		summary["song"] = str(selected.title)
		last_timing.append(summary)
	var timing_file = FileAccess.open("user://last-timing.json", FileAccess.WRITE)
	if timing_file:
		timing_file.store_string(JSON.stringify(last_timing))
	record_completed_runs()
	screen = "results"
	audio.stop()
	stop_background_video()
	clear_ui()
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(center)
	var root = box_into(center)
	label_into(root, "SESSION COMPLETE", 38, COLORS[0])
	label_into(root, str(selected.title), 22)
	var row = box_into(root, true)
	for p in range(players_count):
		var r: Dictionary = runs[p]
		var card = box_into(row)
		card.custom_minimum_size.x = 255
		label_into(card, str(r.profile), 22, COLORS[p])
		label_into(card, str(choices[p].instrument) + " / " + str(choices[p].difficulty), 16)
		var acc: float = 100.0 * float(r.raw_score) / maxf(300, float(r.notes.size()) * 300)
		label_into(card, ScoreStore.grade(acc), 64, COLORS[p])
		label_into(card, "%.2f%%" % acc, 36)
		label_into(card, "%06d points" % r.score, 20)
		label_into(card, "Best streak  %d  /  Peak %d×" % [r.best, multiplier_for(int(r.best))], 16)
		if r.new_best:
			label_into(card, "NEW PERSONAL BEST", 16, COLORS[p])
		elif not str(r.save_error).is_empty():
			label_into(card, str(r.save_error), 13, Color("fa7f96"))
		label_into(card, "Perfect  %d\nGreat  %d\nGood  %d\nMiss  %d" % [r.perfect, r.great, r.good, r.miss], 18, MUTED)
	var buttons = box_into(root, true)
	if online.connected():
		button_into(buttons, "Lobby / live results", show_online_menu)
		button_into(buttons, "Leave lobby", func():
			online.leave()
			abort_online("Left lobby."))
	else:
		button_into(buttons, "Play again", start_game)
		button_into(buttons, "Song library", show_menu)
	button_into(buttons, "Personal bests", show_leaderboard)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		cancel_import()
		if online.connected():
			online.leave()

func open_online() -> void:
	commit_player_names()
	if selected.is_empty():
		return
	if not online.connected():
		var shared: Dictionary = network_source_song()
		var path: String = str(shared.folder).path_join(str(shared.audio))
		var audio_hash: String = FileAccess.get_sha256(path)
		if audio_hash.is_empty():
			last_message = "Could not read the selected song for multiplayer."
			show_menu()
			return
		online_fingerprint = JSON.stringify(["hype-v1", selected.charts, selected.get("timing", []), selected.get("hype", {}), audio_hash]).sha256_text()
	show_online_menu()

func show_online_menu() -> void:
	screen = "online"
	audio.stop()
	stop_background_video()
	clear_ui()
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	ui.add_child(margin)
	var scroll = ScrollContainer.new()
	margin.add_child(scroll)
	var root = box_into(scroll)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_into(root, "MULTIPLAYER", 32, COLORS[0])
	label_into(root, "Up to four PCs · One player per PC · Your local P1 keys", 17, MUTED)
	label_into(root, str(online.state.get("title", selected.get("title", ""))) if online.connected() else str(selected.get("title", "")), 24)
	if not online.connected():
		label_into(root, "Join first, then download the host's song, charts and video from the lobby.", 16, MUTED)
		var mode = OptionButton.new()
		mode.add_item("LAN")
		mode.add_item("Internet")
		mode.select(online_mode)
		root.add_child(mode)
		label_into(root, "Server address", 16)
		var address = LineEdit.new()
		address.name = "LobbyAddress"
		address.text = online_url
		address.placeholder_text = "http://192.168.1.20:27440 or https://your-lobby-server"
		root.add_child(address)
		var local_server = CheckBox.new()
		local_server.text = "Start a LAN server on this PC when creating a lobby"
		local_server.button_pressed = online_mode == 0
		local_server.disabled = online_mode != 0
		root.add_child(local_server)
		mode.item_selected.connect(func(i):
			online_mode = i
			local_server.button_pressed = i == 0
			local_server.disabled = i != 0
			address.text = "http://127.0.0.1:27440" if i == 0 else ""
			address.placeholder_text = "Host PC's LAN address" if i == 0 else "Public server URL, preferably https://")
		label_into(root, "Internet play needs a reachable lobby server. Server software and setup instructions are included.", 15, MUTED)
		label_into(root, "Lobby name", 16)
		var room_field = LineEdit.new()
		room_field.name = "LobbyRoomName"
		room_field.text = online_room
		room_field.max_length = 40
		root.add_child(room_field)
		label_into(root, "Lobby password", 16)
		var password = LineEdit.new()
		password.name = "LobbyPassword"
		password.secret = true
		password.max_length = 128
		root.add_child(password)
		var buttons = box_into(root, true)
		button_into(buttons, "Create lobby", func():
			online_room = room_field.text.strip_edges()
			online_url = address.text.strip_edges()
			if local_server.button_pressed:
				if not online.launch_local_server():
					return
				online_url = "http://127.0.0.1:27440"
				await get_tree().create_timer(1.0).timeout
			if not is_instance_valid(password):
				return
			online.enter(online_url, online_room, password.text, profile_names[0], online_fingerprint, str(selected.title), true))
		button_into(buttons, "Join lobby", func():
			online_room = room_field.text.strip_edges()
			online_url = address.text.strip_edges()
			online.enter(online_url, online_room, password.text, profile_names[0], online_fingerprint, str(selected.title), false))
		button_into(buttons, "Back", func():
			online.leave()
			show_menu())
	else:
		label_into(root, str(online.state.get("room", "Lobby")), 24, COLORS[1])
		var addresses: PackedStringArray = []
		for address in IP.get_local_addresses():
			if "." in address and not address.begins_with("127.") and not address.begins_with("169.254."):
				addresses.append("http://" + address + ":27440")
		if online.local_server_pid > 0:
			label_into(root, "Friends on your LAN can connect to: " + ", ".join(addresses), 15, MUTED)
		var roster = label_into(root, "", 18)
		roster.name = "OnlineRoster"
		if online.current_player().get("matched", false):
			var selection = box_into(root, true)
			var instruments: Array = selected.charts.keys()
			var instrument = OptionButton.new()
			instrument.name = "OnlineInstrument"
			for part in instruments:
				instrument.add_item(str(part))
			instrument.select(instruments.find(choices[0].instrument))
			instrument.disabled = float(online.state.get("start_at", 0)) > 0
			selection.add_child(instrument)
			instrument.item_selected.connect(func(i):
				choices[0].instrument = instruments[i]
				preferred_choices[0]["instrument"] = instruments[i]
				resolve_player_choice(0)
				save_settings()
				online_ready(false)
				show_online_menu())
			var diffs: Array = selected.charts[choices[0].instrument].keys()
			var difficulty = OptionButton.new()
			for diff in diffs:
				difficulty.add_item(str(diff))
			difficulty.select(diffs.find(choices[0].difficulty))
			difficulty.disabled = float(online.state.get("start_at", 0)) > 0
			selection.add_child(difficulty)
			difficulty.item_selected.connect(func(i):
				choices[0].difficulty = diffs[i]
				preferred_choices[0]["difficulty"] = diffs[i]
				save_settings()
				online_ready(false))
		var transfer_buttons = box_into(root, true)
		if online.is_host():
			button_into(transfer_buttons, "Share / retry song upload", func(): pack_transfer.begin_upload(network_source_song())).name = "OnlineShare"
		else:
			button_into(transfer_buttons, "Download host's song + chart + video", func():
				online_ready(false)
				pack_transfer.begin_download(online.state.get("files", []))).name = "OnlineDownload"
		button_into(transfer_buttons, "Cancel transfer", func(): pack_transfer.cancel())
		var buttons = box_into(root, true)
		button_into(buttons, "Ready", func(): online_ready(not bool(online.current_player().get("ready", false)))).name = "OnlineReady"
		if online.is_host():
			button_into(buttons, "Start round", func(): online.command("start")).name = "OnlineStart"
			button_into(buttons, "Return everyone to lobby", func(): online.command("reset"))
		button_into(buttons, "Leave lobby", func():
			online.leave()
			abort_online("Left lobby."))
	var message = label_into(root, online_message, 16, COLORS[0])
	message.name = "OnlineMessage"
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	update_online_lobby()

func online_ready(value: bool) -> void:
	if online_fingerprint != str(online.state.get("song", "")):
		if value:
			online_message = "Download the host's song before readying."
			update_online_lobby()
		return
	if selected.charts[choices[0].instrument][choices[0].difficulty].is_empty():
		online_message = "Choose a non-empty chart before readying."
		update_online_lobby()
		return
	online.command("ready", {"song": online_fingerprint, "instrument": choices[0].instrument, "difficulty": choices[0].difficulty, "ready": value})

func update_online_lobby() -> void:
	queue_redraw()
	if screen != "online" or not is_instance_valid(ui):
		return
	var message = ui.find_child("OnlineMessage", true, false) as Label
	if message != null:
		message.text = online_message + "\n" + str(online.state.get("notice", ""))
	if online.connected() and (bool(online.current_player().get("matched", false)) != (ui.find_child("OnlineInstrument", true, false) != null)):
		show_online_menu()
		return
	var roster = ui.find_child("OnlineRoster", true, false) as Label
	if roster == null:
		return
	var rows: PackedStringArray = []
	var all_ready: bool = online.state.get("players", []).size() >= 2
	for peer in online.state.get("players", []):
		rows.append("%s · %s / %s · %s · %d pts · %.1f%%" % [peer.name, peer.instrument, peer.difficulty, "Needs song download" if not peer.get("matched", false) else "Finished" if peer.finished else "Ready" if peer.ready else "Not ready", int(peer.score), float(peer.accuracy)])
		all_ready = all_ready and bool(peer.ready)
	roster.text = "\n".join(rows)
	var ready = ui.find_child("OnlineReady", true, false) as Button
	if ready != null:
		ready.text = "Unready" if bool(online.current_player().get("ready", false)) else "Ready"
		ready.disabled = float(online.state.get("start_at", 0)) > 0 or not bool(online.current_player().get("matched", false)) or pack_transfer.busy
	var download = ui.find_child("OnlineDownload", true, false) as Button
	if download != null:
		download.disabled = not bool(online.state.get("published", false)) or pack_transfer.busy or float(online.state.get("start_at", 0)) > 0
	var share = ui.find_child("OnlineShare", true, false) as Button
	if share != null:
		share.disabled = pack_transfer.busy or float(online.state.get("start_at", 0)) > 0
	var start = ui.find_child("OnlineStart", true, false) as Button
	if start != null:
		start.disabled = not all_ready or float(online.state.get("start_at", 0)) > 0 or pack_transfer.busy

func begin_online_round(at: float, _round_id: int) -> void:
	if online.server_time() > at + 0.5:
		online.leave()
		abort_online("Round start arrived too late. Rejoin and try again.")
		return
	var player: Dictionary = online.current_player()
	var part: String = str(player.get("instrument", ""))
	var difficulty: String = str(player.get("difficulty", ""))
	if not selected.charts.has(part) or not selected.charts[part].has(difficulty) or selected.charts[part][difficulty].is_empty():
		online.leave()
		abort_online("The selected online chart is unavailable. Download the host's pack again.")
		return
	choices[0] = {"instrument": part, "difficulty": difficulty}
	online_start_at = at
	online_game = true
	players_count = 1
	online_launch = true
	start_game()
	online_launch = false

func abort_online(message: String) -> void:
	if pack_transfer.busy:
		pack_transfer.cancel()
	online_game = false
	online_start_at = 0.0
	audio.stop()
	stop_background_video()
	players_count = offline_players
	last_message = message
	online_message = message
	show_menu()

func install_online_pack(folder: String) -> void:
	if not online.connected():
		return
	var parser = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(folder.path_join("song.json"))) != OK or not valid_song(parser.data):
		online_message = "Downloaded chart is invalid. Nothing was installed."
		update_online_lobby()
		return
	var meta: Dictionary = parser.data
	var fingerprint: String = JSON.stringify(["hype-v1", meta.charts, meta.get("timing", []), meta.get("hype", {}), FileAccess.get_sha256(folder.path_join("audio.wav"))]).sha256_text()
	if fingerprint != str(online.state.get("song", "")):
		online_message = "Downloaded song does not match the host. Retry the transfer."
		update_online_lobby()
		return
	var identity: String = "net-" + fingerprint
	meta.id = identity
	meta.title = str(meta.get("title", "Host song")).left(160)
	meta.artist = str(meta.get("artist", "Multiplayer")).left(160)
	meta.category = str(meta.get("category", "Built-in"))
	meta.duration = float(meta.get("duration", 0))
	meta.erase("folder")
	if meta.get("background_image", "") != "background.png":
		meta.erase("background_image")
	if meta.get("video", "") != "background.ogv":
		meta.erase("video")
	var output = FileAccess.open(folder.path_join("song.json"), FileAccess.WRITE)
	if output == null:
		online_message = "Could not save downloaded song metadata."
		update_online_lobby()
		return
	output.store_string(JSON.stringify(meta))
	output.close()
	var destination: String = song_root.path_join(song_folder_name(meta) + "-" + str(Time.get_ticks_usec()))
	if DirAccess.rename_absolute(folder, destination) != OK:
		online_message = "Could not install the downloaded song. Check free disk space."
		update_online_lobby()
		return
	meta.folder = destination
	selected = meta
	online_fingerprint = fingerprint
	resolve_player_choice(0)
	scan_songs()
	online_ready(false)
	online_message = "Host's song, charts and available video downloaded. Choose your part, then Ready."
	show_online_menu()

func draw_arcade_backdrop() -> void:
	var w: float = size.x
	var h: float = size.y
	if screen == "game":
		if (not is_instance_valid(background_video) or not background_video.visible) and (not is_instance_valid(background_image) or not background_image.visible):
			draw_rect(Rect2(Vector2.ZERO, size), Color("101516"))
			for x in range(0, int(w), 48):
				draw_line(Vector2(x, 0), Vector2(x, h), Color(1, 1, 1, 0.025))
		draw_rect(Rect2(16, 12, w - 32, 55), Color("262d2e"))
		draw_rect(Rect2(16, 12, 6, 55), GraphicSkin.RED)
		return
	for band in range(32):
		var shade = Color("1b2437").lerp(Color("070a12"), float(band) / 31)
		draw_rect(Rect2(0, h * band / 32.0, w, h / 32.0 + 1), shade)
	# Cabinet vents, segmented edge meters and a slow radar sweep.
	for y in range(0, int(h), 4):
		draw_line(Vector2(0, y), Vector2(w, y), Color(0, 0, 0, 0.13))
	for side in [0, 1]:
		for segment in range(24):
			var energy: float = 0.12 + 0.16 * (sin(ui_clock * 2.0 - segment * 0.3) + 1)
			draw_rect(Rect2(5 if side == 0 else w - 12, h - 30 - segment * 20, 7, 13), Color(COLORS[side], energy))
	var center = Vector2(w * 0.32, h * 0.42)
	for ring in range(4):
		draw_arc(center, 130 + ring * 46, ui_clock * 0.08 + ring, ui_clock * 0.08 + ring + 4.5, 70, Color(0.35, 0.55, 0.8, 0.06), 2, true)
	draw_rect(Rect2(18, 0, w - 36, 5), Color("697d99"))
	draw_rect(Rect2(18, h - 7, w - 36, 7), Color("202e46"))

func network_source_song() -> Dictionary:
	var song: Dictionary = selected.duplicate(true)
	# Imported WAV resources may be converted inside the exported PCK. The
	# release carries a raw demo copy specifically for hashing and sharing.
	if str(song.get("folder", "")).begins_with("res://") and not OS.has_feature("editor"):
		song.folder = OS.get_executable_path().get_base_dir().path_join("shared-demo")
	return song

func apply_audio_levels() -> void:
	audio.volume_db = linear_to_db(maxf(volume * music_volume, 0.000001))
	hit_audio.volume_db = linear_to_db(maxf(volume * hit_volume, 0.000001))
	miss_audio.volume_db = linear_to_db(maxf(volume * miss_volume, 0.000001))
	if volume == 0 or hit_volume == 0:
		hit_audio.stop()
	if volume == 0 or miss_volume == 0:
		miss_audio.stop()

func add_audio_slider(parent: Node, title: String, property: String) -> void:
	var caption = label_into(parent, title + "  %d%%" % int(float(get(property)) * 100), 14)
	var slider = HSlider.new()
	slider.name = property
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = float(get(property))
	slider.custom_minimum_size.x = 360
	parent.add_child(slider)
	slider.value_changed.connect(func(value):
		set(property, value)
		caption.text = title + "  %d%%" % int(value * 100)
		apply_audio_levels()
		save_settings())

func add_effect_toggle(parent: Node, title: String, key: String) -> void:
	var toggle = CheckBox.new()
	toggle.name = "Effect_" + key
	toggle.text = title
	toggle.button_pressed = visual_effects[key]
	parent.add_child(toggle)
	toggle.toggled.connect(func(value):
		visual_effects[key] = value
		save_settings()
		queue_redraw())

func make_feedback_sound(missed: bool) -> AudioStreamWAV:
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 44100
	var duration: float = 0.14 if missed else 0.045
	var count: int = int(duration * stream.mix_rate)
	var bytes = PackedByteArray()
	bytes.resize(count * 2)
	for i in range(count):
		var t: float = float(i) / stream.mix_rate
		var envelope: float = minf(1.0, t / 0.002) * pow(1.0 - t / duration, 3)
		var wave: float = sin(TAU * (220 * t - 420 * t * t)) * 0.7 + sin(TAU * 83 * t) * 0.3 if missed else sin(TAU * 1500 * t) * 0.65 + sin(TAU * 3200 * t) * 0.35
		bytes.encode_s16(i * 2, int(wave * envelope * 6500))
	stream.data = bytes
	return stream

func play_feedback(missed: bool) -> void:
	var index: int = 1 if missed else 0
	var level: float = miss_volume if missed else hit_volume
	var now: int = Time.get_ticks_msec()
	# Chords share one transient, avoiding a pile-up at the same timestamp.
	if volume <= 0 or level <= 0 or now - int(last_sound[index]) < 20:
		return
	last_sound[index] = now
	var player: AudioStreamPlayer = miss_audio if missed else hit_audio
	player.play()

func draw_song_visualizer(highway_start: float) -> void:
	var available: float = highway_start - 48.0
	if available < 70.0:
		return
	var width: float = minf(available, 300.0)
	var baseline: float = size.y - 82.0
	var height: float = minf(160.0, size.y * 0.2)
	for side in range(2):
		var origin: float = 24.0 if side == 0 else size.x - 24.0 - width
		if visual_effects.bass_glow and music_visualizer.bass > 0.01:
			for layer in range(6):
				var edge: float = 4.0 + layer * 5.0
				var x: float = 0.0 if side == 0 else size.x - edge
				draw_rect(Rect2(x, baseline - height - 20, edge, height + 40), Color(COLORS[side], music_visualizer.bass * 0.045))
		if not visual_effects.audio_visualizer:
			continue
		var step: float = width / music_visualizer.BANDS
		for i in range(music_visualizer.BANDS):
			var energy: float = music_visualizer.levels[i].x if side == 0 else music_visualizer.levels[i].y
			var band: int = i if side == 0 else music_visualizer.BANDS - 1 - i
			var x: float = origin + band * step
			var tint: Color = LANE_COLORS[mini(3, int(float(i) * 4.0 / music_visualizer.BANDS))]
			var bar_height: float = maxf(2.0, energy * height)
			draw_rect(Rect2(x, baseline - bar_height, maxf(1.0, step - 3.0), bar_height), Color(tint, 0.25 + energy * 0.45))
			if energy > 0.01:
				draw_rect(Rect2(x, baseline - bar_height, maxf(1.0, step - 3.0), 2.0), Color(WHITE, energy * 0.7))

func hype_enabled() -> bool:
	return true if online.connected() else bool(hype_settings.enabled)

func hype_bonus() -> float:
	return 2.0 if online.connected() else float(hype_settings.bonus)

func hype_sensitivity() -> float:
	return 0.5 if online.connected() else float(hype_settings.sensitivity)

func hype_multiplier(run: Dictionary) -> float:
	return Hype.multiplier(run, hype_enabled(), hype_bonus())

func add_hype_slider(parent: Control, title: String, key: String) -> void:
	var caption = label_into(parent, title + ": " + str(hype_settings[key]), 15)
	var slider = HSlider.new()
	slider.name = "Hype_" + key
	slider.custom_minimum_size.x = 340
	slider.min_value = 1.0 if key == "bonus" else 0.0
	slider.max_value = 3.0 if key == "bonus" else 1.0
	slider.step = 0.1 if key == "bonus" else 0.05
	slider.value = float(hype_settings[key])
	slider.value_changed.connect(func(value):
		hype_settings[key] = value
		caption.text = title + ": " + ("%.1f×" % value if key == "bonus" else "%d%%" % int(value * 100))
		save_settings())
	parent.add_child(slider)

func hype_shake() -> Vector2:
	if screen != "game" or paused or not playing or reduced_motion:
		return Vector2.ZERO
	var pulse: float = 0.0
	for run in runs:
		if int(run.get("hype_index", -1)) >= 0:
			pulse = maxf(pulse, Hype.beat_pulse(time_s, run.timing))
	var strength: float = 6.0 * float(hype_settings.shake) * pulse
	return Vector2(sin(time_s * 73.0), cos(time_s * 59.0)) * strength

func draw_hype(run: Dictionary, x: float, width: float, top: float, hit: float, tint: Color) -> void:
	var index: int = int(run.get("hype_index", -1))
	if index < 0:
		return
	var pulse: float = 0.0 if paused else Hype.beat_pulse(time_s, run.timing)
	var bonus: float = hype_multiplier(run)
	var kind: String = str(run.hype_sections[index].kind).to_upper()
	text_at(Vector2(x + 8, hit + 57), kind + ("  %.1f× BONUS" % bonus if bonus > 1.0 else "  BONUS LOST" if bool(run.get("hype_broken", false)) else "  HYPE"), 15, tint, width - 16)
	var glow: float = float(hype_settings.glow) * pulse * (0.08 + music_visualizer.bass * 0.08)
	road_quad(x, width, top, hit, 0, 4, top, hit, Color(tint, glow))
	if float(hype_settings.rings) > 0 and not paused:
		var radius: float = (1.0 - pulse) * width * 0.65 + 10.0
		draw_arc(Vector2(x + width / 2, hit), radius, PI, TAU, 40, Color(tint, float(hype_settings.rings) * pulse * 0.6), 3.0, true)

func add_calibration_panel(parent: Control) -> void:
	label_into(parent, "CALIBRATE FROM LAST SONG", 20, COLORS[0])
	label_into(parent, "Negative = early · Positive = late. The offset is shared; choose the player to calibrate for.", 14, MUTED)
	if last_timing.is_empty():
		label_into(parent, "Finish a song to record your timing. At least 12 hits are needed.", 14, MUTED)
	for data in last_timing:
		if not data is Dictionary:
			continue
		label_into(parent, str(data.get("profile", "Player")) + " / " + str(data.get("song", "Last song")), 16)
		if not data.has("median"):
			label_into(parent, "%d recorded hits — need at least 12." % int(data.get("count", 0)), 14, MUTED)
			continue
		label_into(parent, "%d early / %d late · Median %+.1f ms · Spread %.1f ms" % [int(data.early), int(data.late), float(data.median), float(data.spread)], 14, MUTED)
		if bool(data.get("ready", false)):
			var suggested: float = clampf(float(data.get("recommended", offset_ms)), -300, 300)
			button_into(parent, "Apply recommended offset: %+.0f ms" % suggested, func():
				offset_ms = suggested
				save_settings()
				show_settings())
		else:
			label_into(parent, "Timing was too variable for a reliable automatic adjustment. Try another song.", 14, MUTED)

func request_play(disc: Button) -> void:
	if selected.is_empty() or ui_motion.launching:
		return
	if not commit_preferences():
		return
	commit_player_names()
	var song_id: String = str(selected.id)
	ui_motion.launch(self, disc, preview, func():
		if screen == "menu" and not selected.is_empty() and str(selected.id) == song_id:
			start_game()
		else:
			apply_audio_levels())

func cleanup_old_installs() -> void:
	if OS.has_feature("editor") or OS.get_name() != "Windows" or DisplayServer.get_name() == "headless":
		return
	var folder: String = OS.get_executable_path().get_base_dir()
	var worker: String = folder.path_join("importer/PulseImporter.exe")
	if FileAccess.file_exists(worker):
		OS.create_process(worker, ["--cleanup-old-versions", folder])

func song_folder_name(song: Dictionary) -> String:
	var title: String = str(song.get("title", "Song")).validate_filename().strip_edges().left(70)
	while title.ends_with(".") or title.ends_with(" "):
		title = title.left(title.length() - 1)
	if title.is_empty(): title = "Song"
	var base: String = title.get_slice(".", 0).to_upper()
	if base in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]:
		title = "_" + title
	return title + " [" + str(song.get("id", "song")).sha256_text().left(10) + "]"
