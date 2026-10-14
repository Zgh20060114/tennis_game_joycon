extends SceneTree
## Unit tests for AttitudeFilter (Task 4). Synthetic streams only.

const AttitudeFilter = preload("res://src/input/attitude_filter.gd")

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
	test_bias_removal()
	test_convergence()
	print("----------------------------------------")
	print("%d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures > 0 else 0)


class ArrayReader:
	## Stateful reader over a scripted sample list, with the same
	## read_sample() protocol as JoyconDriver sources.
	var samples: Array
	var i := 0

	func _init(p_samples: Array) -> void:
		samples = p_samples

	func read_sample() -> Dictionary:
		if i >= samples.size():
			return {}
		i += 1
		return samples[i - 1]


func test_bias_removal() -> void:
	var bias := Vector3(0.01, -0.02, 0.005)
	var still := []
	for n in 240:
		still.append({"gyro": bias, "accel": Vector3(0, AttitudeFilter.GRAVITY, 0), "t_us": n * 8333})
	var f := AttitudeFilter.new()
	f.gyro_bias = f.capture_bias(ArrayReader.new(still), 240)
	# Vector3 math is float32, so the 240-sample average carries ~1e-7 slack.
	check((f.gyro_bias - bias).length() < 1e-5, "calibration recovers the injected gyro bias")
	var yaw0: float = Basis(f.quat).get_euler(EULER_ORDER_YXZ).y
	for n in 120 * 60:
		f.step(bias, Vector3(0, AttitudeFilter.GRAVITY, 0), 1.0 / 120.0)
	var yaw60: float = Basis(f.quat).get_euler(EULER_ORDER_YXZ).y
	var drift_deg: float = absf(rad_to_deg(yaw60 - yaw0))
	check(drift_deg < 1.0, "calibrated static stream drifts under 1 degree per minute (%.5f)" % drift_deg)


func test_convergence() -> void:
	var q_true := Quaternion(Vector3(1, 0, 0), deg_to_rad(30.0))
	var accel_body: Vector3 = q_true.inverse() * Vector3(0, AttitudeFilter.GRAVITY, 0)
	var f := AttitudeFilter.new()
	f.reset(Quaternion.IDENTITY)
	for n in int(2.4 * 120):
		f.step(Vector3.ZERO, accel_body, 1.0 / 120.0)
	var err_deg: float = rad_to_deg(f.quat.angle_to(q_true))
	check(err_deg < 2.0, "filter converges to a known orientation within 2 degrees in 2 s (%.3f)" % err_deg)
