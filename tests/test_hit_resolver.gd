extends SceneTree
## Tests for Task 7: hit resolution (threshold, monotonic speed, aim cone,
## cooldown) and handedness anchoring, plus the full integration: recorded
## synthetic swing -> real driver -> hit -> BallSim lands in bounds.

const HitResolver = preload("res://src/game/hit_resolver.gd")
const RacketAnchor = preload("res://src/game/racket_anchor.gd")
const SyntheticSwings = preload("res://src/input/synthetic_swings.gd")
const JoyconDriver = preload("res://src/input/joycon_driver.gd")
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


class ArraySource:
	var samples: Array
	var i := 0

	func _init(p_samples: Array) -> void:
		samples = p_samples

	func read_sample() -> Dictionary:
		if i >= samples.size():
			return {}
		i += 1
		return samples[i - 1]


func _init() -> void:
	test_threshold_and_rejects()
	test_monotonic_speed()
	test_aim_assist_cone()
	test_cooldown()
	test_handedness_anchor()
	call_deferred("_run_integration")


func _run_integration() -> void:
	test_recorded_swing_integration()
	print("----------------------------------------")
	print("%d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures > 0 else 0)


func _hit_params(swing_speed: float) -> Array:
	return [
		Vector3(0.0, 0.05, 0.1),          # ball inside the shell
		Vector3(0, 0, 0),                 # racket head position (origin)
		Vector3(0, 0, swing_speed),       # head velocity toward -Z... +Z magnitude
		Vector3(0, 0.3, -1.0),            # face normal toward the net
		1.0,                              # now
		Vector3(0, 1.0, -10.0),           # aim target
	]


func test_threshold_and_rejects() -> void:
	var r := HitResolver.new()
	var fast: Dictionary = r.try_hit(Vector3(0, 0.05, 0.1), Vector3.ZERO, Vector3(0, 0, 8.0), Vector3(0, 0.3, -1), 1.0, Vector3(0, 1, -10))
	check(not fast.is_empty() and fast.out_vel.z < 0.0, "fast swing on a ball in the shell produces a hit toward the net")
	var slow := HitResolver.new()
	var rejected: Dictionary = slow.try_hit(Vector3(0, 0.05, 0.1), Vector3.ZERO, Vector3(0, 0, 1.0), Vector3(0, 0.3, -1), 1.0, Vector3(0, 1, -10))
	check(rejected.is_empty(), "swing below the speed threshold produces no hit")
	var far := HitResolver.new()
	check(far.try_hit(Vector3(0.5, 0.5, 0.5), Vector3.ZERO, Vector3(0, 0, 8.0), Vector3(0, 0.3, -1), 1.0, Vector3(0, 1, -10)).is_empty(),
			"ball outside the racket shell produces no hit")
	var sweep := HitResolver.new()
	var swept: Dictionary = sweep.try_hit(Vector3(0, 0.2, -0.4), Vector3.ZERO, Vector3(0, 0, 8.0),
			Vector3(0, 0.3, -1), 1.0, Vector3(0, 1, -10), Vector3(0, 0.2, 0.4))
	check(not swept.is_empty(), "fast ball whose swept segment crosses the shell registers a hit")
	var sweep_miss := HitResolver.new()
	check(sweep_miss.try_hit(Vector3(0, 0.2, -0.4), Vector3.ZERO, Vector3(0, 0, 8.0),
			Vector3(0, 0.3, -1), 1.0, Vector3(0, 1, -10), Vector3(0.6, 0.2, 0.4)).is_empty(),
			"swept segment that misses the shell laterally produces no hit")


func test_monotonic_speed() -> void:
	var prev := -1.0
	var monotonic := true
	for speed in [3.0, 6.0, 10.0, 15.0, 25.0]:
		var r := HitResolver.new()
		var hit: Dictionary = r.try_hit(Vector3(0, 0.05, 0.1), Vector3.ZERO, Vector3(0, 0, speed), Vector3(0, 0.3, -1), 1.0, Vector3(0, 1, -10))
		if hit.is_empty() or hit.speed <= prev:
			monotonic = false
		prev = hit.speed if not hit.is_empty() else prev
	check(monotonic, "outgoing speed rises monotonically with swing speed")


func test_aim_assist_cone() -> void:
	var all_in := true
	var face_dir := Vector3(0, 0.3, -1.0).normalized()
	for deg in range(-60, 61, 15):
		var swept := (Quaternion(Vector3.UP, deg_to_rad(deg)) * face_dir).normalized()
		var r := HitResolver.new()
		var hit: Dictionary = r.try_hit(Vector3(0, 0.05, 0.1), Vector3.ZERO, Vector3(0, 0, 9.0), swept, 1.0, Vector3(0, 1, -10))
		var flat := Vector2(hit.out_vel.x, hit.out_vel.z).angle()
		var target_flat := Vector2(0, -10).angle()
		var ang := absf(rad_to_deg(absf(flat - target_flat)))
		if ang > 45.0:
			all_in = false
	check(all_in, "aim assist keeps outgoing direction within a 45 degree cone across a face sweep")


func test_cooldown() -> void:
	var r := HitResolver.new()
	var first: Dictionary = r.try_hit(Vector3(0, 0.05, 0.1), Vector3.ZERO, Vector3(0, 0, 8.0), Vector3(0, 0.3, -1), 1.0, Vector3(0, 1, -10))
	var second: Dictionary = r.try_hit(Vector3(0, 0.05, 0.1), Vector3.ZERO, Vector3(0, 0, 8.0), Vector3(0, 0.3, -1), 1.2, Vector3(0, 1, -10))
	var third: Dictionary = r.try_hit(Vector3(0, 0.05, 0.1), Vector3.ZERO, Vector3(0, 0, 8.0), Vector3(0, 0.3, -1), 1.6, Vector3(0, 1, -10))
	check(not first.is_empty() and second.is_empty(), "second hit inside the cooldown window is rejected")
	check(not third.is_empty(), "hit after the cooldown window is accepted")


func test_handedness_anchor() -> void:
	var cam := Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 12.9))
	var rel := Quaternion(Vector3.UP, 0.4)
	var right: Transform3D = RacketAnchor.anchor_transform("right", cam, rel)
	var left: Transform3D = RacketAnchor.anchor_transform("left", cam, rel)
	check(absf(right.origin.x + left.origin.x) < 1e-6 and absf(right.origin.x) > 0.1,
			"handedness toggle mirrors the racket anchor X offset")
	var yaw_r: float = Basis(right.basis.get_rotation_quaternion()).get_euler(EULER_ORDER_YXZ).y
	var yaw_l: float = Basis(left.basis.get_rotation_quaternion()).get_euler(EULER_ORDER_YXZ).y
	check(absf(yaw_r + yaw_l) < 1e-3, "handedness toggle mirrors the racket swing yaw")
	var mq: Quaternion = RacketAnchor.mirror_quat(Quaternion(Vector3.UP, 0.7))
	check(absf(Basis(mq).get_euler(EULER_ORDER_YXZ).y + 0.7) < 1e-4, "mirror_quat flips yaw about the sagittal plane")


