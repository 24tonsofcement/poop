extends SceneTree
var failures: int = 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run_checks")
func until(condition: Callable, description: String, seconds: float = 12.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	var ok: bool = condition.call()
	check(ok, description)
	return ok
func run_checks() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Missing lobby server URL")
		quit(1)
		return
	var host = load("res://game/main.tscn").instantiate()
	var guest = load("res://game/main.tscn").instantiate()
	root.add_child(host)
	root.add_child(guest)
	host.profile_names[0] = "Host"
	guest.profile_names[0] = "Guest"
	var folder: String = ProjectSettings.globalize_path("user://online-host-fixture")
	DirAccess.make_dir_recursive_absolute(folder)
	check(DirAccess.copy_absolute(ProjectSettings.globalize_path("res://game/demo/audio.wav"), folder.path_join("audio.wav")) == OK, "Copy audio fixture")
	check(DirAccess.copy_absolute(ProjectSettings.globalize_path("res://build/video-test/background.ogv"), folder.path_join("background.ogv")) == OK, "Copy video fixture")
	host.selected = host.selected.duplicate(true)
	host.selected.folder = folder
	host.selected.video = "background.ogv"
	host.open_online()
	guest.open_online()
	var room: String = "smoke-%d" % Time.get_ticks_usec()
	host.online.enter(args[0], room, "test-password", "Host", host.online_fingerprint, host.selected.title, true)
	if not await until(func(): return host.online.connected(), "Host creates lobby"):
		quit(1)
		return
	guest.online_fingerprint = "b".repeat(64)
	guest.online.enter(args[0], room, "test-password", "Guest", guest.online_fingerprint, guest.selected.title, false)
	if not await until(func(): return guest.online.connected(), "Guest joins without host song"):
		quit(1)
		return
	check(not guest.online.current_player().get("matched", true), "Guest must download matching pack")
	if not await until(func(): return bool(guest.online.state.get("published", false)), "Host shares audio, charts and video", 25.0):
		quit(1)
		return
	guest.pack_transfer.begin_download(guest.online.state.files)
	if not await until(func(): return bool(guest.online.current_player().get("matched", false)), "Guest verifies and installs host pack", 25.0):
		quit(1)
		return
	check(FileAccess.file_exists(str(guest.selected.folder).path_join("background.ogv")), "Host video downloaded")
	check(guest.online_fingerprint == host.online_fingerprint, "Audio and charts match after transfer")
	check(guest.ui.find_child("OnlineInstrument", true, false) != null, "Downloaded chart instrument choice is available")
	host.online_ready(true)
	guest.online_ready(true)
	if not await until(func(): return host.online.state.players.size() == 2 and host.online.state.players.all(func(p): return p.ready), "Both players ready"):
		quit(1)
		return
	host.online.command("start")
	if not await until(func(): return host.screen == "game" and guest.screen == "game", "Shared round starts"):
		quit(1)
		return
	check(is_equal_approx(host.online_start_at, guest.online_start_at), "Clients agree on scheduled start")
	if not await until(func(): return host.playing and guest.playing, "Both audio transports start", 10.0):
		quit(1)
		return
	check(absf(host.time_s - guest.time_s) < 0.2, "Localhost song clocks start together")
	var n: Dictionary = host.runs[0].notes[0]
	host.time_s = float(n.t)
	host.key_hit(0, int(n.lane), true)
	if not await until(func(): return guest.online.state.players[0].score >= 300, "Live score reaches the other client"):
		quit(1)
		return
	host.online.command("reset")
	await until(func(): return host.screen == "online" and guest.screen == "online", "Host returns everyone to lobby")
	guest.online.leave()
	await until(func(): return not guest.online.connected(), "Guest leaves cleanly")
	host.online.leave()
	await until(func(): return not host.online.connected(), "Host closes lobby")
	host.queue_free()
	guest.queue_free()
	print("Online smoke failures: ", failures)
	quit(1 if failures else 0)
