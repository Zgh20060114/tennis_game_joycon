## Test-only synthetic IMU streams for parameterized tennis swings.
## NOTHING in shipping scenes may reference this file: the game is
## motion-input only (no mouse/keyboard path exists by design). This feeds
## the REAL JoyconDriver pipeline in headless tests, so replay shares the
## live hardware's exact contract.

const JOYCON_LEVER := 0.55            # must match JoyconDriver.LEVER_DEFAULT length
const RATE_HZ := 120.0

# Swing = smoothstep-trapezoid angular speed. `world_axis` is the swing's
# rotation axis in WORLD frame (e.g. vertical for a groundstroke); the body-
# frame axis fed to the gyro is derived from the start orientation, which
# keeps omega perpendicular to the lever so |omega x lever| = peak exactly:
#   forehand/backhand: racket horizontal (pointing +Z), vertical sweep
#   serve: racket down, pendulum about the world X axis
const PRESETS := {
	"forehand": {
		"world_axis": Vector3(0, 1, 0),
		"tilt": Quaternion(Vector3(1, 0, 0), -PI / 2.0),
		"rise": 0.22, "plateau": 0.06, "fall": 0.18,
	},
	"backhand": {
		"world_axis": Vector3(0, 1, 0),
		"tilt": Quaternion(Vector3(0, 0, 1), PI) * Quaternion(Vector3(1, 0, 0), -PI / 2.0),
		"rise": 0.20, "plateau": 0.06, "fall": 0.20,
	},
	"serve": {
		"world_axis": Vector3(1, 0, 0),
		"tilt": Quaternion.IDENTITY,
		"rise": 0.30, "plateau": 0.06, "fall": 0.24,
	},
}


## Generate one swing's sensor sample stream: [{t_us, gyro, accel}, ...].
## peak_head_speed is the intended |omega x lever| in m/s. A 2 s static
## hold precedes the swing, mirroring a real player's ready stance (and
## letting the attitude filter converge, as after live calibration).
static func make(kind: String, peak_head_speed: float, rate_hz := RATE_HZ) -> Array:
	var p: Dictionary = PRESETS[kind]
	var peak: float = peak_head_speed / JOYCON_LEVER
	# Gyro measures in the BODY frame: map the world swing axis through the
	# start orientation (perpendicularity with the lever is frame-invariant).
	var axis: Vector3 = (p.tilt.inverse() * p.world_axis).normalized()
	var quat: Quaternion = p.tilt
	var dt := 1.0 / rate_hz
	var out: Array = []
	var t := 0.0
	var settle := 2.0
	var accel: Vector3 = quat.inverse() * Vector3(0, 9.81, 0)
	while t < settle:
		out.append({"t_us": int(t * 1e6), "gyro": Vector3.ZERO, "accel": accel})
		t += dt
	var total: float = settle + p.rise + p.plateau + p.fall + 0.05
	while t < total:
		var omega := axis * _omega_profile(t - settle, p.rise, p.plateau, p.fall, peak)
		var swing_accel: Vector3 = quat.inverse() * Vector3(0, 9.81, 0)
		out.append({
			"t_us": int(t * 1e6),
			"gyro": omega,
			"accel": swing_accel,
		})
		if omega.length() > 1e-9:
			quat = quat * Quaternion(omega.normalized(), omega.length() * dt)
		t += dt
	return out


static func _omega_profile(t: float, rise: float, plateau: float, fall: float, peak: float) -> float:
	if t < 0.0 or t > rise + plateau + fall:
		return 0.0
	if t < rise:
		return peak * _smoothstep(t / rise)
	elif t < rise + plateau:
		return peak
	var u: float = (t - rise - plateau) / fall
	return peak * (1.0 - _smoothstep(u))


static func _smoothstep(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)
