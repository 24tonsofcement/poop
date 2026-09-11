extends Button
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
	var ink = Color("89a6c7")
	var paper = Color("d6e8f6")
	var hover: bool = (is_hovered() or has_focus()) and not disabled
	var alpha: float = 0.45 if disabled else 1.0
	draw_rect(Rect2(4, 6, size.x - 5, size.y - 7), ink)
	draw_rect(Rect2(0, 1, size.x - 5, size.y - 7), Color("235b88") if hover else Color("1d344e"))
	draw_rect(Rect2(0, 1, size.x - 5, size.y - 7), ink, false, 2)
	var center = Vector2(37, 33)
	draw_circle(center, 27, paper)
	for radius in [20, 23, 25]: draw_arc(center, radius, 0, TAU, 64, Color("6e85a3"), 1, true)
	draw_arc(center, 22, spin, spin + 1.2, 32, ink, 3, true)
	draw_circle(center, 11, Color("ffba4b"))
	draw_circle(center, 4, ink)
	var face = get_theme_default_font()
	draw_string(face, Vector2(75, 34), "PLAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color(paper, alpha))
	draw_string(face, Vector2(76, 50), "START STAGE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(paper, alpha))
	draw_colored_polygon(PackedVector2Array([Vector2(size.x - 22, 23), Vector2(size.x - 22, 38), Vector2(size.x - 12, 30.5)]), Color(paper, alpha))
