## Complementary (Mahony-style) attitude filter for the Joy-Con IMU.
## Pure logic: consumes gyro (rad/s, body frame) + accel (m/s^2, body frame)
## samples, integrates orientation and gently corrects roll/pitch toward the
## measured gravity direction. Yaw is left to gyro only (corrected by the
## per-point neutral pose recalibration in the game layer).

const GRAVITY := 9.81

var quat := Quaternion.IDENTITY     # body -> world
var gyro_bias := Vector3.ZERO       # rad/s
var kp := 2.5                       # gravity correction gain (1/s)
var max_correction_deg := 30.0      # per-step clamp, guards accel spikes


func reset(initial: Quaternion = Quaternion.IDENTITY) -> void:
	quat = initial


## Average a gyro stream captured while the controller is still.
## reader is any object with read_sample() -> Dictionary (empty dict = end) —
## the same protocol as JoyconDriver sources. We deliberately take the object
## (not a bound-method Callable): Godot Callables reference objects weakly, so
## a temporary's Callable can outlive and lose its instance.
func capture_bias(reader, max_samples := 240) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	while n < max_samples:
		var s: Dictionary = reader.read_sample()
		if s.is_empty():
			break
		sum += s.gyro
		n += 1
	if n == 0:
		return Vector3.ZERO
	return sum / float(n)


func step(gyro: Vector3, accel: Vector3, dt: float) -> void:
	if dt <= 0.0:
		return
	var omega := gyro - gyro_bias

	# Integrate: omega is body-frame, so the delta post-multiplies.
	var rate := omega.length()
	if rate > 1e-9:
		quat = quat * Quaternion(omega / rate, rate * dt)

	# Gravity correction: accel specific force reads +up when still.
	var g := accel.length()
	if g > 0.5 * GRAVITY and g < 2.0 * GRAVITY:
		var up_pred: Vector3 = (quat.inverse() * Vector3.UP).normalized()
		var up_meas: Vector3 = accel / g
		var e: Vector3 = up_meas.cross(up_pred)   # rotate measured toward predicted
		var ang: float = e.length()
		if ang > 1e-9:
			var max_ang: float = deg_to_rad(max_correction_deg)
			var corr: float = minf(ang * kp * dt, max_ang)
			quat = quat * Quaternion(e / ang, corr)
		quat = quat.normalized()
