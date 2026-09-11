extends Button
var motion_source: Control
var ornament: Control
var clock: float = 0.0
func _ready() -> void:
	ornament = Control.new()
	ornament.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ornament.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Each card owns a ten-layer band; this overlay cannot cross into the
	# card ahead of it. Covers and captions stay at their parent's layer.
	ornament.z_index = 1
	add_child(ornament)
	ornament.draw.connect(draw_ornament)
	for state in ["normal", "hover", "pressed", "disabled"]:
		add_theme_stylebox_override(state, preload("res://game/graphic_skin.gd").panel(Color("172439"), Color("89a6c7"), 0))
func _process(delta: float) -> void:
	if not is_instance_valid(motion_source): return
	clock = 0.0 if motion_source.reduced_motion else clock + delta
	ornament.queue_redraw()
func draw_ornament() -> void:
	var active: bool = int(get_meta("offset", 0)) == 0
	var w: float = size.x
	var h: float = size.y
	var ink = Color("89a6c7")
	ornament.draw_rect(Rect2(1, 1, w - 2, h - 2), ink, false, 2)
	ornament.draw_rect(Rect2(5, h - 63, w - 10, 3), ink)
	if not active: return
	# Record-shop catalogue sticker and moving transport marker.
	ornament.draw_rect(Rect2(5, 5, 30, 25), Color("c97726"))
	ornament.draw_string(get_theme_default_font(), Vector2(9, 23), "04", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	ornament.draw_rect(Rect2(w - 85, 8, 77, 21), Color("ffba4b"))
	ornament.draw_string(get_theme_default_font(), Vector2(w - 80, 23), "SELECTED", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("111a26"))
	var cursor: float = (sin(clock * 1.6) + 1.0) * 0.5
	ornament.draw_rect(Rect2(4, h - 5, w - 8, 4), Color("c97726"))
	ornament.draw_rect(Rect2(4 + cursor * maxf(1, w - 40), h - 5, 32, 4), ink)
