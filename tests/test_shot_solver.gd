extends SceneTree
## Unit tests for ShotSolver (Task 3). Run headless:
##   scripts/run_godot.sh --headless --script tests/test_shot_solver.gd

const ShotSolver = preload("res://src/core/shot_solver.gd")
const BallSim = preload("res://src/core/ball_sim.gd")
const Court = preload("res://src/core/court_dimensions.gd")

var checks := 0
var failures := 0


func check(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("PASS  ", label)
	else:
		failures += 1
		print("FAIL  ", label)


func _init() -> void:
	test_grid_solutions()
	test_determinism()
	test_invalid_target()
	test_unreachable_speed()
	print("----------------------------------------")
	print("%d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures > 0 else 0)


func test_grid_solutions() -> void:
	var origin := Vector3(0.0, 1.0, 11.0)
	var total := 0
	var bad := 0
	var worst_landing := 0.0
	var worst_iter := 0
	var worst_clear := INF
	for xi in 12:
		var x: float = -4.0 + 8.0 * xi / 11.0
		for zi in 8:
			var z: float = -1.5 - 10.0 * zi / 7.0
			for speed: float in [16.0, 20.0, 26.0]:
				total += 1
				var target := Vector3(x, Court.BALL_RADIUS, z)
				var r: Dictionary = ShotSolver.solve_shot(origin, target, speed, 0.05)
				if not r.ok:
					bad += 1
					print("  grid fail (%.2f, %.2f) s=%.0f -> %s" % [x, z, speed, r.reason])
					continue
				worst_landing = maxf(worst_landing, r.landing_error)
				worst_iter = maxi(worst_iter, r.iterations)
				worst_clear = minf(worst_clear, r.net_clearance)
	check(total == 288, "grid runs 288 cases (12x8 targets x 3 speed tiers)")
	check(bad == 0, "all valid grid targets produce a solution")
	check(worst_iter <= 100, "convergence within 100 iterations (worst=%d)" % worst_iter)
	check(worst_landing <= 0.05, "verified landings within 5 cm (worst=%.6f m)" % worst_landing)
	check(worst_clear >= 0.05, "net clearance at least the margin (worst=%.3f m)" % worst_clear)
	# Integration: re-fly every 20th solution through the real BallSim (Task 2).
	var refly_ok := true
	var reflies := 0
	for xi in 12:
		var x: float = -4.0 + 8.0 * xi / 11.0
		for zi in 8:
			if (xi + zi) % 5 != 0:
				continue
			reflies += 1
			var target := Vector3(x, Court.BALL_RADIUS, -1.5 - 10.0 * zi / 7.0)
			var r: Dictionary = ShotSolver.solve_shot(origin, target, 20.0, 0.05)
			var res: Dictionary = BallSim.simulate(origin, r.velocity)
			if res.net_hit or res.landing == null or (res.landing - target).length() > 0.05:
				refly_ok = false
	check(reflies >= 10 and refly_ok,
			"solutions re-flown through real BallSim land on target (%d cases)" % reflies)


func test_determinism() -> void:
	var origin := Vector3(0.0, 1.0, 11.0)
	var target := Vector3(1.7, Court.BALL_RADIUS, -7.3)
	var a: Dictionary = ShotSolver.solve_shot(origin, target, 20.0, 0.05)
	var b: Dictionary = ShotSolver.solve_shot(origin, target, 20.0, 0.05)
	check(a.ok and b.ok and a.velocity == b.velocity and a.flight_time == b.flight_time,
			"identical inputs produce identical solutions")


func test_invalid_target() -> void:
	var origin := Vector3(0.0, 1.0, 11.0)
	var r: Dictionary = ShotSolver.solve_shot(origin, Vector3(0.0, Court.BALL_RADIUS, 5.0), 20.0)
	check(not r.ok and r.reason == "invalid_target",
			"target behind the shooter is rejected with invalid_target")
	var r2: Dictionary = ShotSolver.solve_shot(origin, Vector3(0.0, Court.BALL_RADIUS, -5.0), 0.0)
	check(not r2.ok and r2.reason == "invalid_target",
			"non-positive speed is rejected with invalid_target")


func test_unreachable_speed() -> void:
	var origin := Vector3(0.0, 1.0, 11.0)
	var far := Vector3(0.0, Court.BALL_RADIUS, -11.0)
	var r: Dictionary = ShotSolver.solve_shot(origin, far, 5.0)
	check(not r.ok and r.reason == "unreachable_speed",
			"speed too low to reach a far target yields unreachable_speed")
