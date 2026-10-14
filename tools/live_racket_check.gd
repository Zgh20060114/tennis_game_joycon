extends SceneTree
## Live hands-on check: real Joy-Con racket tracking + hit resolution against
## a soft ball machine, in a windowed scene.
## Run: scripts/run_godot.sh --script tools/live_racket_check.gd
## Flow: hold still 2 s (calibration) -> machine feeds a soft ball every few
## seconds -> swing to return. Prints a summary at the end.

const Discovery = preload("res://src/input/imu_discovery.gd")
const EvdevImu = preload("res://src/input/evdev_imu.gd")
const JoyconDriver = preload("res://src/input/joycon_driver.gd")
const ShotSolver = preload("res://src/core/shot_solver.gd")
const Court = preload("res://src/core/court_dimensions.gd")

const SIDE := "left"        # 用户默认左手持拍
const RUN_SECONDS := 75.0
const FEED_PERIOD := 4.5


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var path := Discovery.discover(SIDE)
	if path.is_empty():
		print("未找到 %s 手 Joy-Con IMU" % SIDE)
		quit(1)
		return
	var src := EvdevImu.Source.new(path)
	if not src.is_valid():
		print("设备打开失败")
		quit(1)
		return
	var d := JoyconDriver.new(src)
	d.handedness = SIDE

	var scene: Node3D = load("res://scenes/court.tscn").instantiate()
	root.add_child(scene)
	for i in 5:
		await process_frame

	print("请静止握持 Joy-Con 2 秒（校准）……")
	var neutral: Quaternion = d.filter.quat
	d.calibrate(2.0, 120)
	neutral = d.filter.quat
	d.start()
	scene.attach_driver(d, SIDE, neutral)

	var returns := 0
	scene.player_returned.connect(func(hit): returns += 1; print("  好球！回击成功 挥速%.1fm/s (共 %d)" % [hit.speed, returns]))

	var t0 := Time.get_ticks_msec()
	var last_feed := -10.0
	var last_diag := 0.0
	var prev_active := false
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261014
	while (Time.get_ticks_msec() - t0) / 1000.0 < RUN_SECONDS:
		await process_frame
		var now_s := (Time.get_ticks_msec() - t0) / 1000.0
		if not scene.flight.active and prev_active:
			print("t=%4.1fs  球落定（%s）" % [now_s, scene.flight_res.class])
		prev_active = scene.flight.active
		if scene.flight.active and not scene.flight.player_hit:
			var dist: float = scene.ball_view.ball.position.distance_to(scene.racket.head_position())
			var spd: float = d.head_velocity.length()
			if spd > 1.5 and now_s - last_diag > 0.5:
				last_diag = now_s
				print("t=%4.1fs  挥速 %.1f m/s，球距拍心 %.2f m" % [now_s, spd, dist])
		if not scene.flight.active and now_s - last_feed >= FEED_PERIOD:
			last_feed = now_s
			var origin := Vector3(rng.randf_range(-3.0, 3.0), 1.0, -Court.HALF_LENGTH + 0.5)
			var target := Vector3(rng.randf_range(-2.5, 2.5), Court.BALL_RADIUS, rng.randf_range(5.0, 10.0))
			var sol: Dictionary = ShotSolver.solve_shot(origin, target, 13.0)
			if sol.ok:
				scene.start_shot(origin, sol.velocity)
				print("t=%4.1fs  来球！（已回击 %d）" % [now_s, returns])

	print("结束：共回击 %d 球" % returns)
	d.stop()
	quit(0)
