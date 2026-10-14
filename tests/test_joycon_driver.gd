extends SceneTree
## Unit tests for JoyconDriver (Task 4) with an injected synthetic source.

const JoyconDriver = preload("res://src/input/joycon_driver.gd")

var checks := 0
var failures := 0


func check(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("PASS  ", label)
	else:
		failures += 1
		print("FAIL  ", label)


class FakeSource:
	var samples: Array = []
	var i := 0

	func read_sample() -> Dictionary:
		if i >= samples.size():
			return {}
		var s: Dictionary = samples[i]
		i += 1
		return s


func rotation_stream(duration_s: float, rate_hz: float, omega: Vector3, q0: Quaternion, start_s := 0.0) -> Array:
	var out: Array = []
	for n in int(duration_s * rate_hz):
		var t := start_s + (n + 1) / rate_hz
		var q := q0 * Quaternion(omega.normalized() if omega.length() > 0 else Vector3(1, 0, 0), omega.length() * (t - start_s))
		out.append({
			"t_us": int(t * 1e6),
			"gyro": omega,
			"accel": q.inverse() * Vector3(0, 9.81, 0),
		})
	return out


func _init() -> void:
	test_dropout_continuity()
	test_swing_velocity_magnitude()
	test_mirror_mapping()
	test_discovery_with_fake_sysfs()
	print("----------------------------------------")
	print("%d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures > 0 else 0)


func test_dropout_continuity() -> void:
	var src := FakeSource.new()
	src.samples = rotation_stream(1.0, 120.0, Vector3(2, 0, 0), Quaternion.IDENTITY)
	var gap := []
	for n in 60:
		gap.append({})
	src.samples.append_array(gap)
	src.samples.append_array(rotation_stream(1.0, 120.0, Vector3(2, 0, 0), Quaternion(Vector3(1, 0, 0), 2.0), 2.0))
	var d := JoyconDriver.new(src)
	for n in 120:
		d.pull()
	var quat_before_gap := d.quat
	var v_before_gap: float = d.head_velocity.length()
	for n in 60:
		d.pull()
	var quat_during_gap := d.quat
	var v_during_gap: float = d.head_velocity.length()
	check(quat_during_gap == quat_before_gap, "pose freezes during a sample dropout")
	check(is_finite(v_during_gap) and v_during_gap < v_before_gap,
			"head velocity bleeds off smoothly during dropout")
	check(d.head_velocity.is_finite() and d.omega_world.is_finite(), "no NaN through the dropout")
	for n in 120:
		d.pull()
	check(d.quat != quat_during_gap, "stream resumes updating the pose after the gap")


func test_swing_velocity_magnitude() -> void:
	var src := FakeSource.new()
	# Rotate about Z so omega stays perpendicular to the -Y lever arm.
	src.samples = rotation_stream(1.0, 120.0, Vector3(0, 0, 4.0), Quaternion.IDENTITY)
	var d := JoyconDriver.new(src)
	for n in 120:
		d.pull()
	# Pure rotation about the lever-perpendicular axis: |v| -> omega * lever.
	var expected := 4.0 * 0.55
	var got := d.head_velocity.length()
	check(got > 0.7 * expected and got < 1.4 * expected,
			"constant swing rate yields head speed near omega x lever (%.3f m/s vs %.3f)" % [got, expected])


func test_mirror_mapping() -> void:
	var src_r := FakeSource.new()
	src_r.samples = [{"t_us": 8333, "gyro": Vector3(1, 0, 0), "accel": Vector3(0, 9.81, 0)}]
	var d_r := JoyconDriver.new(src_r)
	d_r.pull()
	var src_m := FakeSource.new()
	src_m.samples = [{"t_us": 8333, "gyro": Vector3(1, 0, 0), "accel": Vector3(0, 9.81, 0)}]
	var d_m := JoyconDriver.new(src_m)
	d_m.mirror_axes = true
	d_m.pull()
	check(signf(d_r.omega_world.x) > 0.0 and signf(d_m.omega_world.x) < 0.0,
			"mirror option flips the X axis sign of the angular velocity")


func test_discovery_with_fake_sysfs() -> void:
	var root := "/tmp/jc_sysfs_test"
	_rmtree(root)
	for cfg in [["input2", "Joy-Con (L)", "2006", "event1"],
			["input5", "Joy-Con (L) (IMU)", "2006", "event3"],
			["input9", "Joy-Con (R) (IMU)", "2007", "event7"],
			["input12", "Pro Controller (IMU)", "2009", "event11"]]:
		var base := root.path_join(cfg[0])
		DirAccess.make_dir_recursive_absolute(base.path_join("id"))
		DirAccess.make_dir_recursive_absolute(base.path_join(cfg[3]))
		FileAccess.open(base.path_join("name"), FileAccess.WRITE).store_string(cfg[1])
		FileAccess.open(base.path_join("id/product"), FileAccess.WRITE).store_string(cfg[2])
		FileAccess.open(base.path_join(cfg[3] + "/name"), FileAccess.WRITE).store_string(cfg[3])
	var left := _discover_in_test(root, "left")
	var right := _discover_in_test(root, "right")
	check(left == "/dev/input/event3", "left Joy-Con IMU matched by name plus product 2006")
	check(right == "/dev/input/event7", "right Joy-Con IMU matched by product 2007")
	_rmtree(root)


func _rmtree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for child: String in DirAccess.get_directories_at(path):
		_rmtree(path.path_join(child))
	for child: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)


func _discover_in_test(root: String, side: String) -> String:
	const Discovery = preload("res://src/input/imu_discovery.gd")
	return Discovery.discover(side, root)
