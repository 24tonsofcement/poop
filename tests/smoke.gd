# Execute with Godot 4.4.1: --headless --path . --script tests/smoke.gd
extends SceneTree
var failures: int = 0
func check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
		push_error(description)

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var original_bus_count: int = AudioServer.bus_count
	var scene = load("res://game/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var fresh_card = Button.new()
	scene.stop_card_tween(fresh_card)
	scene.stop_card_tween(fresh_card)
	check(not fresh_card.has_meta("motion"), "Unanimated cards safely skip tween cleanup")
	fresh_card.free()
	check(scene.songs.size() >= 1, "Demo loads")
	check(scene.audio.bus == scene.music_visualizer.bus_name and scene.hit_audio.bus != scene.audio.bus, "Spectrum follows song audio separately from hit sounds")
	for count in range(1, 5):
		scene.players_count = count
		scene.show_menu()
		scene.start_game()
		check(scene.runs.size() == count, "Player run count")
		scene.audio.stop()
		scene.offset_ms = 0
		for p in range(count):
			var n: Dictionary = scene.runs[p].notes[0]
			scene.time_s = float(n.t)
			scene.key_hit(p, int(n.lane), true)
			if float(n.end) > float(n.t):
				scene.time_s = float(n.end)
				scene.key_hit(p, int(n.lane), false)
			check(scene.runs[p].score == 300, "Perfect timing awards 300")
	# Explicit scoring fixtures, independent of bundled chart contents.
	scene.players_count = 2
	scene.show_menu()
	scene.start_game()
	scene.audio.stop()
	scene.offset_ms = 0
	scene.runs[0].notes = [{"t": 1.0, "end": 2.0, "lane": 0, "state": 0, "points": 0}]
	scene.time_s = 1.0
	scene.key_hit(0, 0, true)
	check(scene.runs[0].notes[0].state == 1, "Hold enters held state")
	scene.time_s = 1.5
	scene.key_hit(0, 0, false)
	check(scene.runs[0].miss == 0 and scene.runs[0].score == 300 and scene.runs[0].combo == 1, "Early release preserves head score and streak")
	check(scene.runs[1].judged == 0, "Players score independently")
	scene.runs[0].notes = [{"t": 3.0, "end": 3.0, "lane": 0, "state": 0, "points": 0}]
	scene.runs[0].cursor = 0
	scene.time_s = 3.07
	scene.key_hit(0, 0, true)
	check(scene.runs[0].great == 1, "70ms timing is Great")
	scene.key_hit(0, 0, true)
	check(scene.runs[0].judged == 2, "Repeated input cannot score a note twice")
	scene.runs[0].notes = [{"t": 4.0, "end": 4.0, "lane": 1, "state": 0, "points": 0}]
	scene.runs[0].cursor = 0
	scene.offset_ms = 100
	scene.time_s = 4.1
	scene.key_hit(0, 1, true)
	check(scene.runs[0].perfect == 2, "Positive offset delays note judgement")
	scene.toggle_pause()
	check(scene.paused, "Pause enters paused state")
	scene.toggle_pause()
	check(not scene.paused, "Resume returns to gameplay")
	scene.show_results()
	check(scene.screen == "results", "Results render")
	scene.show_menu()
	check(scene.screen == "menu", "Return to menu")
	check_menu_update(scene)
	await check_menu_polish(scene)
	check(scene.ui.find_child("NoteSpeed", true, false) == null, "Preferences removed from song selection")
	check(scene.ui.find_child("PlayerCount", true, false) != null, "Player count restored to main menu")
	var main_instrument = scene.ui.find_child("Instrument0", true, false)
	var main_difficulty = scene.ui.find_child("Difficulty0", true, false)
	var main_profile = scene.ui.find_child("ProfileName0", true, false) as LineEdit
	check(main_instrument != null, "Instrument choice restored to song selection")
	check(main_profile != null and main_difficulty != null, "Player name and difficulty on main screen")
	if main_profile != null and main_difficulty != null:
		check(main_profile.get_parent() == main_difficulty.get_parent() and main_profile.get_index() == main_difficulty.get_index() + 1, "Player name directly follows difficulty")
		main_profile.text = "Test Bandmate"
		scene.show_menu()
		scene.load_settings()
		check(scene.profile_names[0] == "Test Bandmate", "Main player name survives menu rebuild and reload")

	scene.show_settings()
	check(scene.screen == "settings", "Dedicated settings screen opens")
	check(scene.ui.find_child("Instrument0", true, false) == null and scene.ui.find_child("ProfileName0", true, false) == null, "Instrument and name removed from preferences")
	check(scene.ui.find_child("PlayerCount", true, false) == null, "Player count is not in settings")
	var highway = scene.ui.find_child("HighwayTransparency", true, false) as HSlider
	check(highway != null, "Highway transparency slider exists")
	if highway != null:
		highway.value = 1.0
		scene.load_settings()
		check(scene.highway_opacity == 0.0, "Transparent highway persists")
		highway.value = 0.0
		check(scene.highway_opacity == 1.0, "Opaque highway endpoint")
		highway.value = 0.18
	check(scene.LANE_COLORS[0] != scene.LANE_COLORS[1] and scene.LANE_COLORS[1] != scene.LANE_COLORS[2] and scene.LANE_COLORS[2] != scene.LANE_COLORS[3], "Distinct lane colors")
	var dimming = scene.ui.find_child("VideoDimming", true, false) as HSlider
	check(dimming != null, "Video dimming slider exists")
	if dimming != null:
		dimming.value = 0.0
		scene.load_settings()
		check(scene.video_opacity == 1.0, "Zero dimming permits full brightness after reload")
		dimming.value = 1.0
		check(scene.video_opacity == 0.0, "Full dimming disables video")
		dimming.value = 0.78
	var near_left: Vector2 = scene.road_point(100, 400, 170, 600, 0, 600)
	var near_right: Vector2 = scene.road_point(100, 400, 170, 600, 4, 600)
	var far_left: Vector2 = scene.road_point(100, 400, 170, 600, 0, 170)
	var far_right: Vector2 = scene.road_point(100, 400, 170, 600, 4, 170)
	check(near_left.is_equal_approx(Vector2(100, 600)) and near_right.is_equal_approx(Vector2(500, 600)), "Projection preserves hit line")
	check(far_right.x - far_left.x < near_right.x - near_left.x, "Lanes converge toward horizon")
	# Values above the old scroll limit must survive application and reload.
	var previous_speed: float = scene.scroll_speed
	var speed_field = scene.ui.find_child("NoteSpeed", true, false) as LineEdit
	check(speed_field != null, "Uncapped note speed field exists")
	if speed_field != null:
		speed_field.text = "1000000"
		check(scene.apply_note_speed(speed_field), "Large note speed accepted")
		scene.load_settings()
		check(scene.scroll_speed == 1000000.0, "Large speed reloads without clamping")
		speed_field.text = "0.001"
		check(scene.apply_note_speed(speed_field), "Small positive speed accepted")
		for invalid in ["0", "-2", "abc", "inf"]:
			speed_field.text = invalid
			check(not scene.apply_note_speed(speed_field), "Invalid speed rejected")
		speed_field.text = str(previous_speed)
		scene.apply_note_speed(speed_field)
	scene.show_menu()
	# Holding through the tail scores once, independently of note speed.
	scene.start_game()
	scene.audio.stop()
	scene.offset_ms = 0
	scene.runs[0].notes = [{"t": 1.0, "end": 2.0, "lane": 0, "state": 0, "points": 0}]
	scene.time_s = 1.0
	scene.key_hit(0, 0, true)
	scene.time_s = 2.0
	scene.key_hit(0, 0, false)
	check(scene.runs[0].score == 300 and scene.runs[0].judged == 1, "Completed hold scores once")
	check(scene.runs[0].effects.size() == 2, "Successful hold head and tail emit hit effects")
	check(scene.runs[0].lane_flash[0] > 0, "Successful hit flashes its lane")
	scene.key_hit(0, 0, false)
	check(scene.runs[0].judged == 1, "Hold tail cannot score twice")
	run_hype_calibration_checks(scene)
	run_hold_bar_checks(scene)
	run_arcade_checks(scene)
	await run_video_checks(scene)
	scene.queue_free()
	await process_frame
	await process_frame
	check(AudioServer.bus_count == original_bus_count, "Song analysis bus removed when scene is freed")
	print("Godot smoke failures: ", failures)
	quit(1 if failures else 0)

func run_arcade_checks(scene) -> void:
	for streak in [0, 19, 20, 49, 50, 99, 100, 500]:
		var expected: int = 4 if streak >= 100 else 3 if streak >= 50 else 2 if streak >= 20 else 1
		check(scene.multiplier_for(streak) == expected, "Combo threshold %d" % streak)
	scene.start_game()
	scene.audio.stop()
	for i in range(20):
		scene.judge(0, {"state": 0, "lane": 0, "t": 0.0, "end": 0.0}, 300)
	check(scene.runs[0].score == 6300, "Twentieth hit earns 2x")
	check(scene.runs[0].raw_score == 6000, "Accuracy stays based on raw judgements")
	check(scene.runs[0].combo_pulse > 0, "Combo milestone triggers extra effects")
	scene.judge(0, {"state": 0, "lane": 1, "t": 0.0, "end": 0.0}, 0)
	check(scene.runs[0].multiplier == 1 and scene.runs[0].combo == 0, "Miss resets multiplier")
	scene.judge(0, {"state": 0, "lane": 2, "t": 0.0, "end": 0.0}, 300)
	check(scene.runs[0].score == 6600, "First hit after miss uses 1x")
	var fixture: Dictionary = {"category": "YouTube", "charts": {"Bass": {"Hard": [
		{"t": 0.0, "end": 8.0, "lane": 0}, {"t": 1.0, "end": 8.0, "lane": 1},
		{"t": 2.0, "end": 8.0, "lane": 2}, {"t": 3.0, "end": 8.0, "lane": 3}]}}}
	scene.cap_generated_holds(fixture)
	check(fixture.charts.Bass.Hard[2].end == 2.0 and fixture.charts.Bass.Hard[3].end == 3.0, "Cached charts also cap simultaneous holds")
	var old_style: String = scene.note_style
	for style in ["Bar", "Circle", "Arrows", "Square"]:
		scene.note_style = style
		scene.save_settings()
		scene.load_settings()
		check(scene.note_style == style, "Note style persists: " + style)
	scene.note_style = old_style
	scene.save_settings()
	var Store = load("res://game/score_store.gd")
	var store = Store.new()
	store.path = "user://score-smoke-%d.json" % Time.get_ticks_usec()
	store.load_data()
	var meta: Dictionary = {"song_id": "fixture", "instrument": "Bass", "difficulty": "Hard"}
	var a: Dictionary = {"name": "Ada", "score": 1000, "accuracy": 98.0, "combo": 20}
	var b: Dictionary = {"name": "Bo", "score": 900, "accuracy": 99.0, "combo": 30}
	check(store.submit("chart-a", meta, a).saved, "First PB saves")
	check(store.submit("chart-a", meta, b).saved, "Second profile saves")
	check(store.entries("chart-a")[0].name == "Ada", "Leaderboard sorts by score")
	a.score = 800
	check(not store.submit("chart-a", meta, a).improved, "Worse result cannot replace PB")
	a.name = "ada"
	a.score = 1200
	check(store.submit("chart-a", meta, a).improved, "Better score replaces same profile")
	check(store.entries("chart-a").size() == 2, "One PB per normalized player name")
	check(store.submit("chart-b", meta, b).saved, "Different chart has its own table")
	var reloaded = Store.new()
	reloaded.path = store.path
	reloaded.load_data()
	check(reloaded.best_for("chart-a", "ADA").score == 1200, "PB survives save/load")
	check(reloaded.entries("chart-b").size() == 1, "Chart tables stay separate")
	var corrupt = FileAccess.open(store.path, FileAccess.WRITE)
	corrupt.store_string("broken fixture")
	corrupt.close()
	reloaded.load_data()
	check(not reloaded.warning.is_empty() and not reloaded.entries("chart-a").is_empty(), "Backup recovers corrupted score file")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(store.path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(store.path + suffix))
	scene.show_leaderboard()
	check(scene.screen == "leaderboard", "Song leaderboard opens")
	scene.show_menu()

func run_video_checks(scene) -> void:
	var original: Dictionary = scene.selected
	var fixture: Dictionary = original.duplicate(true)
	fixture.folder = ProjectSettings.globalize_path("res://build/video-test")
	fixture.video = "background.ogv"
	check(FileAccess.file_exists(str(fixture.folder).path_join("background.ogv")), "Video smoke fixture exists")
	scene.selected = fixture
	scene.video_opacity = 0.22
	scene.prepare_background_video()
	check(scene.background_video.stream != null, "Theora video loads")
	check(scene.background_video.volume == 0.0, "Video has no duplicate audio")
	check(is_equal_approx(scene.background_video.modulate.a, 0.22), "Video is transparent")
	scene.background_video.visible = true
	scene.background_video.play()
	await create_timer(0.15).timeout
	check(scene.background_video.is_playing(), "Video playback starts")
	scene.toggle_pause()
	check(scene.background_video.paused, "Video pauses with gameplay")
	scene.toggle_pause()
	check(not scene.background_video.paused, "Video resumes with gameplay")
	scene.stop_background_video()
	check(not scene.background_video.visible and not scene.background_video.is_playing(), "Video stops on navigation")
	scene.video_opacity = 0.0
	scene.prepare_background_video()
	check(scene.background_video.stream == null, "Zero opacity disables video loading")
	scene.video_opacity = 0.22
	scene.selected = original
	scene.show_menu()

func run_hold_bar_checks(scene) -> void:
	var tempo: Array = [{"t": 0.0, "beat_length": 0.5, "meter": 4}]
	check(is_equal_approx(scene.bars_between(0.0, 4.0, tempo), 2.0), "120 BPM four-four: four seconds is two bars")
	var changes: Array = [{"t": 0.0, "beat_length": 0.5, "meter": 4}, {"t": 2.0, "beat_length": 1.0, "meter": 3}]
	check(is_equal_approx(scene.bars_between(0.0, 5.0, changes), 2.0), "Hold bars follow tempo and meter changes")
	scene.start_game()
	scene.audio.stop()
	scene.offset_ms = 0
	var r: Dictionary = scene.runs[0]
	r.timing = tempo
	var hold: Dictionary = {"t": 0.0, "end": 4.0, "lane": 0, "state": 0, "points": 0}
	r.notes = [hold]
	scene.time_s = 0.0
	scene.key_hit(0, 0, true)
	check(r.score == 300 and r.combo == 1, "Hold head scores like a normal note")
	scene.award_hold_bars(0, hold, 2.0)
	check(r.score == 600 and r.judged == 1, "One sustained bar adds a perfect note bonus")
	scene.award_hold_bars(0, hold, 2.0)
	check(r.score == 600, "A bar cannot score twice")
	scene.time_s = 3.95
	scene.key_hit(0, 0, false)
	check(r.score == 900 and r.judged == 1 and hold.state == 2, "Two-bar hold adds 600 to its head score including release tolerance")
	check(r.raw_score == 300, "Sustain bonuses do not inflate accuracy")
	check(r.notes.size() == 1, "Completing a hold does not spawn a recovery tail")

	scene.start_game()
	scene.audio.stop()
	r = scene.runs[0]
	r.timing = tempo
	r.combo = 25
	r.multiplier = 2
	hold = {"t": 0.0, "end": 6.0, "lane": 0, "state": 0, "points": 0}
	r.notes = [hold]
	scene.time_s = 0.0
	scene.key_hit(0, 0, true)
	scene.time_s = 2.5
	scene.key_hit(0, 0, false)
	check(r.score == 1200, "Head and first bar use active combo multiplier")
	check(r.combo == 26 and r.multiplier == 2 and r.miss == 0, "Early release preserves streak")
	check(r.notes.size() == 2 and r.notes[1].get("recovery", false), "Early release creates a required tail tap")
	var tail: Dictionary = r.notes[1]
	check(tail.t == 6.0 and tail.end == 6.0 and tail.lane == 0, "Recovery tap uses original tail time and lane")
	scene.key_hit(0, 0, false)
	scene.award_hold_bars(0, hold, 6.0)
	check(r.notes.size() == 2 and r.score == 1200, "Repeated release cannot duplicate tail or earn more sustain points")
	scene.time_s = 6.0
	scene.key_hit(0, 0, true)
	check(tail.state == 2 and r.combo == 26 and r.score == 1200, "Hitting recovery tail preserves streak without extra score/combo")
	scene.key_hit(0, 0, false)
	check(r.judged == 2 and r.miss == 0, "Recovery tail judged exactly once")

	scene.start_game()
	scene.audio.stop()
	r = scene.runs[0]
	r.timing = tempo
	hold = {"t": 0.0, "end": 4.0, "lane": 0, "state": 0, "points": 0}
	r.notes = [hold]
	scene.time_s = 0.0
	scene.key_hit(0, 0, true)
	scene.time_s = 0.5
	scene.key_hit(0, 0, false)
	check(r.combo == 1 and r.miss == 0, "No streak penalty at early release")
	scene.playing = true
	scene.time_s = 4.3
	scene._process(0.0)
	check(r.combo == 0 and r.miss == 1 and r.notes[1].state == 3, "Missing recovery tail later breaks streak")
	scene._process(0.0)
	check(r.miss == 1, "Missed recovery tail cannot penalize twice")
	scene.show_menu()

func check_menu_update(scene) -> void:
	var saved_song: Dictionary = scene.selected
	var saved_songs: Array = scene.songs.duplicate()
	var saved_preferences: Array = scene.preferred_choices.duplicate(true)
	var saved_choices: Array = scene.choices.duplicate(true)
	var original: Dictionary = saved_song.duplicate(true)
	original.id = "menu-fixture-a"
	var other: Dictionary = original.duplicate(true)
	other.id = "menu-fixture-b"
	var unsupported: Dictionary = original.duplicate(true)
	unsupported.id = "menu-fixture-c"
	unsupported.charts = {"Original": {"Custom map": [{"t": 1.0, "end": 1.0, "lane": 0}]}}
	scene.songs = [original, other, unsupported]
	scene.category = "All songs"
	scene.selected = original
	scene.preferred_choices[0] = {"instrument": "Bass", "difficulty": "Expert"}
	scene.show_menu()
	check(scene.ui.find_child("SongCarousel", true, false) != null, "Carousel exists")
	check(scene.ui.find_child("MenuLeaderboard", true, false) != null, "Inline personal bests exist")
	check(scene.ui.find_child("MultiplayerMenu", true, false) is MenuButton, "Multiplayer dropdown exists")
	var categories = scene.ui.find_child("SongCategory", true, false)
	check(categories.item_count == 3, "Three requested song categories")
	scene.move_song(1)
	check(scene.selected.id == other.id and scene.choices[0].instrument == "Bass" and scene.choices[0].difficulty == "Expert", "Song switch preserves part and difficulty")
	var instrument = scene.ui.find_child("Instrument0", true, false)
	instrument.item_selected.emit(0)
	check(scene.choices[0].instrument == "Drums" and scene.choices[0].difficulty == "Expert", "Instrument switch preserves difficulty")
	scene.move_song(1)
	check(scene.choices[0].instrument == "Original" and scene.choices[0].difficulty == "Custom map", "Unavailable choice has valid fallback")
	scene.move_song(1)
	check(scene.selected.id == original.id and scene.choices[0].difficulty == "Expert" and scene.choices[0].instrument == "Drums", "Carousel wraps and restores preferred choices")
	scene.save_settings()
	scene.preferred_choices[0] = {}
	scene.load_settings()
	check(scene.preferred_choices[0].difficulty == "Expert", "Difficulty preference persists across reload")
	scene.process_preview(0.4)
	check(scene.preview.stream != null, "Selected song preview loads")
	scene.show_settings()
	check(not scene.preview.playing and scene.preview.stream == null, "Preview stops in settings")
	check(scene.covers.video_id({"category": "YouTube", "source": "https://www.youtube.com/watch?v=abcdefghijk"}) == "abcdefghijk", "Thumbnail accepts canonical video ID")
	check(scene.covers.video_id({"category": "YouTube", "source": "https://evil.example/watch?v=abcdefghijk"}) == "", "Thumbnail rejects arbitrary origins")
	scene.selected = saved_song
	scene.songs = saved_songs
	scene.preferred_choices = saved_preferences
	scene.choices = saved_choices
	scene.show_menu()

func check_menu_polish(scene) -> void:
	var saved_song: Dictionary = scene.selected
	var saved_songs: Array = scene.songs.duplicate()
	var old_pause: bool = scene.preview_paused
	var old_volume: float = scene.hit_volume
	var old_effects: Dictionary = scene.visual_effects.duplicate()
	scene.songs = []
	for i in range(6):
		var song: Dictionary = saved_song.duplicate(true)
		song.id = "carousel-polish-%d" % i
		song.title = "Search Fixture %d" % i
		song.artist = "Test Artist"
		scene.songs.append(song)
	scene.selected = scene.songs[0]
	scene.show_menu()
	await process_frame
	var carousel = scene.ui.find_child("SongCarousel", true, false)
	var retained_card: Node = null
	for card in carousel.get_children():
		if card.has_meta("song") and card.get_meta("song").id == scene.songs[1].id:
			retained_card = card
	var old_position: Vector2 = retained_card.position
	scene.move_song(1)
	check(scene.ui.find_child("SongCarousel", true, false) == carousel, "Song switch retains carousel and cards")
	check(retained_card.position == old_position, "Existing card starts transition from its current position")
	await process_frame
	var motion = retained_card.get_meta("motion") if retained_card.has_meta("motion") else null
	check(motion is Tween, "Carousel uses a property tween")
	if motion is Tween:
		motion.custom_step(0.5)
	check(int(retained_card.get_meta("offset")) == 0 and retained_card.position != old_position, "Selected card animates to center")
	scene.preview_paused = false
	scene.process_preview(0.4)
	scene.toggle_preview()
	check(scene.preview_paused and scene.preview.stream_paused, "Preview pause suspends audio")
	scene.move_song(1)
	scene.process_preview(1.0)
	check(scene.preview_paused and scene.preview.stream == null, "Pause persists while changing songs")
	scene.song_search = "fixture 4 artist"
	scene.show_menu()
	check(scene.filtered.size() == 1 and scene.selected.title == "Search Fixture 4", "Search combines case-insensitive title and artist terms")
	scene.song_search = "no matching song at all"
	scene.show_menu()
	check(scene.filtered.is_empty() and scene.selected.is_empty(), "Empty search clears selection")
	check(scene.ui.find_child("PlaySong", true, false).disabled, "Play disabled for no matches")
	scene.show_settings()
	for key in ["volume", "music_volume", "preview_volume", "hit_volume", "miss_volume"]:
		check(scene.ui.find_child(key, true, false) is HSlider, "Audio mixer slider: " + key)
	for key in scene.visual_effects:
		check(scene.ui.find_child("Effect_" + key, true, false) is CheckBox, "Effect switch: " + key)
	var volume_slider = scene.ui.find_child("hit_volume", true, false)
	volume_slider.value = 0
	scene.play_feedback(false)
	check(not scene.hit_audio.playing, "Zero hit volume mutes feedback")
	var effect_switch = scene.ui.find_child("Effect_hit_rings", true, false)
	effect_switch.button_pressed = false
	scene.load_settings()
	check(scene.preview_paused and scene.hit_volume == 0 and not scene.visual_effects.hit_rings, "Preview/audio/effects preferences persist")
	check(scene.hit_audio.stream.data.size() > 0 and scene.miss_audio.stream.data.size() > 0, "Hit and miss sounds generated without external files")
	scene.preview_paused = old_pause
	scene.hit_volume = old_volume
	scene.visual_effects = old_effects
	scene.song_search = ""
	scene.songs = saved_songs
	scene.selected = saved_song
	scene.save_settings()
	scene.show_menu()

func run_hype_calibration_checks(scene) -> void:
	var logic = load("res://game/hype.gd")
	var calibration = load("res://game/calibration.gd")
	var fixture: Dictionary = {"hype": {"global": [{"start": 2, "end": 6, "confidence": 0.9, "kind": "drop"}], "instruments": {"Bass": [{"start": 9, "end": 12, "confidence": 0.9, "kind": "solo"}]}}}
	var bass: Array = logic.sections(fixture, "Bass", 0.5)
	check(bass.size() == 2 and logic.sections(fixture, "Drums", 0.5).size() == 1, "Solo hype applies only to its instrument")
	var state: Dictionary = {"hype_sections": bass}
	logic.refresh(state, 2.0)
	check(logic.multiplier(state, true, 2.0) == 2.0, "Hype begins at section boundary")
	state.hype_broken = true
	logic.refresh(state, 4.0)
	check(logic.multiplier(state, true, 2.0) == 1.0, "Broken bonus stays off for rest of section")
	logic.refresh(state, 9.0)
	check(logic.multiplier(state, true, 2.0) == 2.0, "Next section restores eligibility")
	check(logic.multiplier(state, false, 2.0) == 1.0, "Hype scoring can be disabled")
	var samples: Array = []
	for i in range(20):
		samples.append(30.0)
	samples.append(-150.0)
	var stats: Dictionary = calibration.summarize(samples, 10.0)
	check(stats.ready and stats.recommended == 40.0, "Late hits increase offset; median rejects an outlier")
	samples.fill(-25.0)
	check(calibration.summarize(samples, 10.0).recommended == -15.0, "Early hits reduce offset")
	check(not calibration.summarize([10.0], 0.0).ready, "Too few hits cannot auto calibrate")
	# Exercise actual scoring and miss/recovery semantics in a real game run.
	scene.start_game()
	scene.time_s = 3.0
	var run: Dictionary = scene.runs[0]
	run.hype_sections = bass
	run.score = 0
	run.combo = 0
	var n: Dictionary = {"t": 3.0, "end": 3.0, "lane": 0, "state": 0}
	scene.judge(0, n, 300)
	check(run.score == 600, "Perfect hit receives hype points")
	scene.judge(0, {"t": 3.1, "end": 3.1, "lane": 1, "state": 0}, 0)
	scene.judge(0, {"t": 3.2, "end": 3.2, "lane": 2, "state": 0}, 300)
	check(run.score == 900 and run.hype_broken, "A miss removes only the remaining hype bonus")
	run.hype_sections = []
	scene.show_settings()
	for key in ["bonus", "sensitivity", "glow", "rings", "shake"]:
		check(scene.ui.find_child("Hype_" + key, true, false) is HSlider, "Hype setting exists: " + key)
