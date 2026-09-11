extends RefCounted
# Shared visual language. Layout and game rules belong to main.gd.
const PAPER = Color("10131d")
const INK = Color("e4edf9")
const RED = Color("ff9f35")
const BLUE = Color("65caff")
const GREEN = Color("69dda9")
const OCHRE = Color("ffc857")
const QUIET = Color("9aabc4")
static func font(heading: bool = false) -> SystemFont:
	var face = SystemFont.new()
	face.font_names = PackedStringArray(["Bahnschrift", "Arial", "DejaVu Sans"])
	face.font_weight = 800 if heading else 500
	face.font_italic = heading
	return face
static func panel(fill: Color, accent: Color = INK, shadow: int = 4) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = Color("566a85") if accent == INK else accent
	box.set_border_width_all(1)
	box.border_width_top = 2
	box.corner_radius_top_left = 8
	box.corner_radius_bottom_right = 8
	box.shadow_color = Color(0, 0, 0, 0.65)
	box.shadow_offset = Vector2(shadow, shadow)
	box.shadow_size = 5
	box.set_content_margin_all(12)
	return box
static func make_theme() -> Theme:
	var t = Theme.new()
	t.default_font = font()
	t.default_font_size = 17
	for kind in ["Button", "MenuButton", "OptionButton", "LineEdit", "SpinBox", "ItemList", "CheckButton", "CheckBox"]:
		for state in ["normal", "hover", "pressed", "focus", "disabled", "read_only"]:
			var fill: Color = Color("202a3d")
			if state == "hover": fill = Color("374e69")
			if state == "pressed": fill = Color("14243a")
			if state == "disabled": fill = Color("171e2c")
			var box = panel(fill, BLUE if state == "focus" else INK, 0 if state in ["pressed", "focus"] else 3)
			if state == "focus":
				box.bg_color = Color.TRANSPARENT
				box.set_border_width_all(3)
			t.set_stylebox(state, kind, box)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			t.set_color(state, kind, INK)
		t.set_color("font_disabled_color", kind, QUIET)
		t.set_color("font_placeholder_color", kind, QUIET)
		t.set_color("caret_color", kind, BLUE)
		t.set_color("selection_color", kind, Color("305777"))
		t.set_color("font_selected_color", kind, INK)
		t.set_constant("outline_size", kind, 0)
	t.set_color("font_color", "Label", INK)
	t.set_constant("outline_size", "Label", 0)
	var body = panel(Color("151c2b"), INK, 6)
	body.set_content_margin_all(20)
	t.set_stylebox("panel", "PanelContainer", body)
	t.set_stylebox("panel", "TabContainer", body)
	t.set_stylebox("panel", "PopupMenu", panel(PAPER))
	t.set_stylebox("hover", "PopupMenu", panel(Color("374e69"), Color.TRANSPARENT, 0))
	for state in ["font_color", "font_hover_color", "font_accelerator_color"]:
		t.set_color(state, "PopupMenu", INK)
	for state in ["tab_selected", "tab_unselected", "tab_hovered", "tab_disabled"]:
		var box = panel(Color("304b67") if state == "tab_selected" else Color("374e69") if state == "tab_hovered" else PAPER, INK, 0)
		box.set_content_margin_all(14)
		t.set_stylebox(state, "TabContainer", box)
	t.set_color("font_selected_color", "TabContainer", INK)
	t.set_color("font_unselected_color", "TabContainer", INK)
	t.set_color("font_hovered_color", "TabContainer", INK)
	t.set_font_size("font_size", "TabContainer", 16)
	for kind in ["HSlider", "VSlider", "HScrollBar", "VScrollBar", "ProgressBar"]:
		var rail = panel(Color("080e18"), INK, 0)
		rail.set_content_margin_all(3)
		var fill = panel(BLUE, BLUE, 0)
		for state in ["slider", "background", "scroll"]: t.set_stylebox(state, kind, rail)
		for state in ["fill", "grabber_area", "grabber_area_highlight", "grabber", "grabber_highlight", "grabber_pressed"]: t.set_stylebox(state, kind, fill)
		if kind in ["HSlider", "VSlider"]:
			for icon in ["grabber", "grabber_highlight", "grabber_disabled"]: t.set_icon(icon, kind, preload("res://game/ui/knob.svg"))
	t.set_icon("arrow", "OptionButton", preload("res://game/ui/chevron.svg"))
	for kind in ["CheckButton", "CheckBox"]:
		for suffix in ["", "_disabled"]:
			t.set_icon("checked" + suffix, kind, preload("res://game/ui/toggle_on.svg"))
			t.set_icon("unchecked" + suffix, kind, preload("res://game/ui/toggle_off.svg"))
	return t
