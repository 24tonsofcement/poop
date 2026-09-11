extends Node

signal joined
signal changed
signal round_started(at: float, round_id: int)
signal round_cancelled
signal disconnected(message: String)
signal problem(message: String)

const PROTOCOL = "pulse-online-1"
var endpoint: String = ""
var room: String = ""
var token: String = ""
var state: Dictionary = {}
var report: Dictionary = {}
var http: HTTPRequest
var busy: bool = false
var pending: Array = []
var action: String = ""
var elapsed: float = 0.0
var sent_at: float = 0.0
var clock_offset: float = 0.0
var best_rtt: float = INF
var failures: int = 0
var seen_round: int = 0
var local_server_pid: int = -1
var active_round: bool = false
var leaving: bool = false

func _ready() -> void:
	http = HTTPRequest.new()
	http.timeout = 3.0
	http.body_size_limit = 65536
	http.max_redirects = 0
	add_child(http)
	http.request_completed.connect(received)

func connected() -> bool:
	return not token.is_empty()

func is_host() -> bool:
	return connected() and state.get("self_id", "") == state.get("host_id", "?")

func current_player() -> Dictionary:
	for player in state.get("players", []):
		if player.id == state.get("self_id", ""):
			return player
	return {}

func server_time() -> float:
	return Time.get_ticks_msec() / 1000.0 + clock_offset

func enter(url: String, lobby: String, password: String, player_name: String, fingerprint: String, title: String, create: bool) -> void:
	if busy or connected() or not pending.is_empty():
		problem.emit("Leave the current lobby before joining another.")
		return
	endpoint = url.strip_edges().trim_suffix("/")
	if not endpoint.begins_with("http://") and not endpoint.begins_with("https://"):
		problem.emit("Use a server URL, for example http://192.168.1.20:27440 or https://lobby.example.com.")
		return
	room = lobby.strip_edges()
	best_rtt = INF
	seen_round = 0
	state = {}
	report = {}
	command("create" if create else "join", {"password": password, "name": player_name, "song": fingerprint, "title": title})

func command(kind: String, data: Dictionary = {}) -> void:
	pending.append({"kind": kind, "data": data.duplicate(true)})

func _process(delta: float) -> void:
	elapsed += delta
	if busy:
		return
	if not pending.is_empty():
		var next: Dictionary = pending.pop_front()
		send(next.kind, next.data)
	elif connected() and elapsed >= 0.25:
		send("poll", {"round": seen_round, "report": report})

func send(kind: String, data: Dictionary) -> void:
	data.merge({"protocol": PROTOCOL, "room": room, "token": token}, true)
	action = kind
	elapsed = 0.0
	sent_at = Time.get_ticks_msec() / 1000.0
	busy = true
	var result: int = http.request(endpoint + "/api/" + kind, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(data))
	if result != OK:
		busy = false
		problem.emit("Could not start the lobby request.")

func received(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	if action == "leave":
		clear_connection()
		return
	if leaving:
		return
	var parser = JSON.new()
	if result != HTTPRequest.RESULT_SUCCESS or parser.parse(body.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		failures += 1
		if connected() and failures >= 3:
			clear_connection()
			disconnected.emit("Lost connection to the lobby server.")
		else:
			problem.emit("Server did not respond. Check its address, firewall and connection.")
		return
	var data: Dictionary = parser.data
	if status != 200:
		var message: String = str(data.get("error", "Lobby request failed."))
		if action == "poll":
			clear_connection()
			disconnected.emit(message)
		else:
			problem.emit(message)
		return
	if data.get("protocol", "") != PROTOCOL:
		problem.emit("Lobby server version does not match this game.")
		return
	failures = 0
	var now: float = Time.get_ticks_msec() / 1000.0
	var rtt: float = now - sent_at
	if rtt < best_rtt:
		best_rtt = rtt
		clock_offset = float(data.server_time) - (sent_at + now) / 2.0
	var was_connected: bool = connected()
	token = str(data.token)
	state = data
	if not was_connected:
		joined.emit()
	changed.emit()
	var round_id: int = int(data.get("round", 0))
	var at: float = float(data.get("start_at", 0))
	if at > 0 and round_id > seen_round:
		seen_round = round_id
		active_round = true
		report = {}
		round_started.emit(at, round_id)
	elif at == 0 and active_round:
		active_round = false
		report = {}
		round_cancelled.emit()

func leave() -> void:
	leaving = true
	if connected():
		pending.clear()
		command("leave")
	else:
		http.cancel_request()
		busy = false
		clear_connection()

func clear_connection() -> void:
	leaving = false
	token = ""
	state = {}
	report = {}
	pending.clear()
	active_round = false
	changed.emit()

func launch_local_server() -> bool:
	if local_server_pid > 0 and OS.is_process_running(local_server_pid):
		return true
	var program: String = OS.get_executable_path().get_base_dir().path_join("PulseLobby.exe")
	var args: PackedStringArray = ["--port", "27440"]
	if OS.has_feature("editor"):
		program = OS.get_environment("PULSE_PYTHON")
		if program.is_empty():
			program = "python" if OS.get_name() == "Windows" else "python3"
		args = PackedStringArray([ProjectSettings.globalize_path("res://server/lobby_server.py"), "--port", "27440"])
	elif not FileAccess.file_exists(program):
		problem.emit("PulseLobby.exe is missing. Run the multiplayer updater first.")
		return false
	local_server_pid = OS.create_process(program, args)
	if local_server_pid <= 0:
		problem.emit("Could not launch the lobby server.")
	return local_server_pid > 0

func _exit_tree() -> void:
	if local_server_pid > 0 and OS.is_process_running(local_server_pid):
		OS.kill(local_server_pid)
