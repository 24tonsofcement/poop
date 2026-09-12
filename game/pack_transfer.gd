extends Node
signal progress(message: String)
signal downloaded(folder: String)
signal published
signal failed(message: String)

var lobby: Node
var http: HTTPRequest
var busy: bool = false
var mode: String = ""
var folder: String = ""
var files: Array = []
var index: int = 0
var offset: int = 0
var chunk_size: int = 0
var source_folder: String = ""
var metadata_path: String = ""

func _ready() -> void:
	http = HTTPRequest.new()
	http.timeout = 1800.0
	http.max_redirects = 0
	add_child(http)
	http.request_completed.connect(received)

func begin_upload(song: Dictionary) -> void:
	if busy or not lobby.connected():
		return
	busy = true
	mode = "upload"
	source_folder = str(song.folder)
	var meta: Dictionary = song.duplicate(true)
	meta.erase("folder")
	meta.audio = "audio.wav"
	files = [{"name": "song.json"}, {"name": "audio.wav"}]
	if song.get("video", "") == "background.ogv" and FileAccess.file_exists(source_folder.path_join("background.ogv")):
		files.append({"name": "background.ogv"})
	else:
		meta.erase("video")
	if song.get("background_image", "") == "background.png" and FileAccess.file_exists(source_folder.path_join("background.png")):
		files.append({"name": "background.png"})
	else:
		meta.erase("background_image")
	var cache: String = ProjectSettings.globalize_path("user://network-cache")
	DirAccess.make_dir_recursive_absolute(cache)
	metadata_path = cache.path_join("host-song.json")
	var file = FileAccess.open(metadata_path, FileAccess.WRITE)
	if file == null:
		fail("Could not prepare song metadata for sharing.")
		return
	file.store_string(JSON.stringify(meta))
	file.close()
	for item in files:
		var source: String = metadata_path if item.name == "song.json" else source_folder.path_join(item.name)
		var input = FileAccess.open(source, FileAccess.READ)
		if input == null:
			fail("Could not read " + str(item.name))
			return
		item["size"] = input.get_length()
		input.close()
	index = 0
	offset = 0
	upload_next()

func upload_next() -> void:
	if not lobby.connected():
		fail("Lobby disconnected during sharing.")
		return
	http.download_file = ""
	http.body_size_limit = 65536
	if index >= files.size():
		mode = "publish"
		post("publish", {})
		return
	var item: Dictionary = files[index]
	var source: String = metadata_path if item.name == "song.json" else source_folder.path_join(item.name)
	var input = FileAccess.open(source, FileAccess.READ)
	if input == null:
		fail("Could not read shared file.")
		return
	input.seek(offset)
	var chunk: PackedByteArray = input.get_buffer(mini(262144, int(item.size) - offset))
	input.close()
	chunk_size = chunk.size()
	if chunk_size == 0:
		fail("Shared file changed during upload. Retry sharing.")
		return
	progress.emit("Sharing %s · %d%%" % [item.name, int(100.0 * offset / maxi(1, int(item.size)))])
	post("upload", {"file": item.name, "size": item.size, "offset": offset, "data": Marshalls.raw_to_base64(chunk)})

func post(action: String, data: Dictionary) -> void:
	data.merge({"protocol": lobby.PROTOCOL, "room": lobby.room, "token": lobby.token}, true)
	var error: int = http.request(lobby.endpoint + "/api/" + action, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(data))
	if error != OK:
		fail("Could not start the file transfer.")

func begin_download(manifest: Array) -> void:
	if busy or not lobby.connected():
		return
	files = manifest.duplicate(true)
	var names: Array = []
	for item in files:
		if not item is Dictionary or not item.get("name", "") in ["song.json", "audio.wav", "background.ogv", "background.png"] or item.get("name") in names:
			failed.emit("Invalid song download manifest.")
			return
		if int(item.get("size", 0)) <= 0 or int(item.size) > 268435456 or str(item.get("sha256", "")).length() != 64:
			failed.emit("Invalid song download size or checksum.")
			return
		names.append(item.name)
	if not "song.json" in names or not "audio.wav" in names:
		failed.emit("The host has not finished sharing the song.")
		return
	folder = ProjectSettings.globalize_path("user://network-cache/download-%d" % Time.get_ticks_usec())
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		failed.emit("Could not create the song download folder.")
		return
	busy = true
	mode = "download"
	index = 0
	download_next()

func download_next() -> void:
	if not lobby.connected():
		fail("Lobby disconnected during download.")
		return
	if index >= files.size():
		busy = false
		downloaded.emit(folder)
		return
	var item: Dictionary = files[index]
	http.download_file = folder.path_join(item.name)
	http.body_size_limit = int(item.size)
	progress.emit("Downloading host's " + str(item.name) + "…")
	var error: int = http.request(lobby.endpoint + "/file/" + str(item.name), PackedStringArray(["Authorization: Bearer " + lobby.token]))
	if error != OK:
		fail("Could not start song download.")

func received(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not busy:
		return
	if result != HTTPRequest.RESULT_SUCCESS or status != 200:
		var parser = JSON.new()
		var message: String = "File transfer failed. You can retry from the lobby."
		if mode != "download" and parser.parse(body.get_string_from_utf8()) == OK and parser.data is Dictionary:
			message = str(parser.data.get("error", message))
		fail(message)
		return
	if mode == "download":
		var item: Dictionary = files[index]
		var path: String = folder.path_join(item.name)
		if FileAccess.get_sha256(path) != str(item.sha256):
			fail("Downloaded file checksum mismatch. Retry download.")
			return
		index += 1
		download_next()
	elif mode == "publish":
		busy = false
		progress.emit("Song, charts and available video are ready for friends to download.")
		published.emit()
	else:
		offset += chunk_size
		if offset >= int(files[index].size):
			index += 1
			offset = 0
		upload_next()

func cancel() -> void:
	http.cancel_request()
	cleanup_download()
	busy = false
	progress.emit("File transfer cancelled.")

func fail(message: String) -> void:
	cleanup_download()
	busy = false
	failed.emit(message)

func cleanup_download() -> void:
	if mode != "download" or not folder.begins_with(ProjectSettings.globalize_path("user://network-cache/download-")):
		return
	for name in ["song.json", "audio.wav", "background.ogv", "background.png"]:
		var path: String = folder.path_join(name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(folder):
		DirAccess.remove_absolute(folder)
