## Hit resolution: decides when a swing contacts the ball and computes the
## outgoing velocity. Pure logic over world-frame inputs so headless tests
## can drive it with recorded swings.
##
## Model: forgiving shell around the racket head center; outgoing speed from
## swing speed; direction blends the racket face normal with an aim-assist
## vector toward the opponent court; sweet-spot distance scales speed.

const MIN_SWING_SPEED := 2.0     # m/s head speed required to count as a swing
const COOLDOWN_S := 0.4          # reject re-hits inside this window
const SHELL_RADIUS := 0.24       # contact shell around the head center (m)
const AIM_ASSIST := 0.55         # 0 = pure face direction, 1 = pure aim target
const BASE_SPEED := 6.0          # outgoing m/s at threshold swing
const SPEED_GAIN := 1.35         # outgoing m/s per m/s of swing speed
const MAX_SPEED := 30.0
const MIN_UP_COMPONENT := 0.12   # guarantee an arc that can clear the net

var _last_hit_s := -1e9


func reset() -> void:
	_last_hit_s = -1e9


## Attempt a hit. ball_prev_pos enables swept collision: fast balls tunnel
## through a static shell between frames, so distance is measured to the
## segment [prev, pos]. Returns {} when rejected, else
## {out_vel: Vector3, speed: float, quality: float}.
func try_hit(ball_pos: Vector3, racket_head_pos: Vector3, racket_head_vel: Vector3,
		face_dir_world: Vector3, now_s: float, aim_target: Vector3,
		ball_prev_pos := Vector3.INF) -> Dictionary:
	var to_ball := ball_pos - racket_head_pos
	if ball_prev_pos != Vector3.INF:
		var seg := ball_pos - ball_prev_pos
		if seg.length_squared() > 1e-9:
			var t: float = clampf((racket_head_pos - ball_prev_pos).dot(seg) / seg.length_squared(), 0.0, 1.0)
			to_ball = ball_prev_pos + seg * t - racket_head_pos
	if to_ball.length() > SHELL_RADIUS:
		return {}
	var swing_speed := racket_head_vel.length()
	if swing_speed < MIN_SWING_SPEED:
		return {}
	if now_s - _last_hit_s < COOLDOWN_S:
		return {}
	_last_hit_s = now_s

	var quality: float = clampf(1.0 - to_ball.length() / SHELL_RADIUS, 0.0, 1.0)
	var speed: float = clampf(BASE_SPEED + SPEED_GAIN * swing_speed, BASE_SPEED, MAX_SPEED)
	speed *= lerpf(0.85, 1.0, quality)
	var dir := face_dir_world.normalized().lerp((aim_target - racket_head_pos).normalized(), AIM_ASSIST).normalized()
	dir.y = maxf(dir.y, MIN_UP_COMPONENT)
	return {"out_vel": dir.normalized() * speed, "speed": speed, "quality": quality}
