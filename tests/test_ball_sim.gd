extends SceneTree
## Unit tests for BallSim (Task 2). Run headless:
##   scripts/run_godot.sh --headless --script tests/test_ball_sim.gd

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
	test_determinism()
	test_analytical_landing()
	test_no_nan_long_flight()
	test_bounce_model()
	test_net_collision()
	test_court_classification()
	test_zero_velocity()
	print("----------------------------------------")
	print("%d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures > 0 else 0)


func test_determinism() -> void:
	var res_a := BallSim.simulate(Vector3(0.4, 1.2, 10.0), Vector3(-1.5, 5.0, -14.0), {"net_enabled": false})
	var res_b := BallSim.simulate(Vector3(0.4, 1.2, 10.0), Vector3(-1.5, 5.0, -14.0), {"net_enabled": false})
	var same: bool = res_a.path.size() == res_b.path.size() and res_a.events.size() == res_b.events.size()
	if same:
		for i in res_a.path.size():
			var a: Dictionary = res_a.path[i]
			var b: Dictionary = res_b.path[i]
			if not (a.p == b.p and a.v == b.v and a.t == b.t):
				same = false
				break
	check(same, "same initial conditions produce bit-identical trajectories")


func test_analytical_landing() -> void:
	var y0 := 1.0
	var vy := 4.0
	var z0 := 11.885
	var vz := -19.0
	var r := Court.BALL_RADIUS
	var res := BallSim.simulate(Vector3(0, y0, z0), Vector3(0, vy, vz), {"net_enabled": false})
	# Closed form: y(t) = y0 + vy t - g/2 t^2 = r
	var t_land: float = (vy + sqrt(vy * vy + 2.0 * Court.GRAVITY * (y0 - r))) / Court.GRAVITY
	var z_closed: float = z0 + vz * t_land
	check(res.landing != null, "analytical case produces a landing")
	if res.landing != null:
		var dz: float = absf(res.landing.z - z_closed)
		check(dz < 0.01, "no-drag landing within 1 cm of closed form at ~20 m range (dz=%.6f m)" % dz)
		check(absf(res.landing.y - r) < 1e-6, "landing y equals ball radius")
		check(absf(res.landing.x) < 1e-9, "no lateral drift with zero vx")


func _all_finite(res: Dictionary) -> bool:
	for s in res.path:
		if not (s.p.is_finite() and s.v.is_finite()):
			return false
	for e in res.events:
		if not (e.pos.is_finite() and e.vel_in.is_finite() and e.vel_out.is_finite()):
			return false
	return true


func test_no_nan_long_flight() -> void:
	var res := BallSim.simulate(Vector3(0.5, 1.0, 10.0), Vector3(1.2, 7.0, -13.0))
	check(_all_finite(res), "long multi-bounce flight contains no NaN or Infinity")
	# With restitution 0.9 the rally horizon exceeds 10 s and hits MAX_TIME.
	var long_params := {"restitution": 0.9, "net_enabled": false}
	var long_res := BallSim.simulate(Vector3(0.5, 1.0, 10.0), Vector3(1.2, 7.0, -13.0), long_params)
	check(_all_finite(long_res), "extended horizon flight contains no NaN or Infinity")
	check(long_res.duration > 10.0, "simulation runs past 10 s when the ball keeps bouncing")


func test_bounce_model() -> void:
	var params := {"restitution": 0.6, "friction": 0.7, "net_enabled": false}
	var res := BallSim.simulate(Vector3(0, 2.0, 0), Vector3(3.0, -5.0, 0), params)
	check(res.events.size() > 0 and res.events[0].type == "land", "first ground contact emits a land event")
	if res.events.size() > 0:
		var e: Dictionary = res.events[0]
		# Vector3 stores float32 components, so allow one ulp of slack.
		check(absf(e.vel_out.y - (-e.vel_in.y * 0.6)) < 1e-6,
				"bounce vertical velocity equals incoming times restitution")
		check(absf(e.vel_out.x - e.vel_in.x * 0.7) < 1e-6,
				"bounce horizontal velocity equals incoming times friction")
		check(e.vel_in.y < -5.0, "ball gains downward speed during the fall")


func test_net_collision() -> void:
	# Low shot: crosses the net plane at ~0.27 m, below the 0.914 m tape.
	var low := BallSim.simulate(Vector3(0, 0.5, 5.0), Vector3(0, 2.0, -10.0))
	check(low.net_hit, "shot below net height triggers net collision")
	check(low.events.size() > 0 and low.events[0].type == "net", "net collision emits a net event")
	check(low.events.size() > 0 and absf(low.events[0].pos.z) < 1e-9, "net event sits on the net plane")
	check(low.class == "net", "net hit classifies the shot as net")
	# High shot over the same net.
	var high := BallSim.simulate(Vector3(0, 0.5, 5.0), Vector3(0, 6.0, -10.0))
	check(not high.net_hit, "shot above net height does not trigger net collision")
	check(high.class == "in", "clean shot over the net lands in")


func test_court_classification() -> void:
	check(Court.in_singles_court(4.114, -5.0, -1), "point inside singles sideline on far half is in")
	check(not Court.in_singles_court(4.116, -5.0, -1), "point outside singles sideline is out")
	check(Court.in_singles_court(0.0, -11.884, -1), "point inside baseline is in")
	check(not Court.in_singles_court(0.0, -11.886, -1), "point beyond baseline is out")
	check(not Court.in_singles_court(0.0, 5.0, -1), "point on the wrong half is out")
	var wide := BallSim.simulate(Vector3(1.0, 1.0, 11.0), Vector3(4.0, 4.0, -19.0))
	check(wide.class == "out", "shot landing beyond the sideline classifies out")


func test_zero_velocity() -> void:
	var res := BallSim.simulate(Vector3(0, 0.5, 0), Vector3.ZERO)
	check(res.path.size() > 0, "zero velocity input still produces a simulated path")
	check(_all_finite(res), "zero velocity input contains no NaN")
	check(res.duration < 3.0, "zero velocity ball settles and terminates quickly")
	check(res.landing != null, "zero velocity ball reaches the ground")
