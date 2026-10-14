extends RefCounted
## Real-time playback of a precomputed (deterministic) BallSim result.
## The game never integrates physics live: every shot is a full simulation
## played back, so what the opponent predicted is exactly what happens.

var res: Dictionary
var start_pos: Vector3
var clock := 0.0
var active := false
var player_hit := false      # true once the player intercepts this flight
var _ev_i := 0
var _path_i := 0


func start(p_res: Dictionary, p_start_pos: Vector3, p_player_hit := false) -> void:
	res = p_res
	start_pos = p_start_pos
	player_hit = p_player_hit
	clock = 0.0
	_ev_i = 0
	_path_i = 0
	active = true


## Advance playback. Returns {pos, events, finished}; events are the sim
## events whose time elapsed this frame (land/bounce/net), in order.
func update(dt: float) -> Dictionary:
	if not active:
		return {"pos": start_pos, "events": [], "finished": true}
	clock += dt
	var events: Array = []
	while _ev_i < res.events.size() and res.events[_ev_i].time <= clock:
		events.append(res.events[_ev_i])
		_ev_i += 1
	var finished: bool = clock >= float(res.duration)
	return {"pos": _pos_at(clock), "events": events, "finished": finished}


func _pos_at(t: float) -> Vector3:
	var path: Array = res.path
	if path.is_empty():
		return start_pos
	while _path_i + 1 < path.size() and float(path[_path_i + 1].t) <= t:
		_path_i += 1
	var a: Dictionary = path[_path_i]
	if _path_i == 0 and t <= float(a.t):
		var span: float = maxf(float(a.t), 1e-6)
		return start_pos.lerp(a.p, clampf(t / span, 0.0, 1.0))
	if _path_i + 1 >= path.size():
		return a.p
	var b: Dictionary = path[_path_i + 1]
	var span2: float = maxf(float(b.t) - float(a.t), 1e-6)
	return a.p.lerp(b.p, clampf((t - float(a.t)) / span2, 0.0, 1.0))
