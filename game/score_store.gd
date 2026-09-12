extends RefCounted

var path: String = "user://leaderboards.json"
var tables: Dictionary = {}
var warning: String = ""
var writable: bool = true
var recovered_from_backup: bool = false

func load_data() -> void:
	tables = {}
	warning = ""
	writable = true
	recovered_from_backup = false
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"):
		return
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		# Corrupt saves are recoverable: handle parse failure without an engine error.
		var parser = JSON.new()
		if parser.parse(FileAccess.get_file_as_string(candidate)) != OK:
			continue
		var data = parser.data
		if data is Dictionary and data.get("schema") == 1 and data.get("tables") is Dictionary:
			tables = data.tables
			if candidate != path:
				recovered_from_backup = true
				warning = "Leaderboard recovered from backup."
			return
	writable = false
	warning = "Leaderboard save could not be read. Existing files were preserved."

func entries(key: String) -> Array:
	var result: Array = []
	var table = tables.get(key, {})
	if not table is Dictionary or not table.get("entries", []) is Array:
		return result
	for row in table.get("entries", []):
		if row is Dictionary and row.get("name") is String and (row.get("score") is float or row.get("score") is int):
			if float(row.get("score", -1)) >= 0 and is_finite(float(row.get("accuracy", -1))) and float(row.get("accuracy", -1)) >= 0 and float(row.get("accuracy", -1)) <= 100:
				result.append(row.duplicate(true))
	result.sort_custom(better)
	return result

func better(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("score", 0)) != int(b.get("score", 0)):
		return int(a.get("score", 0)) > int(b.get("score", 0))
	if float(a.get("accuracy", 0)) != float(b.get("accuracy", 0)):
		return float(a.get("accuracy", 0)) > float(b.get("accuracy", 0))
	return int(a.get("combo", 0)) > int(b.get("combo", 0))

func best_for(key: String, player_name: String) -> Dictionary:
	for row in entries(key):
		if str(row.name).strip_edges().to_lower() == player_name.strip_edges().to_lower():
			return row
	return {}

func submit(key: String, metadata: Dictionary, record: Dictionary) -> Dictionary:
	if not writable:
		return {"improved": false, "saved": false, "error": warning}
	var old: Dictionary = best_for(key, str(record.name))
	if not old.is_empty() and not better(record, old):
		return {"improved": false, "saved": true, "error": ""}
	var previous: Dictionary = tables.duplicate(true)
	var rows: Array = entries(key)
	for i in range(rows.size() - 1, -1, -1):
		if str(rows[i].name).strip_edges().to_lower() == str(record.name).strip_edges().to_lower():
			rows.remove_at(i)
	rows.append(record.duplicate(true))
	rows.sort_custom(better)
	tables[key] = {"metadata": metadata.duplicate(true), "entries": rows}
	var error: String = save_data()
	if not error.is_empty():
		tables = previous
		return {"improved": false, "saved": false, "error": error}
	return {"improved": true, "saved": true, "error": ""}

func save_data() -> String:
	var temporary: String = path + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Could not save leaderboard; check disk space."
	file.store_string(JSON.stringify({"schema": 1, "tables": tables}))
	file.flush()
	var write_error: int = file.get_error()
	file.close()
	if write_error != OK:
		return "Leaderboard write failed; previous scores were preserved."
	var target: String = ProjectSettings.globalize_path(path)
	var backup: String = target + ".bak"
	var had_previous: bool = FileAccess.file_exists(path)
	if had_previous and recovered_from_backup:
		if DirAccess.remove_absolute(target) != OK:
			return "Could not replace the damaged leaderboard file."
	elif had_previous:
		if FileAccess.file_exists(path + ".bak") and DirAccess.remove_absolute(backup) != OK:
			return "Could not rotate leaderboard backup."
		if DirAccess.rename_absolute(target, backup) != OK:
			return "Could not preserve the previous leaderboard."
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), target) != OK:
		if had_previous:
			DirAccess.rename_absolute(backup, target)
		return "Could not finish saving the leaderboard."
	recovered_from_backup = false
	return ""

# osu!mania-style thresholds, applied to raw judgement accuracy only.
static func grade(accuracy: float) -> String:
	if not is_finite(accuracy):
		return "D"
	if accuracy >= 100.0:
		return "SS"
	if accuracy > 95.0:
		return "S"
	if accuracy > 90.0:
		return "A"
	if accuracy > 80.0:
		return "B"
	if accuracy > 70.0:
		return "C"
	return "D"
