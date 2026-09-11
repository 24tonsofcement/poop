extends Button
# Vector CD: legible at every display scale; the reflection rotates on launch.
var spin: float = 0.0:
	set(value):
		spin = value
		queue_redraw()

func _ready() -> void:
	text = ""
	tooltip_text = "Play selected song"
	custom_minimum_size = Vector2(188, 72)
	for state in ["normal", "hover", "pressed", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func _draw() -> void:
	var center: Vector2 = Vector2(43, size.y / 2.0)
	var strength: float = 0.25 if disabled else 1.0
	var hover: bool = (is_hovered() or has_focus()) and not disabled
	draw_circle(center + Vector2(0, 4), 31, Color(0.01, 0.02, 0.07, 0.6 * strength))
	draw_circle(center, 34 if hover else 32, Color(0.3, 0.9, 1.0, (0.18 if hover else 0.07) * strength))
	draw_circle(center, 29, Color(Color("c7d4ed"), strength))
	for i in range(48):
		var angle: float = TAU * i / 48.0 + spin
		var tint: Color = Color.from_hsv(fposmod(float(i) / 48.0 + 0.5, 1.0), 0.35, 1.0, 0.38 * strength)
		draw_arc(center, 23.0, angle, angle + TAU / 48.0, 4, tint, 10, true)
	for radius in [12.0, 18.0, 27.0]:
		draw_arc(center, radius, 0, TAU, 64, Color(1, 1, 1, 0.3 * strength), 1.0, true)
	draw_arc(center, 25, spin - 0.2, spin + 0.55, 24, Color(1, 1, 1, 0.65 * strength), 3.0, true)
	draw_circle(center, 8, Color("101a32"))
	draw_circle(center, 3, Color("5bded9"))
	var font = get_theme_default_font()
	draw_string(font, Vector2(89, size.y / 2.0 + 1), "PLAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color(Color("f1f6ff"), strength))
	draw_string(font, Vector2(89, size.y / 2.0 + 19), "DROP THE NEEDLE", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(Color("85a1c6"), strength))