## Full pipeline: recorded synthetic forehand -> real driver -> hit at peak
## swing speed -> BallSim flight that lands in bounds. Deterministic.
func test_recorded_swing_integration() -> void:
	var samples := SyntheticSwings.make("forehand", 12.0)
	var z1 := _recorded_swing_landing(samples)
	check(z1 < -0.5, "recorded fast swing hit lands on the opponent side (z=%.2f)" % z1)
	check(z1 > -Court.HALF_LENGTH - 0.001, "recorded swing hit lands inside the baseline")
	var z2 := _recorded_swing_landing(SyntheticSwings.make("forehand", 12.0))
	check(absf(z2 - z1) < 1e-6, "integration pipeline is deterministic (z1=%.6f z2=%.6f)" % [z1, z2])


## Drive the real driver with the recorded swing, take the hit at the swing's
## peak head speed (two passes so the cooldown can't swallow the plateau),
## fly it through BallSim, return the landing z.
func _recorded_swing_landing(samples: Array) -> float:
	var cam := Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 12.9))
	# Pass 1: find the frame with the maximum head speed.
	var d0 := JoyconDriver.new(ArraySource.new(samples))
	var peak_idx := -1
	var peak_speed := 0.0
	for i in samples.size():
		d0.pull()
		var speed := d0.head_velocity.length()
		if speed > peak_speed:
			peak_speed = speed
			peak_idx = i
	if peak_idx < 0:
		return 99.0
	# Pass 2: replay to the peak frame and resolve the hit there.
	var d := JoyconDriver.new(ArraySource.new(samples))
	var resolver := HitResolver.new()
	for i in peak_idx + 1:
		d.pull()
	var anchor: Transform3D = RacketAnchor.anchor_transform("right", cam, d.quat)
	var head: Vector3 = anchor * Vector3(0, -0.55, 0)
	if head.y < 0.3:
		return 97.0
	var face := -(anchor.basis * Vector3(0, 0, 1)).normalized()
	var hit: Dictionary = resolver.try_hit(head + Vector3(0, 0.05, 0.05), head, d.head_velocity,
			face, peak_idx / 120.0, Vector3(0, 1.0, -6.0))
	if hit.is_empty():
		return 96.0
	var res: Dictionary = BallSim.simulate(head + Vector3(0, 0.05, 0.05), hit.out_vel)
	if res.landing == null:
		return 98.0
	return res.landing.z
