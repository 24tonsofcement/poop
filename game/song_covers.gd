extends Node
# Optional YouTube artwork. Fixed HTTPS origin, bounded response, local cache.
signal available(video_id: String)
var http: HTTPRequest
var textures: Dictionary = {}
var attempted: Dictionary = {}
var pending: Array[String] = []
var current: String = ""
var enabled: bool = true

func _ready() -> void:
	http = HTTPRequest.new()
	http.timeout = 6.0
	http.body_size_limit = 1048576
	http.max_redirects = 0
	add_child(http)
	http.request_completed.connect(completed)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://covers"))

func video_id(song: Dictionary) -> String:
	if song.get("category", "") != "YouTube":
		return ""
	var source: String = str(song.get("source", ""))
	var regex = RegEx.new()
	regex.compile("^https://www\\.youtube\\.com/watch\\?v=([A-Za-z0-9_-]{11})$")
	var found = regex.search(source)
	return found.get_string(1) if found != null else ""

func texture_for(song: Dictionary) -> Texture2D:
	var id: String = video_id(song)
	if id.is_empty():
		return null
	if textures.has(id):
		return textures[id]
	var path: String = "user://covers/" + id + ".jpg"
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		if file != null and file.get_length() <= 1048576:
			var image = Image.new()
			if image.load_jpg_from_buffer(file.get_buffer(file.get_length())) == OK:
				remember(id, image)
				return textures[id]
	if enabled and not attempted.has(id):
		attempted[id] = true
		pending.append(id)
		call_deferred("next_request")
	return null

func remember(id: String, image: Image) -> void:
	if textures.size() >= 24:
		textures.erase(textures.keys()[0])
	textures[id] = ImageTexture.create_from_image(image)

func next_request() -> void:
	if not current.is_empty() or pending.is_empty() or not enabled:
		return
	current = pending.pop_front()
	if http.request("https://i.ytimg.com/vi/" + current + "/hqdefault.jpg") != OK:
		current = ""
		call_deferred("next_request")

func completed(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var id: String = current
	current = ""
	if result == HTTPRequest.RESULT_SUCCESS and status == 200 and not id.is_empty():
		var image = Image.new()
		if image.load_jpg_from_buffer(body) == OK and image.get_width() >= 320 and image.get_width() <= 1024 and image.get_height() <= 1024:
			remember(id, image)
			var file = FileAccess.open("user://covers/" + id + ".jpg", FileAccess.WRITE)
			if file != null:
				file.store_buffer(body)
				file.close()
			available.emit(id)
	call_deferred("next_request")
