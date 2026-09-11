extends Button
# Selection ornament is drawn above the song jacket, without competing with
# the carousel's position/scale tweens or intercepting its input.
var motion_source: Control
var ornament: Control
var clock: float = 0.0
func _ready() -> void:
	ornament = Control.new()
	ornament.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ornament.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ornament.z_index = 5
	add_child(ornament)
	ornament.draw.connect(draw_ornament)
func _process(delta: float) -> void:
	if not is_instance_valid(motion_source): return
	clock = 0.0 if motion_source.reduced_motion else clock + delta
	ornament.queue_redraw()
func draw_ornament() -> void:
	var active: bool = int(get_meta("offset", 0)) == 0
	var tint = Color("32f1ff") if active else Color("526b94")
	var w: float = size.x
	var h: float = size.y
	ornament.draw_rect(Rect2(2, 2, w - 4, h - 4), tint, false, 2)
	if not active: return
	for x in [4.0, w - 4]:
		var direction: float = 1 if x < w / 2 else -1
		ornament.draw_line(Vector2(x, 4), Vector2(x + direction * 28, 4), Color.WHITE, 4)
		ornament.draw_line(Vector2(x, h - 4), Vector2(x + direction * 28, h - 4), Color("ff52ba"), 4)
	var scan: float = fposmod(clock * 0.16, 1.0)
	ornament.draw_line(Vector2(5, 6 + scan * maxf(1, h - 70)), Vector2(w - 5, 6 + scan * maxf(1, h - 70)), Color(0.5, 1, 1, 0.12), 2)
	ornament.draw_rect(Rect2(w - 86, 9, 76, 20), Color("29dce9"))
	ornament.draw_string(get_theme_default_font(), Vector2(w - 80, 23), "SELECTED", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("091728"))
