extends RefCounted
# Independent six-button + two-laser judgment engine. Seconds are audio-clock time.
const CRITICAL = 0.046
const NEAR = 0.150
var buttons: Array = []
var paths: Array = [[], []]
var ticks: Array = []
var held: Array = [false, false, false, false, false, false]
var positions: Array = [0.5, 0.5]
var motion_at: Array = [-99.0, -99.0]
var motion_direction: Array = [0.0, 0.0]
var combo: int = 0
var best: int = 0
var earned: int = 0
var total: int = 0
var critical: int = 0
var near: int = 0
var misses: int = 0
var gauge: float = 0.0
var message: String = "READY"
var effects: Array = []
var tick_cursor: int = 0
var button_cursor: int = 0
var now: float = -2.0

func setup(chart: Dictionary, timing: Array = []) -> void:
	buttons = chart.get("buttons", []).duplicate(true)
	paths = chart.get("lasers", [[], []]).duplicate(true)
	ticks.clear()
	held = [false, false, false, false, false, false]
	positions = [0.5, 0.5]
	motion_at = [-99.0, -99.0]
	motion_direction = [0.0, 0.0]
	combo = 0; best = 0; earned = 0; critical = 0; near = 0; misses = 0; gauge = 0.0
	tick_cursor = 0; button_cursor = 0; effects.clear(); now = -2.0
	for note in buttons:
		note.state = 0
		var at: float = float(note.t) + tick_step(float(note.t), timing)
		while at < float(note.end) - 0.015:
			ticks.append({"t": at, "lane": int(note.lane), "kind": "hold", "note": note})
			at += tick_step(at, timing)
	for side in range(2):
		for path in paths[side]:
			var points: Array = path.points
			var at: float = float(points[0].t)
			while at <= float(points[-1].t):
				ticks.append({"t": at, "lane": side, "kind": "laser", "path": path})
				at += tick_step(at, timing)
			for i in range(1, points.size()):
				if absf(float(points[i].t) - float(points[i - 1].t)) < 0.001 and absf(float(points[i].x) - float(points[i - 1].x)) > 0.05:
					ticks.append({"t": float(points[i].t), "lane": side, "kind": "slam", "direction": signf(float(points[i].x) - float(points[i - 1].x)), "x": float(points[i].x)})
	ticks.sort_custom(func(a, b): return float(a.t) < float(b.t))
	total = buttons.size() + ticks.size()

func tick_step(at: float, timing: Array) -> float:
	var beat: float = 0.5
	for point in timing:
		if float(point.get("t", 0)) <= at: beat = clampf(float(point.get("beat_length", 0.5)), 0.1, 3.0)
	return beat / (2.0 if beat < 60.0 / 255.0 else 4.0)

func judge(points: int, lane: int, label: String = "") -> void:
	earned += points
	if points == 2: critical += 1
	elif points == 1: near += 1
	else: misses += 1
	if points > 0:
		combo += 1; best = maxi(best, combo)
		gauge = minf(1, gauge + float(points) * 0.7 / maxf(total, 1))
	else:
		combo = 0; gauge = maxf(0, gauge - 0.02)
	message = label if not label.is_empty() else ("CRITICAL" if points == 2 else "NEAR" if points == 1 else "ERROR")
	effects.append({"t": now, "lane": lane, "points": points})

func press(lane: int, down: bool, at: float) -> void:
	if lane < 0 or lane >= 6: return
	var previous: bool = held[lane]
	held[lane] = down
	if not down or previous: return
	now = at
	for index in range(button_cursor, buttons.size()):
		var note: Dictionary = buttons[index]
		if float(note.t) > at + NEAR: break
		if int(note.lane) != lane or int(note.state) != 0: continue
		var error: float = absf(at - float(note.t))
		if error <= NEAR:
			note.state = 1
			judge(2 if error <= CRITICAL else 1, lane)
			return

func turn(side: int, amount: float, at: float) -> void:
	if side < 0 or side > 1 or absf(amount) < 0.00005: return
	positions[side] = clampf(float(positions[side]) + amount, 0, 1)
	motion_at[side] = at
	motion_direction[side] = signf(amount)

func target(path: Dictionary, at: float) -> float:
	var points: Array = path.points
	var value: float = float(points[0].x)
	for i in range(1, points.size()):
		var a: Dictionary = points[i - 1]
		var b: Dictionary = points[i]
		if at >= float(b.t): value = float(b.x); continue
		if at >= float(a.t) and float(b.t) > float(a.t):
			return lerpf(float(a.x), float(b.x), (at - float(a.t)) / (float(b.t) - float(a.t)))
		break
	return value

func track(side: int, path: Dictionary, at: float) -> bool:
	var wanted: float = target(path, at)
	var direction: float = signf(target(path, minf(at + 0.03, float(path.points[-1].t))) - wanted)
	var recent: bool = at - float(motion_at[side]) <= 0.18 and at >= float(motion_at[side]) - 0.15
	# Directional knob assist: a correct turn follows the segment; wrong turns break tracking.
	if recent and (direction == 0 or direction == float(motion_direction[side])):
		positions[side] = wanted
	return absf(float(positions[side]) - wanted) <= 0.08

func advance(at: float) -> void:
	now = at
	for index in range(button_cursor, buttons.size()):
		var note: Dictionary = buttons[index]
		if float(note.t) > at - NEAR: break
		if int(note.state) == 0:
			note.state = 2; judge(0, int(note.lane))
	while button_cursor < buttons.size() and int(buttons[button_cursor].state) != 0: button_cursor += 1
	for side in range(2):
		for path in paths[side]:
			if at >= float(path.points[0].t) and at <= float(path.points[-1].t): track(side, path, at)
	while tick_cursor < ticks.size():
		var tick: Dictionary = ticks[tick_cursor]
		var delay: float = NEAR if tick.kind == "slam" else 0.0
		if float(tick.t) + delay > at: break
		var lane: int = int(tick.lane)
		var success: bool = false
		if tick.kind == "hold": success = held[lane] and int(tick.note.state) == 1
		elif tick.kind == "laser": success = track(lane, tick.path, float(tick.t))
		else:
			success = absf(float(motion_at[lane]) - float(tick.t)) <= NEAR and float(motion_direction[lane]) == float(tick.direction)
			if success: positions[lane] = float(tick.x)
		judge(2 if success else 0, lane + 6 if tick.kind != "hold" else lane, "SLAM" if success and tick.kind == "slam" else "")
		tick_cursor += 1
	while not effects.is_empty() and at - float(effects[0].t) > 0.5: effects.pop_front()

func score() -> int:
	return roundi(10000000.0 * earned / maxf(1, total * 2))

func release_all() -> void:
	held.fill(false)
	motion_at.fill(-99.0)
