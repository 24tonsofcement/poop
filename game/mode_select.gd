extends Control
var clock: float = 0.0
var opening: bool = false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 22)
	center.add_child(column)
	var title = Label.new()
	title.text = "SELECT YOUR SYSTEM"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	column.add_child(title)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	column.add_child(row)
	mode_card(row, "01   /   FOUR-LANE\n\nARCADE\n\nFour keys · shared keyboard · instruments", Color("75ccff"), "res://game/main.tscn")
	mode_card(row, "02   /   DUAL-LASER\n\nLASER DRIVE\n\nFour BT · two FX · two knobs", Color("fa52b6"), "res://game/laser/mode.tscn")
	var note = Label.new()
	note.text = "Separate song libraries and scores  /  Return with ◀ MODES"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(note)

func mode_card(parent: Node, text: String, tint: Color, scene: String) -> void:
	var card = Button.new()
	card.text = text
	card.custom_minimum_size = Vector2(420, 270)
	card.add_theme_font_size_override("font_size", 21)
	for state in ["normal", "hover", "pressed", "focus"]:
		var style = StyleBoxFlat.new()
		style.bg_color = Color("151b2c") if state == "normal" else tint.darkened(.7)
		style.border_color = tint
		style.set_border_width_all(2 if state == "normal" else 4)
		style.corner_radius_top_left = 24
		style.corner_radius_bottom_right = 24
		card.add_theme_stylebox_override(state, style)
	parent.add_child(card)
	card.resized.connect(func(): card.pivot_offset = card.size / 2)
	card.mouse_entered.connect(func(): create_tween().tween_property(card, "scale", Vector2(1.025, 1.025), .16))
	card.mouse_exited.connect(func(): create_tween().tween_property(card, "scale", Vector2.ONE, .16))
	card.pressed.connect(func():
		if opening: return
		opening = true
		var tween = create_tween()
		tween.tween_property(card, "scale", Vector2(1.08, 1.08), .18)
		tween.parallel().tween_property(self, "modulate:a", 0.0, .25)
		tween.tween_callback(func(): get_tree().change_scene_to_file(scene)))

func _process(delta: float) -> void:
	clock += delta
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("080c17"))
	for i in range(16):
		var x: float = fmod(i * 150.0 + clock * 30, size.x + 400) - 200
		draw_line(Vector2(x, 0), Vector2(x - 300, size.y), Color(.15, .3, .45, .15), 3)
	draw_arc(size / 2, 260 + sin(clock) * 10, clock * .1, clock * .1 + 4.7, 80, Color(.2, .8, 1, .14), 2)
