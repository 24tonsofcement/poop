extends RefCounted
var config: ConfigFile = ConfigFile.new()
var profile: String = "Keyboard / mouse"
const DEFAULT_KEYS = [KEY_D, KEY_F, KEY_J, KEY_K, KEY_C, KEY_M, KEY_ENTER, KEY_Q, KEY_W, KEY_O, KEY_P, KEY_BACKSPACE]
var keys: Array = DEFAULT_KEYS.duplicate()
var joy_buttons: Array = [0, 1, 2, 3, 4, 5, 8]
var axes: Array = [0, 1]
var inverted: Array = [false, false]
var sensitivity: float = 1.0
var deadzone: float = 0.002
var axis_mode: int = 0 # Wrapping encoder, absolute axis, or spring-centered rate.
var source: int = 0 # Mouse+keys, joystick, keyboard-only.
var device: int = -1
var previous: Dictionary = {}
var rates: Array = [0.0, 0.0]
var feedback: String = "Turn a knob or press a button to test input."
var learning: int = -1
var learning_axis: int = -1
var focused: bool = true

func _init() -> void:
	config.load("user://laser-controller.cfg")
	load_profile(str(config.get_value("selected", "profile", profile)))

func load_profile(name: String) -> void:
	profile = name
	keys = config.get_value(name, "keys", DEFAULT_KEYS.duplicate())
	while keys.size() < DEFAULT_KEYS.size(): keys.append(DEFAULT_KEYS[keys.size()])
	joy_buttons = config.get_value(name, "buttons", [0, 1, 2, 3, 4, 5, 8])
	axes = config.get_value(name, "axes", [0, 1])
	inverted = config.get_value(name, "inverted", [false, false])
	sensitivity = float(config.get_value(name, "sensitivity", 1.0))
	deadzone = float(config.get_value(name, "deadzone", 0.002))
	axis_mode = int(config.get_value(name, "axis_mode", 0))
	source = int(config.get_value(name, "source", 0))
	previous.clear(); rates = [0.0, 0.0]

func save() -> void:
	config.set_value("selected", "profile", profile)
	for item in [["keys", keys], ["buttons", joy_buttons], ["axes", axes], ["inverted", inverted], ["sensitivity", sensitivity], ["deadzone", deadzone], ["axis_mode", axis_mode], ["source", source]]:
		config.set_value(profile, item[0], item[1])
	config.save("user://laser-controller.cfg")

func axis_delta(side: int, value: float) -> float:
	var before: float = float(previous.get(side, value))
	previous[side] = value
	if axis_mode == 2:
		rates[side] = value if absf(value) > maxf(deadzone, 0.05) else 0.0
		return 0.0
	var delta: float = (value - before) / 2.0
	if axis_mode == 0: delta = wrapf(delta + 0.5, 0.0, 1.0) - 0.5
	if absf(delta) < deadzone: return 0.0
	return delta * sensitivity * (-1.0 if inverted[side] else 1.0)

func event_actions(event: InputEvent) -> Array:
	var output: Array = []
	if not focused: return output
	if event is InputEventJoypadMotion or event is InputEventJoypadButton:
		if device >= 0 and event.device != device: return output
	if event is InputEventKey and not event.echo:
		feedback = "KEY " + OS.get_keycode_string(event.physical_keycode)
		if learning >= 0 and event.pressed:
			assign_key(learning, event.physical_keycode); learning = -1; save(); return output
		for lane in [0, 1, 2, 3, 4, 5, 6, 11]:
			if event.physical_keycode == int(keys[lane]): output.append({"button": lane, "down": event.pressed})
	elif event is InputEventJoypadButton:
		feedback = "BUTTON %d · %s" % [event.button_index, "ON" if event.pressed else "OFF"]
		if learning >= 0 and learning < 7 and event.pressed:
			joy_buttons[learning] = event.button_index; learning = -1; save(); return output
		if source == 1:
			for lane in range(7):
				if event.button_index == int(joy_buttons[lane]): output.append({"button": lane, "down": event.pressed})
	elif event is InputEventJoypadMotion:
		feedback = "AXIS %d · %.4f" % [event.axis, event.axis_value]
		if learning_axis >= 0:
			axes[learning_axis] = event.axis; learning_axis = -1; previous.clear(); save(); return output
		if source == 1:
			for side in range(2):
				if event.axis == int(axes[side]): output.append({"knob": side, "delta": axis_delta(side, event.axis_value)})
	elif event is InputEventMouseMotion and source == 0:
		feedback = "MOUSE X %.1f / Y %.1f" % [event.relative.x, event.relative.y]
		for side in range(2):
			var amount: float = event.relative.x if side == 0 else event.relative.y
			output.append({"knob": side, "delta": amount * .004 * sensitivity * (-1.0 if inverted[side] else 1.0)})
	return output

func continuous(delta: float) -> Array:
	if not focused: return [0.0, 0.0]
	var result: Array = [0.0, 0.0]
	var keyboard: Array = [[keys[7], keys[8]], [keys[9], keys[10]]]
	for side in range(2):
		result[side] = (float(Input.is_physical_key_pressed(keyboard[side][1])) - float(Input.is_physical_key_pressed(keyboard[side][0]))) * delta * sensitivity * 1.8
		if source == 1 and axis_mode == 2: result[side] += float(rates[side]) * delta * sensitivity * (-1.0 if inverted[side] else 1.0)
	return result

func assign_key(action: int, code: int) -> void:
	var other: int = keys.find(code)
	if other >= 0 and other != action: keys[other] = keys[action]
	keys[action] = code
	feedback = "Bound " + OS.get_keycode_string(code) + (" (previous binding swapped)" if other >= 0 and other != action else "")

func reset_bindings() -> void:
	keys = DEFAULT_KEYS.duplicate()
	joy_buttons = [0, 1, 2, 3, 4, 5, 8]
	learning = -1; learning_axis = -1
	save()
