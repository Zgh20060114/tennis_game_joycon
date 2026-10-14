extends Node3D
## Assembles the playable court scene: environment, court geometry, ball
## view, and the first-person baseline camera (player side, looking at net).

const Court = preload("res://src/core/court_dimensions.gd")
const CourtBuilder = preload("res://src/game/court_builder.gd")
const BallViewScript = preload("res://src/game/ball_view.gd")

var ball_view: Node3D
var camera: Camera3D


func _ready() -> void:
	CourtBuilder.build_environment(self)
	add_child(CourtBuilder.build_court())

	ball_view = BallViewScript.new()
	add_child(ball_view)

	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.6, Court.HALF_LENGTH + 1.1)
	camera.fov = 75.0
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.8, 0.0))
	camera.current = true
