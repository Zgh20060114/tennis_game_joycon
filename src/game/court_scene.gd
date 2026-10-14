extends Node3D
## Assembles the playable court scene: environment, court geometry, ball
## view, first-person baseline camera, and (once a driver is attached) the
## motion-controlled racket with live hit resolution.
##
## Ball flight is always playback of a deterministic BallSim result, so the
## opponent AI (Task 9) can predict with the exact same data.

const Court = preload("res://src/core/court_dimensions.gd")
const CourtBuilder = preload("res://src/game/court_builder.gd")
const BallViewScript = preload("res://src/game/ball_view.gd")
const RacketViewScript = preload("res://src/game/racket_view.gd")
const RacketAnchor = preload("res://src/game/racket_anchor.gd")
const HitResolverScript = preload("res://src/game/hit_resolver.gd")
const BallFlightScript = preload("res://src/game/ball_flight.gd")
const BallSim = preload("res://src/core/ball_sim.gd")

signal player_returned(hit: Dictionary)

var ball_view: Node3D
var racket: Node3D
var camera: Camera3D
var resolver: HitResolverScript
var flight: BallFlightScript
var flight_res: Dictionary

var driver = null                  # JoyconDriver once attached
var neutral_quat := Quaternion.IDENTITY
var handedness := "left"           # 用户默认左手持拍
var aim_target := Vector3(0.0, 1.0, -Court.HALF_LENGTH * 0.55)


func _ready() -> void:
	CourtBuilder.build_environment(self)
	add_child(CourtBuilder.build_court())

	ball_view = BallViewScript.new()
	add_child(ball_view)

	racket = RacketViewScript.new()
	racket.visible = false   # hidden until a driver is attached
	add_child(racket)

	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.6, Court.HALF_LENGTH + 1.1)
	camera.fov = 75.0
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.8, 0.0))
	camera.current = true

	resolver = HitResolverScript.new()
	flight = BallFlightScript.new()
	# rest the ball near the player's side until the first shot
	ball_view.set_ball_position(Vector3(0.0, Court.BALL_RADIUS, Court.HALF_LENGTH - 2.0))


## Connect a live (or replay-driven) JoyconDriver and enable the racket.
func attach_driver(p_driver, p_handedness := "left", p_neutral := Quaternion.IDENTITY) -> void:
	driver = p_driver
	handedness = p_handedness
	neutral_quat = p_neutral
	racket.visible = true


## Launch a shot from an arbitrary origin (machine feed, serve, AI return).
func start_shot(from: Vector3, vel: Vector3, is_player_hit := false) -> void:
	flight_res = BallSim.simulate(from, vel)
	flight.start(flight_res, from, is_player_hit)
	_prev_ball_pos = Vector3.INF
	ball_view.hide_landing()


func _process(delta: float) -> void:
	var now_s := Time.get_ticks_msec() / 1000.0
	if driver != null:
		var rel: Quaternion = neutral_quat.inverse() * driver.quat
		racket.global_transform = RacketAnchor.anchor_transform(handedness, camera.global_transform, rel, driver.pos_offset)
		_try_hit(now_s)
	if flight.active:
		_advance_flight(delta)
	_prev_ball_pos = ball_view.ball.position


func _advance_flight(delta: float) -> void:
	var state: Dictionary = flight.update(delta)
	ball_view.set_ball_position(state.pos)
	for ev: Dictionary in state.events:
		if ev.type == "land":
			ball_view.bounce_puff(ev.pos)
			ball_view.show_landing(ev.pos, flight_res.class == "in")
		elif ev.type == "bounce":
			ball_view.bounce_puff(ev.pos)
	if state.finished:
		flight.active = false   # ball settled; the feeder may serve again


var _prev_ball_pos := Vector3.INF


func _try_hit(now_s: float) -> void:
	if not flight.active or flight.player_hit:
		return
	var head: Vector3 = racket.head_position()
	var hit: Dictionary = resolver.try_hit(
			ball_view.ball.position, head, driver.head_velocity,
			racket.face_normal(), now_s, aim_target, _prev_ball_pos)
	if hit.is_empty():
		return
	# Deterministic rest-of-flight from the exact contact state.
	start_shot(ball_view.ball.position, hit.out_vel, true)
	player_returned.emit(hit)
