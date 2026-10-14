## Programmatic tennis court construction. Layout DATA (line_layout) is
## separated from mesh building so headless tests can verify geometry
## against the dimension constants without a renderer.

const Court = preload("res://src/core/court_dimensions.gd")

const LINE_W := 0.05      # line width (m)
const LINE_H := 0.01      # line thickness (m)
const NET_STEPS := 64     # quad strip resolution along the net


## All painted line boxes as {center: Vector3, size: Vector3}.
static func line_layout() -> Array:
	var hw: float = Court.SINGLES_HALF_WIDTH
	var hl: float = Court.HALF_LENGTH
	var sl: float = Court.SERVICE_LINE_FROM_NET
	var items: Array = []
	for s: float in [-1.0, 1.0]:
		items.append({"center": Vector3(0, LINE_H / 2.0, s * hl), "size": Vector3(2.0 * hw, LINE_H, LINE_W)})
		items.append({"center": Vector3(s * hw, LINE_H / 2.0, 0), "size": Vector3(LINE_W, LINE_H, 2.0 * hl)})
		items.append({"center": Vector3(0, LINE_H / 2.0, s * sl), "size": Vector3(2.0 * hw, LINE_H, LINE_W)})
	items.append({"center": Vector3(0, LINE_H / 2.0, 0), "size": Vector3(LINE_W, LINE_H, 2.0 * sl)})
	return items


## Build surface, lines, net and posts under a new Node3D (caller adds it).
static func build_court() -> Node3D:
	var root := Node3D.new()
	root.name = "Court"
	var hw: float = Court.SINGLES_HALF_WIDTH
	var hl: float = Court.HALF_LENGTH

	_add_plane(root, Vector2(2.0 * hw + 6.0, 2.0 * hl + 4.0), Color(0.16, 0.35, 0.20), -0.002)  # apron
	_add_plane(root, Vector2(2.0 * hw, 2.0 * hl), Color(0.16, 0.32, 0.55), 0.0)                 # inner court

	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.92, 0.92, 0.9)
	for item: Dictionary in line_layout():
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = item.size
		box.material = line_mat
		mi.mesh = box
		mi.position = item.center
		root.add_child(mi)

	root.add_child(_build_net())
	return root


## Net quad strip following the parabolic sag, white tape, two posts.
static func _build_net() -> Node3D:
	var root := Node3D.new()
	root.name = "Net"

	var net_mat := StandardMaterial3D.new()
	net_mat.albedo_color = Color(0.9, 0.9, 0.92, 0.75)
	net_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	net_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in NET_STEPS + 1:
		var x: float = -Court.NET_HALF_SPAN + 2.0 * Court.NET_HALF_SPAN * i / NET_STEPS
		var h: float = Court.net_height_at(x)
		st.add_vertex(Vector3(x, 0.0, 0.0))
		st.add_vertex(Vector3(x, h, 0.0))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = net_mat
	root.add_child(mi)

	var tape := MeshInstance3D.new()
	var tape_box := BoxMesh.new()
	tape_box.size = Vector3(2.0 * Court.NET_HALF_SPAN, 0.05, 0.02)
	tape_box.material = StandardMaterial3D.new()
	tape_box.material.albedo_color = Color(0.95, 0.95, 0.95)
	tape.mesh = tape_box
	tape.position = Vector3(0, Court.NET_CENTER_HEIGHT, 0)   # straight v1 tape at center height
	root.add_child(tape)

	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.1, 0.1, 0.12)
	for s: float in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.height = Court.NET_POST_HEIGHT
		cyl.top_radius = 0.02
		cyl.bottom_radius = 0.02
		cyl.material = post_mat
		post.mesh = cyl
		post.position = Vector3(s * Court.NET_HALF_SPAN, Court.NET_POST_HEIGHT / 2.0, 0)
		root.add_child(post)
	return root


static func build_environment(root: Node) -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.52, 0.85)
	sky_mat.sky_horizon_color = Color(0.71, 0.82, 0.93)
	sky_mat.ground_bottom_color = Color(0.12, 0.18, 0.14)
	sky_mat.ground_horizon_color = Color(0.55, 0.65, 0.60)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	root.add_child(sun)


static func _add_plane(parent: Node3D, size: Vector2, color: Color, y: float) -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	plane.material = mat
	mi.mesh = plane
	mi.position.y = y
	parent.add_child(mi)
