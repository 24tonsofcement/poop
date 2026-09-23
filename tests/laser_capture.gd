extends SceneTree
func _initialize() -> void:
	call_deferred("capture")
func capture() -> void:
	var game = load("res://game/laser/mode.tscn").instantiate()
	root.add_child(game)
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/laser-menu.png")
	game.start_game()
	game.laser_clock = 3.0
	game.playing = true
	game.audio.play(3.0)
	await create_timer(.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/laser-play.png")
	game.show_menu()
	game.show_controllers()
	await create_timer(.7).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/laser-controller.png")
	game.show_settings()
	await create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/laser-settings.png")
	quit()
