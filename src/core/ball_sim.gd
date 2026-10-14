## Deterministic ballistic tennis-ball flight. Pure logic: no engine physics
## nodes, no RNG, no wall-clock. Fixed substeps with exact in-substep
## ballistic integration and analytic collision resolution, so identical
## inputs give identical outputs AND no-drag flight matches the closed-form
## solution to float precision. Live flight and the opponent AI's prediction
## both run through this same code path.

const Court = preload("res://src/core/court_dimensions.gd")

const SUBSTEP := 1.0 / 240.0
const MAX_TIME := 12.0
const MAX_BOUNCES := 24
const PATH_EVERY := 4            # record a path sample every N substeps
const REST_VY := 0.3             # impact speed below which the ball settles
const REST_H_SPEED := 0.05       # settled when horizontal speed drops below this

const DEFAULT_PARAMS := {
	"gravity": 9.81,
	"drag": 0.0,                 # quadratic drag coefficient (off by default)
	"restitution": 0.73,
	"friction": 0.70,
	"radius": 0.033,
	"net_enabled": true,
}


## Simulate a shot from (pos, vel) until it settles, exceeds MAX_TIME,
## or exceeds MAX_BOUNCES. Returns:
##   landing: Vector3 of first ground contact (or null)
##   class:   "in" | "out" | "net" | "none"  (shot outcome vs opponent court)
##   side:    which half the ball travels toward (+1 / -1)
##   net_hit: bool
##   events:  [{type, pos, vel_in, vel_out, time}, ...]  land/bounce/net/rest
##   path:    sampled [{p, v, t}, ...]
##   duration: float seconds simulated
static func simulate(pos: Vector3, vel: Vector3, params: Dictionary = {}) -> Dictionary:
	var p: Dictionary = DEFAULT_PARAMS.duplicate()
	for k in params:
		p[k] = params[k]
	var g: float = p.gravity
	var drag: float = p.drag
	var restitution: float = p.restitution
	var friction: float = p.friction
	var radius: float = p.radius
	var net_enabled: bool = p.net_enabled

	var side: int = -1 if vel.z < 0.0 else 1
	var events: Array = []
	var path: Array = []
	var landing: Variant = null
	var net_hit := false
	var first_contact := false
	var bounces := 0
	var t := 0.0
	var max_steps := int(MAX_TIME / SUBSTEP)

	if pos.y <= radius:
		first_contact = true
		landing = Vector3(pos.x, radius, pos.z)
		events.append(_event("land", landing, vel, Vector3.ZERO, 0.0))
		pos = landing

	var step := 0
	while step < max_steps:
		step += 1
		var acc := Vector3(0.0, -g, 0.0)
		if drag > 0.0:
			acc -= vel * vel.length() * drag
		var v0 := vel
		var prev := pos
		vel = v0 + acc * SUBSTEP
		pos += v0 * SUBSTEP + acc * (0.5 * SUBSTEP * SUBSTEP)
		t += SUBSTEP

		# Net plane crossing (z is drag-free per substep so linear interp is exact).
		if net_enabled and not net_hit and signf(prev.z) != signf(pos.z):
			var s: float = prev.z / (prev.z - pos.z)
			var xc: float = lerpf(prev.x, pos.x, s)
			var yc: float = lerpf(prev.y, pos.y, s)
			if absf(xc) <= Court.NET_HALF_SPAN and yc < Court.net_height_at(xc):
				net_hit = true
				var net_pos := Vector3(xc, yc, 0.0)
				var v_in := vel
				vel = Vector3(vel.x * 0.3, vel.y * 0.3, -vel.z * 0.1)
				events.append(_event("net", net_pos, v_in, vel, t))
				continue

		# Ground contact: solve exact crossing time inside the substep.
		if pos.y <= radius:
			var d: float = prev.y - radius
			var vy0: float = v0.y
			var disc: float = vy0 * vy0 + 2.0 * g * d
			var tc: float = SUBSTEP
			if disc >= 0.0:
				tc = clampf((vy0 + sqrt(disc)) / g, 0.0, SUBSTEP)
			var impact := Vector3(prev.x + v0.x * tc, radius, prev.z + v0.z * tc)
			var v_imp: Vector3 = v0 + acc * tc
			pos = impact
			t = t - SUBSTEP + tc

			var just_landed := false
			if not first_contact:
				first_contact = true
				landing = impact
				just_landed = true
			var real_bounce := v_imp.y < -REST_VY
			var vy_out: float = -v_imp.y * restitution if real_bounce else 0.0
			vel = Vector3(v_imp.x * friction, vy_out, v_imp.z * friction)
			if real_bounce:
				bounces += 1
				events.append(_event("land" if just_landed else "bounce", impact, v_imp, vel, t))
				if bounces >= MAX_BOUNCES:
					break
			if vel.y == 0.0 and Vector2(vel.x, vel.z).length() < REST_H_SPEED:
				events.append(_event("rest", impact, Vector3.ZERO, Vector3.ZERO, t))
				break
			continue

		if step % PATH_EVERY == 0:
			path.append({"p": pos, "v": vel, "t": t})

	var out_class := "none"
	if net_hit:
		out_class = "net"
	elif landing != null:
		out_class = "in" if Court.in_singles_court(landing.x, landing.z, side) else "out"
	return {
		"landing": landing,
		"class": out_class,
		"side": side,
		"net_hit": net_hit,
		"events": events,
		"path": path,
		"duration": t,
	}


static func _event(type: String, pos: Vector3, vel_in: Vector3, vel_out: Vector3, time: float) -> Dictionary:
	return {"type": type, "pos": pos, "vel_in": vel_in, "vel_out": vel_out, "time": time}
