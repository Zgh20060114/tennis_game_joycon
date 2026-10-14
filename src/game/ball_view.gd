extends Node3D
## Tennis ball visualization: slightly oversized ball mesh (visual only),
## motion trail, one-shot bounce puff, and in/out landing markers.

const TRAIL_MAX := 24

var ball: MeshInstance3D
var trail_node: MeshInstance3D
var trail_mesh: ImmediateMesh
var puff: CPUParticles3D
var marker: MeshInstance3D

var _trail_points := PackedVector3Array()


static func marker_color(in_bounds: bool) -> Color:
	return Color(0.2, 1.0, 0.3) if in_bounds else Color(1.0, 0.25, 0.2)


func _ready() -> void:
	ball = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.08        # visual radius, oversized vs the 3.3 cm ball
	sphere.height = 0.16
	sphere.material = _flat_material(Color(0.95, 0.88, 0.25))
	ball.mesh = sphere
	add_child(ball)

	trail_mesh = ImmediateMesh.new()
	trail_node = MeshInstance3D.new()
	trail_node.mesh = trail_mesh
	trail_node.material_override = _flat_material(Color(0.95, 0.88, 0.25, 0.45), true)
	add_child(trail_node)

	puff = CPUParticles3D.new()
	puff.emitting = false
	puff.one_shot = true
	puff.amount = 10
	puff.lifetime = 0.35
	puff.explosiveness = 1.0
	puff.direction = Vector3(0, 1, 0)
	puff.spread = 70.0
	puff.initial_velocity_min = 0.5
	puff.initial_velocity_max = 1.2
	puff.gravity = Vector3(0, -4, 0)
	puff.scale_amount_min = 0.3
	puff.scale_amount_max = 0.8
	var puff_sphere := SphereMesh.new()
	puff_sphere.radius = 0.02
	puff_sphere.height = 0.04
	puff_sphere.material = _flat_material(Color(1, 1, 1, 0.7), true)
	puff.mesh = puff_sphere
	add_child(puff)

	marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.16
	ring.outer_radius = 0.21
	ring.material = _flat_material(Color(0.2, 1.0, 0.3))
	marker.mesh = ring
	marker.visible = false
	add_child(marker)


func set_ball_position(p: Vector3) -> void:
	ball.position = p
	_trail_points.append(p)
	while _trail_points.size() > TRAIL_MAX:
		_trail_points.remove_at(0)
	_rebuild_trail()


func bounce_puff(at: Vector3) -> void:
	puff.global_position = at
	puff.restart()


func show_landing(at: Vector3, in_bounds: bool) -> void:
	marker.position = at + Vector3(0, 0.03, 0)
	(marker.mesh as TorusMesh).material.albedo_color = marker_color(in_bounds)
	marker.visible = true


func hide_landing() -> void:
	marker.visible = false


func _rebuild_trail() -> void:
	trail_mesh.clear_surfaces()
	if _trail_points.size() < 2:
		return
	trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p: Vector3 in _trail_points:
		trail_mesh.surface_add_vertex(p)
	trail_mesh.surface_end()


static func _flat_material(color: Color, transparent := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if transparent:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat
