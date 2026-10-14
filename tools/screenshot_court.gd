extends SceneTree
## Windowed visual acceptance: builds the court scene, places the ball at a
## real mid-flight simulation point, renders ~30 frames, saves a PNG.
## Run: scripts/run_godot.sh --script tools/screenshot_court.gd

const BallSim = preload("res://src/core/ball_sim.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node3D = load("res://scenes/court.tscn").instantiate()
	root.add_child(scene)
	for i in 5:
		await process_frame

	var res: Dictionary = BallSim.simulate(Vector3(0.5, 1.2, 10.5), Vector3(1.2, 5.5, -14.0))
	var mid: Dictionary = res.path[res.path.size() / 8]   # nearer the camera so the ball reads clearly
	scene.ball_view.set_ball_position(mid.p)

	for i in 30:
		await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("/tmp/court.png")
	print("screenshot saved: /tmp/court.png ", img.get_size())
	scene.queue_free()
	quit(0)
