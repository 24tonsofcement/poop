extends Control
# This scene intentionally has no game-script preloads: mount updates first.
const RELEASE_API = "https://api.github.com/repos/24tonsofcement/poop/releases/tags/android-standalone"
const RUNTIME = "godot-4.4.1-android-3"
var caption: Label
var start_button: Button
var started: bool = false
var pending: bool = false

func _ready() -> void:
	# A new native APK supersedes cached content, never user settings or songs.
	var bundled_version: String = FileAccess.get_file_as_string("res://mobile/VERSION").strip_edges()
	var installed_version: String = FileAccess.get_file_as_string("user://installed-apk-version") if FileAccess.file_exists("user://installed-apk-version") else ""
	if bundled_version != installed_version:
		for cache_name in ["update.pck", "update-old.pck", "update-download.pck", "update-version", "update-trial", "rejected-version"]:
			DirAccess.remove_absolute("user://" + cache_name)
		var installed = FileAccess.open("user://installed-apk-version", FileAccess.WRITE)
		if installed: installed.store_string(bundled_version); installed.close()
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column = VBoxContainer.new()
	center.add_child(column)
	caption = Label.new()
	caption.text = "PULSE / ANDROID\nChecking for updates…"
	caption.add_theme_font_size_override("font_size", 26)
	column.add_child(caption)
	start_button = Button.new()
	start_button.text = "Play now / offline"
	start_button.custom_minimum_size.y = 60
	start_button.pressed.connect(launch)
	column.add_child(start_button)
	# An interrupted trial update is discarded next launch.
	if FileAccess.file_exists("user://update-trial"):
		var rejected = FileAccess.open("user://rejected-version", FileAccess.WRITE)
		if rejected and FileAccess.file_exists("user://update-version"):
			rejected.store_string(FileAccess.get_file_as_string("user://update-version"))
			rejected.close()
		DirAccess.remove_absolute("user://update.pck")
		if FileAccess.file_exists("user://update-old.pck"):
			DirAccess.rename_absolute("user://update-old.pck", "user://update.pck")
		DirAccess.remove_absolute("user://update-version")
		DirAccess.remove_absolute("user://update-trial")
	await check_update()
	if not started: launch()

func fetch(url: String, target: String = "") -> Array:
	var request = HTTPRequest.new()
	request.timeout = 12 if target.is_empty() else 240
	request.download_file = target
	add_child(request)
	if request.request(url, ["Accept: application/vnd.github+json", "User-Agent: PulseFour-Android"]) != OK:
		request.queue_free()
		return []
	var reply: Array = await request.request_completed
	request.queue_free()
	if reply[0] != HTTPRequest.RESULT_SUCCESS or reply[1] != 200: return []
	return reply

func parse(bytes: PackedByteArray) -> Dictionary:
	var parser = JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary: return {}
	return parser.data

func check_update() -> void:
	var response = await fetch(RELEASE_API)
	if started or response.is_empty(): return
	var release = parse(response[3])
	var manifest_url = ""
	for asset in release.get("assets", []):
		if asset.get("name") == "android-update.json": manifest_url = str(asset.get("browser_download_url", ""))
	if not manifest_url.begins_with("https://github.com/24tonsofcement/poop/releases/download/"): return
	response = await fetch(manifest_url)
	if started or response.is_empty(): return
	var manifest = parse(response[3])
	if manifest.get("runtime") != RUNTIME: return
	var version = str(manifest.get("version", ""))
	if FileAccess.file_exists("user://rejected-version") and version == FileAccess.get_file_as_string("user://rejected-version"): return
	if version.is_empty() or version == FileAccess.get_file_as_string("res://mobile/VERSION").strip_edges(): return
	if FileAccess.file_exists("user://update-version") and version == FileAccess.get_file_as_string("user://update-version"): return
	var url = str(manifest.get("url", ""))
	if not url.begins_with("https://github.com/24tonsofcement/poop/releases/download/"): return
	caption.text = "Downloading game update…\nYour songs and scores will stay on this device."
	response = await fetch(url, "user://update-download.pck")
	if started: return
	if response.is_empty() or FileAccess.get_sha256("user://update-download.pck") != str(manifest.get("sha256", "")):
		DirAccess.remove_absolute("user://update-download.pck")
		return
	# Keep only one previous content bundle until the new one has started successfully.
	DirAccess.remove_absolute("user://update-old.pck")
	if FileAccess.file_exists("user://update.pck"):
		DirAccess.rename_absolute("user://update.pck", "user://update-old.pck")
	if DirAccess.rename_absolute("user://update-download.pck", "user://update.pck") != OK: return
	var marker = FileAccess.open("user://update-version", FileAccess.WRITE)
	if marker: marker.store_string(version); marker.close()
	pending = true

func launch() -> void:
	if started: return
	started = true
	start_button.disabled = true
	caption.text = "Starting…"
	if FileAccess.file_exists("user://update.pck"):
		if ProjectSettings.load_resource_pack("user://update.pck", true):
			var trial = FileAccess.open("user://update-trial", FileAccess.WRITE)
			if trial: trial.store_string("trial"); trial.close()
	var packed = load("res://mobile/main.tscn") as PackedScene
	if packed == null:
		caption.text = "Update could not start. Close and reopen to recover."
		return
	var game = packed.instantiate()
	if game == null or game.get_script() == null:
		caption.text = "Update could not start. Close and reopen to recover."
		return
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	# Mark healthy only after the game's ready and several frames complete.
	await get_tree().process_frame
	await get_tree().process_frame
	if str(game.get("screen")) != "menu":
		return
	DirAccess.remove_absolute("user://update-trial")
	DirAccess.remove_absolute("user://update-old.pck")
	queue_free()
