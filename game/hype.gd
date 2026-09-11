extends RefCounted

static func sections(song: Dictionary, instrument: String, sensitivity: float) -> Array:
	var result: Array = []
	var data = song.get("hype", {})
	if not data is Dictionary:
		return result
	var candidates: Array = []
	if data.get("global", []) is Array:
		candidates.append_array(data.get("global", []))
	var parts = data.get("instruments", {})
	if parts is Dictionary and parts.get(instrument, []) is Array:
		candidates.append_array(parts.get(instrument, []))
	for item in candidates:
		if not item is Dictionary:
			continue
		var start: float = float(item.get("start", -1))
		var finish: float = float(item.get("end", -1))
		var confidence: float = float(item.get("confidence", 0))
		if is_finite(start) and is_finite(finish) and is_finite(confidence) and start >= 0 and finish > start and confidence >= 0.85 - 0.4 * sensitivity:
			result.append({"start": start, "end": finish, "kind": str(item.get("kind", "hype"))})
	result.sort_custom(func(a, b): return float(a.start) < float(b.start))
	var merged: Array = []
	for item in result:
		if not merged.is_empty() and float(item.start) <= float(merged[-1].end):
			merged[-1].end = maxf(float(merged[-1].end), float(item.end))
		else:
			merged.append(item.duplicate())
	return merged

static func refresh(run: Dictionary, now: float) -> void:
	var index: int = -1
	var ranges: Array = run.get("hype_sections", [])
	for i in range(ranges.size()):
		if now >= float(ranges[i].start) and now < float(ranges[i].end):
			index = i
			break
	if index != int(run.get("hype_index", -1)):
		run["hype_index"] = index
		run["hype_broken"] = false

static func multiplier(run: Dictionary, enabled: bool, bonus: float) -> float:
	return bonus if enabled and int(run.get("hype_index", -1)) >= 0 and not bool(run.get("hype_broken", false)) else 1.0

static func beat_pulse(now: float, timing: Array) -> float:
	var origin: float = 0.0
	var beat: float = 0.5
	for point in timing:
		if float(point.t) > now:
			break
		origin = float(point.t)
		beat = float(point.beat_length)
	return exp(-fposmod(now - origin, maxf(beat, 0.05)) / 0.10)
