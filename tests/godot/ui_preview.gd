extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://src/main.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1440,900)
	for _i in 8: await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.runtime/previews")
	root.get_texture().get_image().save_png("res://.runtime/previews/desktop.png")
	scene.camera_mode = 3
	for _i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.runtime/previews/top.png")
	scene.tabs.current_tab = 2
	for _i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.runtime/previews/controller.png")
	scene.queue_free()
	await process_frame
	quit()
