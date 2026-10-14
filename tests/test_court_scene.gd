extends SceneTree
## Tests for the court scene (Task 6): layout geometry vs dimension constants,
## net profile, marker colors, and the BallSim -> BallView drive path.

const Court = preload("res://src/core/court_dimensions.gd")
const CourtBuilder = preload("res://src/game/court_builder.gd")
const BallSim = preload("res://src/core/ball_sim.gd")
const BallViewScript = preload("res://src/game/ball_view.gd")

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
	test_line_layout()
	test_net_profile()
	test_marker_colors()
	# BallView builds its children in _ready, which fires on the first
	# processed frame — headless script mode needs one deferred run.
	call_deferred("_run_ball_drive")


func _run_ball_drive() -> void:
	test_ball_drive()
	print("----------------------------------------")
	print("%d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures > 0 else 0)


func _find(items: Array, pred: Callable) -> Array:
	var out: Array = []
	for it: Dictionary in items:
		if pred.call(it):
			out.append(it)
	return out


func test_line_layout() -> void:
	var items: Array = CourtBuilder.line_layout()
	check(items.size() == 7, "layout has 7 painted lines")
	var tol := 0.001
	var baselines := _find(items, func(it): return it.size.x > it.size.z and absf(absf(it.center.z) - Court.HALF_LENGTH) < tol)
	var services := _find(items, func(it): return it.size.x > it.size.z and absf(absf(it.center.z) - Court.SERVICE_LINE_FROM_NET) < tol)
	var sidelines := _find(items, func(it): return it.size.z > it.size.x and absf(absf(it.center.x) - Court.SINGLES_HALF_WIDTH) < tol)
	var center_line := _find(items, func(it): return it.size.z > it.size.x and absf(it.center.x) < tol)
	check(baselines.size() == 2, "two baselines at +/- half length within 1 mm")
	check(services.size() == 2, "two service lines at +/- 6.40 m within 1 mm")
	check(sidelines.size() == 2, "two singles sidelines at +/- half width within 1 mm")
	check(center_line.size() == 1 and absf(center_line[0].size.z - 2.0 * Court.SERVICE_LINE_FROM_NET) < tol,
			"center service line spans both service lines within 1 mm")


func test_net_profile() -> void:
	check(absf(Court.net_height_at(0.0) - 0.914) < 0.001, "net tape is 0.914 m at the center within 1 mm")
	check(absf(Court.net_height_at(Court.NET_HALF_SPAN) - 1.07) < 0.001, "net is 1.07 m at the posts within 1 mm")
	check(Court.net_height_at(Court.NET_HALF_SPAN / 2.0) > 0.914 and Court.net_height_at(Court.NET_HALF_SPAN / 2.0) < 1.07,
			"net height sags parabolically between center and posts")


func test_marker_colors() -> void:
	var c_in: Color = BallViewScript.marker_color(true)
	var c_out: Color = BallViewScript.marker_color(false)
	check(c_in.g > 0.8 and c_in.r < 0.5, "in-bounds marker color is green-ish")
	check(c_out.r > 0.8 and c_out.g < 0.5, "out-of-bounds marker color is red-ish")


func test_ball_drive() -> void:
	var bv: Node3D = BallViewScript.new()
	root.add_child(bv)
	await process_frame   # let _ready build the ball, trail, puff, marker
	var res: Dictionary = BallSim.simulate(Vector3(0.5, 1.2, 10.5), Vector3(1.2, 5.5, -14.0))
	check(res.path.size() > 20, "rally path has enough samples to drive the ball view")
	var worst := 0.0
	for s: Dictionary in res.path:
		bv.set_ball_position(s.p)
		worst = maxf(worst, bv.ball.position.distance_to(s.p))
	check(worst < 0.02, "ball node follows simulation state within 2 cm (worst=%.6f m)" % worst)
	check(bv._trail_points.size() <= BallViewScript.TRAIL_MAX, "trail buffer respects its cap")
	check(not bv.marker.visible, "landing marker stays hidden until a landing is shown")
	bv.show_landing(res.landing, res.class == "in")
	check(bv.marker.visible, "landing marker shows on demand")
	root.remove_child(bv)
	bv.free()
