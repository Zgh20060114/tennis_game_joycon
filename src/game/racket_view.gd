extends Node3D
## First-person racket, built from primitives. Local frame: grip origin at
## (0,0,0), racket extends along -Y (matching JoyconDriver lever), strings
## face along -Z (toward the net in the ready pose).

const HEAD_LOCAL := Vector3(0.0, -0.55, 0.0)   # matches JoyconDriver.LEVER_DEFAULT


func _ready() -> void:
	var grip_mat := _material(Color(0.12, 0.12, 0.14))
	var frame_mat := _material(Color(0.85, 0.3, 0.2))
	var string_mat := _material(Color(0.95, 0.95, 0.95, 0.55))
	string_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var grip := _mesh(CylinderMesh.new(), grip_mat, Vector3(0, -0.12, 0))
	(grip.mesh as CylinderMesh).top_radius = 0.018
	(grip.mesh as CylinderMesh).bottom_radius = 0.02
	(grip.mesh as CylinderMesh).height = 0.24
	add_child(grip)

	var shaft := _mesh(CylinderMesh.new(), grip_mat, Vector3(0, -0.36, 0))
	(shaft.mesh as CylinderMesh).top_radius = 0.011
	(shaft.mesh as CylinderMesh).bottom_radius = 0.013
	(shaft.mesh as CylinderMesh).height = 0.26
	add_child(shaft)

	var throat := _mesh(BoxMesh.new(), frame_mat, Vector3(0, -0.47, 0))
	(throat.mesh as BoxMesh).size = Vector3(0.055, 0.1, 0.03)
	add_child(throat)

	var frame := _mesh(TorusMesh.new(), frame_mat, HEAD_LOCAL)
	frame.rotation_degrees.x = 90.0        # torus plane -> XY, face axis -> Z
	frame.scale = Vector3(0.85, 1.0, 1.0)  # elongate the head along the shaft axis
	var torus := frame.mesh as TorusMesh
	torus.inner_radius = 0.145
	torus.outer_radius = 0.175
	add_child(frame)

	var strings := _mesh(CylinderMesh.new(), string_mat, HEAD_LOCAL)
	strings.rotation_degrees.x = 90.0
	(strings.mesh as CylinderMesh).top_radius = 0.16
	(strings.mesh as CylinderMesh).bottom_radius = 0.16
	(strings.mesh as CylinderMesh).height = 0.004
	add_child(strings)


## World position of the contact point (racket head center).
func head_position() -> Vector3:
	return global_transform * HEAD_LOCAL


## World-space face normal (points toward the net in the ready pose).
func face_normal() -> Vector3:
	return -(global_transform.basis * Vector3(0, 0, 1)).normalized()


func _mesh(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi


static func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	return mat
