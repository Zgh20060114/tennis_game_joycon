extends SceneTree
## Unit tests for SyntheticSwings (Task 5): determinism, peak speed fidelity,
## and interface contract through the real JoyconDriver pipeline.

const SyntheticSwings = preload("res://src/input/synthetic_swings.gd")
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


## Drive the real driver with a synthetic swing, return peak |head_velocity|.
func _peak_head_speed(samples: Array) -> float:
	var d := JoyconDriver.new(ArraySource.new(samples))
	var peak := 0.0
	for n in samples.size() + 10:
		d.pull()
		peak = maxf(peak, d.head_velocity.length())
	return peak


func _init() -> void:
	test_determinism()
	test_peak_speed_fidelity()
	test_contract()
	print("----------------------------------------")
	print("%d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures > 0 else 0)


func test_determinism() -> void:
	var a := SyntheticSwings.make("forehand", 10.0)
	var b := SyntheticSwings.make("forehand", 10.0)
	var same: bool = a.size() == b.size()
	if same:
		for i in a.size():
			if not (a[i].gyro == b[i].gyro and a[i].accel == b[i].accel and a[i].t_us == b[i].t_us):
				same = false
				break
	check(same and a.size() > 50, "replay of the same swing produces identical sample streams")


func test_peak_speed_fidelity() -> void:
	for kind in ["forehand", "backhand", "serve"]:
		for speed in [5.0, 12.0, 20.0]:
			var peak := _peak_head_speed(SyntheticSwings.make(kind, speed))
			var err: float = absf(peak - speed) / speed
			check(err < 0.05, "%s at %d m/s lands within 5%% (peak=%.3f, err=%.2f%%)" %
					[kind, int(speed), peak, err * 100.0])


func test_contract() -> void:
	for kind in ["forehand", "backhand", "serve"]:
		var samples := SyntheticSwings.make(kind, 12.0)
		var d := JoyconDriver.new(ArraySource.new(samples))
		var finite := true
		var continuous := true
		var last_speed := 0.0
		for n in samples.size() + 10:
			d.pull()
			if not (d.head_velocity.is_finite() and d.quat.is_finite()):
				finite = false
			if absf(d.head_velocity.length() - last_speed) > 4.0:
				continuous = false
			last_speed = d.head_velocity.length()
		check(finite, "%s: pose and velocity stay finite through the real pipeline" % kind)
		check(continuous, "%s: velocity stream is continuous (max jump < 4 m/s per sample)" % kind)
