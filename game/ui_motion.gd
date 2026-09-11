extends Node
# One motion vocabulary for all screens. Rebuilds within a screen stay immediate
# so typing, lobby polling and changing a player choice never flash the menu.
var reduced: bool = false
var view_key: String = ""
var outgoing: Control
var outgoing_tween: Tween
var entry_tween: Tween
var launch_tween: Tween
var launching: bool = false
var veil: ColorRect

func disable_tree(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		disable_tree(child)

func swap(previous: Control, current: Control, key: String) -> void:
	var changed: bool = key != view_key
	view_key = key
	if is_instance_valid(outgoing):
		if outgoing_tween != null and outgoing_tween.is_valid():
			outgoing_tween.kill()
		outgoing.queue_free()
		outgoing = null
	if entry_tween != null and entry_tween.is_valid():
		entry_tween.kill()
	if is_instance_valid(previous):
		if changed and not reduced and not launching:
			outgoing = previous
			disable_tree(outgoing)
			outgoing.process_mode = Node.PROCESS_MODE_DISABLED
			outgoing_tween = create_tween().set_parallel(true)
			outgoing_tween.tween_property(outgoing, "modulate:a", 0.0, 0.18)
			outgoing_tween.tween_property(outgoing, "position:y", -12.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			outgoing_tween.chain().tween_callback(outgoing.queue_free)
		else:
			previous.get_parent().remove_child(previous)
			previous.queue_free()
	if changed and not reduced and not launching:
		current.modulate.a = 0.0
		current.position.y = 16.0
		entry_tween = create_tween().set_parallel(true)
		entry_tween.tween_property(current, "modulate:a", 1.0, 0.28).set_delay(0.06)
		entry_tween.tween_property(current, "position:y", 0.0, 0.38).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	bind_tree.call_deferred(current)
	if changed and not reduced and not launching:
		reveal_panels.call_deferred(current)

func bind_tree(node) -> void:
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return
	if node is BaseButton and not node.has_meta("ui_bound"):
		node.set_meta("ui_bound", true)
		node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		# Song cards have an independent layout tween; scale never alters it.
		node.mouse_entered.connect(func(): pop(node, 1.035))
		node.mouse_exited.connect(func(): pop(node, 1.0))
		node.focus_entered.connect(func(): pop(node, 1.035))
		node.focus_exited.connect(func(): pop(node, 1.0))
		node.button_down.connect(func(): pop(node, 0.97))
		node.button_up.connect(func(): pop(node, 1.035 if node.is_hovered() else 1.0))
	for child in node.get_children():
		bind_tree(child)

func pop(button: BaseButton, factor: float) -> void:
	if not is_instance_valid(button) or button.is_queued_for_deletion() or button.disabled or launching:
		return
	if button.has_meta("ui_pop"):
		var old = button.get_meta("ui_pop")
		if old is Tween and old.is_valid():
			old.kill()
	button.pivot_offset = button.size / 2.0
	if reduced:
		button.scale = Vector2.ONE
		return
	var tween = button.create_tween()
	button.set_meta("ui_pop", tween)
	tween.tween_property(button, "scale", Vector2.ONE * factor, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func launch(owner_control: Control, disc: Button, preview: AudioStreamPlayer, action: Callable) -> void:
	if launching:
		return
	launching = true
	veil = ColorRect.new()
	veil.name = "SongTransition"
	veil.color = Color("101516")
	veil.modulate.a = 0.0
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	veil.z_index = 4090
	owner_control.add_child(veil)
	launch_tween = create_tween().set_parallel(true)
	var duration: float = 0.16 if reduced else 0.65
	if is_instance_valid(disc) and disc.has_meta("ui_pop"):
		var pop_tween = disc.get_meta("ui_pop")
		if pop_tween is Tween and pop_tween.is_valid():
			pop_tween.kill()
	if is_instance_valid(disc) and not reduced:
		launch_tween.tween_property(disc, "spin", TAU * 1.5, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		launch_tween.tween_property(disc, "scale", Vector2(1.12, 1.12), duration)
	if is_instance_valid(preview) and preview.playing:
		launch_tween.tween_property(preview, "volume_db", -60.0, duration)
	launch_tween.tween_property(veil, "modulate:a", 1.0, duration * 0.6).set_delay(duration * 0.4)
	launch_tween.chain().tween_callback(action)
	launch_tween.chain().tween_property(veil, "modulate:a", 0.0, 0.18 if reduced else 0.4)
	launch_tween.chain().tween_callback(func():
		if is_instance_valid(veil):
			veil.queue_free()
		launching = false)

func reveal_panels(root) -> void:
	if not is_instance_valid(root) or root.is_queued_for_deletion() or reduced:
		return
	var index: int = 0
	for panel in root.find_children("*", "PanelContainer", true, false):
		panel.modulate.a = 0.0
		var tween = panel.create_tween()
		tween.tween_property(panel, "modulate:a", 1.0, 0.3).set_delay(0.08 + mini(index, 4) * 0.04)
		index += 1
