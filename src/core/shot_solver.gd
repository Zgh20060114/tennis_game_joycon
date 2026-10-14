## Solves an initial velocity that lands the ball on a requested target point
## behind the net while clearing the net tape, at approximately a requested
## speed. Vacuum ballistics closed form for the search, then verified through
## BallSim so solver output and live flight agree by construction.
## This is what the omniscient opponent uses to aim its returns.

const Court = preload("res://src/core/court_dimensions.gd")
const BallSim = preload("res://src/core/ball_sim.gd")

const BISECT_STEPS := 40           # bisection iterations for the flight-time root
const SCAN_FACTORS := [1.2, 1.5, 2.0, 3.0, 4.5, 6.5, 9.0]  # T scan = d/speed * factor
const LANDING_TOL := 0.05          # metres; verified landing must sit this close

## Returns {ok, reason, velocity, speed, flight_time, net_clearance,
##          landing_error, iterations}. reason is "" on success, else one of
## "invalid_target" (target not on the far side of the net from origin),
## "unreachable_speed" (speed cannot cover the distance),
## "no_clearance" (even the highest arc clips the net).
static func solve_shot(origin: Vector3, target: Vector3, speed: float,
		net_margin := 0.05, params: Dictionary = {}) -> Dictionary:
	var radius: float = params.get("radius", Court.BALL_RADIUS)
	var g: float = params.get("gravity", Court.GRAVITY)
	if params.get("drag", 0.0) != 0.0:
		return _fail("drag_unsupported", 0)
	if speed <= 0.0 or signf(origin.z) == 0.0 or signf(target.z) == 0.0 \
			or signf(origin.z) == signf(target.z):
		return _fail("invalid_target", 0)

	var flat := Vector3(target.x - origin.x, 0.0, target.z - origin.z)
	var d := flat.length()
	var dy := target.y - origin.y
	var flat_dir := flat / d
	var iterations := 0

	# speed^2(T) = (dy/T + g T/2)^2 + (d/T)^2 must equal speed^2.
	# Scan for a bracket, then bisect the high-arc (large T) root.
	var t_lo := -1.0
	var t_prev := -1.0
	var f_prev := 0.0
	for factor: float in SCAN_FACTORS:
		var t := d / speed * factor
		var f := _speed_err(t, d, dy, g, speed)
		iterations += 1
		if f < 0.0:
			t_lo = t
		elif t_lo > 0.0:
			t_prev = t
			f_prev = f
			break
	if t_lo < 0.0:
		return _fail("unreachable_speed", iterations)
	var t_hi: float = t_prev if t_prev > 0.0 else t_lo * 3.0
	if _speed_err(t_hi, d, dy, g, speed) < 0.0:
		# Grow the bracket until the high branch crosses zero.
		for i in 20:
			t_hi *= 1.6
			iterations += 1
			if _speed_err(t_hi, d, dy, g, speed) >= 0.0:
				break
		if _speed_err(t_hi, d, dy, g, speed) < 0.0:
			return _fail("unreachable_speed", iterations)

	var t_root := -1.0
	for i in BISECT_STEPS:
		iterations += 1
		var t_mid := 0.5 * (t_lo + t_hi)
		if _speed_err(t_mid, d, dy, g, speed) < 0.0:
			t_lo = t_mid
		else:
			t_hi = t_mid
	t_root = 0.5 * (t_lo + t_hi)

	var vy: float = dy / t_root + 0.5 * g * t_root
	var vh: float = d / t_root
	var velocity := flat_dir * vh + Vector3(0.0, vy, 0.0)

	# Analytic net clearance of this trajectory.
	var net_y: float = Court.net_height_at(origin.x + velocity.x * (-origin.z / velocity.z))
	var crossing_y: float = origin.y + velocity.y * (-origin.z / velocity.z) \
			- 0.5 * g * (-origin.z / velocity.z) * (-origin.z / velocity.z)
	var clearance: float = crossing_y - net_y
	if clearance < net_margin:
		return _fail("no_clearance", iterations)

	# Verify through the real simulator (the same one the game flies with).
	var res := BallSim.simulate(origin, velocity, params)
	if res.net_hit or res.landing == null:
		return _fail("no_clearance", iterations)
	var landing_error: float = (res.landing - target).length()
	if landing_error > LANDING_TOL:
		return _fail("landing_miss", iterations)

	return {
		"ok": true, "reason": "", "velocity": velocity, "speed": velocity.length(),
		"flight_time": t_root, "net_clearance": clearance,
		"landing_error": landing_error, "iterations": iterations,
	}


static func _speed_err(t: float, d: float, dy: float, g: float, speed: float) -> float:
	var vy := dy / t + 0.5 * g * t
	var vh := d / t
	return vy * vy + vh * vh - speed * speed


static func _fail(reason: String, iterations: int) -> Dictionary:
	return {"ok": false, "reason": reason, "velocity": Vector3.ZERO, "speed": 0.0,
			"flight_time": 0.0, "net_clearance": -1.0, "landing_error": -1.0,
			"iterations": iterations}
