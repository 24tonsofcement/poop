extends RefCounted

static func summarize(samples: Array, offset: float) -> Dictionary:
	var clean: Array[float] = []
	for value in samples:
		var number: float = float(value)
		if is_finite(number) and absf(number) <= 160.0:
			clean.append(number)
	clean.sort()
	if clean.size() < 12:
		return {"count": clean.size(), "ready": false}
	var middle: int = clean.size() / 2
	var median: float = clean[middle] if clean.size() % 2 else (clean[middle - 1] + clean[middle]) / 2.0
	var deviations: Array[float] = []
	var early: int = 0
	var late: int = 0
	for value in clean:
		deviations.append(absf(value - median))
		if value < -5:
			early += 1
		elif value > 5:
			late += 1
	deviations.sort()
	var spread: float = deviations[middle]
	return {"count": clean.size(), "ready": spread <= 45.0, "median": median, "spread": spread, "early": early, "late": late, "recommended": clampf(offset + median, -300, 300)}
