class_name MARCArena
extends Node3D

signal obstacle_fallen(id: String)
var course := MARCCourse.new()
var props: Dictionary = {}
var homes: Dictionary = {}
var fallen: Dictionary = {}
var card_meshes: Dictionary = {}
var card_colors: Dictionary = {}
var report_label: Label3D
var program_group := true

func _ready() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("111d30")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("dce9ff")
	settings.ambient_light_energy = 0.7
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-65, -25, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)
	_build_floor()
	_build_pad()
	for ring in course.data.rings:
		_build_ring(ring)
	_build_pole()
	_build_bridge()
	for card in course.cards(true):
		var mesh := box(Vector3(0.4, 0.003, 0.4), Color.WHITE)
		mesh.position = MARCCourse.world(card.x, card.y, 0.25)
		add_child(mesh)
		card_meshes[card.id] = mesh
		var card_label := label(String(card.id), mesh.position + Vector3(0, 0.008, 0), 0.003, true)
		if card.id == "5": report_label = card_label
	set_group(true)

func _build_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	add_child(floor_body)
	var width := float(course.data.width_cm) / 100.0
	var depth := float(course.data.depth_cm) / 100.0
	var cell := float(course.data.cell_cm) / 100.0
	var columns := int(course.data.width_cm / course.data.cell_cm)
	var rows := int(course.data.depth_cm / course.data.cell_cm)
	shape_box(floor_body, Vector3(width + 2, 0.1, depth + 2), Vector3(width/2, -0.05, -depth/2))
	var mesh := box(Vector3(width, 0.04, depth), Color("f0f2f4"))
	mesh.position = Vector3(width/2, -0.02, -depth/2)
	add_child(mesh)
	for column in columns + 1:
		var line := box(Vector3(0.01, 0.003, depth), Color("172131"))
		line.position = Vector3(column * cell, 0.002, -depth/2)
		add_child(line)
	for row in rows + 1:
		var line := box(Vector3(width, 0.003, 0.01), Color("172131"))
		line.position = Vector3(width/2, 0.002, -row * cell)
		add_child(line)
	for column in columns:
		label(str(column), Vector3(column * cell + cell/2, 0.006, 0.16), 0.005, true, Color("9eafc3"))
	for row in rows:
		label(String.chr(65 + row), Vector3(-0.15, 0.006, -row * cell - cell/2), 0.005, true, Color("9eafc3"))
	label("MARC  /  火線救援", Vector3(2, 0.01, -3.48), 0.005, true, Color("9eafc3"))
	label("選手區", Vector3(-0.6, 0.01, -1.6), 0.004, true, Color("9eafc3"))
	# Boundary posts are visual only. Crossing the competition volume is detected.
	var ceiling := float(course.data.ceiling_cm) / 100.0
	for x in [0.0, width]:
		for z in [0.0, -depth]:
			var post := box(Vector3(0.015, ceiling, 0.015), Color("4b6785"))
			post.position = Vector3(x, ceiling/2, z)
			add_child(post)

func _build_pad() -> void:
	var center := MARCCourse.world(course.data.pad.x, course.data.pad.y, 0.4)
	var disc := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = float(course.data.pad.outer_diameter) / 200.0
	cylinder.bottom_radius = cylinder.top_radius
	cylinder.height = 0.004
	disc.mesh = cylinder
	disc.material_override = material(Color("176c99"))
	disc.position = center
	add_child(disc)
	var inner_radius := float(course.data.pad.inner_diameter) / 200.0
	var half_line := float(course.data.line_width_cm) / 200.0
	var inner := torus(inner_radius - half_line, inner_radius + half_line, Color.WHITE)
	inner.position = center + Vector3(0, 0.004, 0)
	add_child(inner)
	label("H", center + Vector3(0, 0.008, 0), 0.006, true, Color.WHITE)

func _prop(id: String, at: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "Prop_" + id
	body.position = at
	body.mass = 0.6
	body.freeze = true
	body.contact_monitor = true
	body.max_contacts_reported = 8
	body.physics_material_override = PhysicsMaterial.new()
	body.physics_material_override.friction = 0.85
	body.body_entered.connect(func(other: Node):
		if other is DroneBall and other.linear_velocity.length() > 0.35 and body.freeze:
			body.freeze = false
			body.apply_central_impulse(other.linear_velocity * 0.15)
			body.apply_torque_impulse(Vector3(other.linear_velocity.z, 0.04, -other.linear_velocity.x) * 0.08)
	)
	add_child(body)
	props[id] = body
	homes[id] = body.transform
	return body

func _build_ring(ring: Dictionary) -> void:
	var color := Color(String(ring.color))
	var body := _prop(ring.id, MARCCourse.world(ring.x, ring.y, ring.h))
	var radius := float(ring.diameter) / 200.0
	var visual := torus(radius, radius + 0.025, color)
	if ring.axis == "x":
		visual.rotation.z = PI / 2.0
	body.add_child(visual)
	var mid := radius + 0.0125
	for i in 32:
		var angle := TAU * i / 32.0
		var position := Vector3(cos(angle) * mid, 0, sin(angle) * mid)
		var size := Vector3(0.025, 0.025, mid * TAU / 32.0 + 0.003)
		var rotation := Vector3(0, -angle, 0)
		if ring.axis == "x":
			position = Vector3(0, cos(angle) * mid, sin(angle) * mid)
			size = Vector3(0.025, 0.025, mid * TAU / 32.0 + 0.003)
			rotation = Vector3(angle, 0, 0)
		shape_box(body, size, position, rotation)
	# Supports are outside the clear opening.
	for side in [-1.0, 1.0]:
		var support_x: float = 0.0 if ring.axis == "x" else side * (radius + 0.05)
		var support_z: float = side * (radius + 0.05) if ring.axis == "x" else 0.0
		var height := float(ring.h) / 100.0
		part(body, Vector3(0.025, height, 0.025), Vector3(support_x, -height / 2, support_z), Color("627086"))
		part(body, Vector3(0.20, 0.025, 0.20), Vector3(support_x, -height + 0.015, support_z), Color("627086"))
	label(String(ring.id), body.position + Vector3(0, radius + 0.13, 0), 0.0035)

func _build_pole() -> void:
	var p: Dictionary = course.data.pole
	var body := _prop("2", MARCCourse.world(p.x, p.y, 0))
	part(body, Vector3(0.03, p.h / 100.0, 0.03), Vector3(0, p.h / 200.0, 0), Color("ef9c23"))
	part(body, Vector3(0.18, 0.025, 0.18), Vector3(0, 0.015, 0), Color("7c663f"))
	label("2  ↺", body.position + Vector3(0, 1.68, 0), 0.004)

func _build_bridge() -> void:
	var p: Dictionary = course.data.bridge
	var body := _prop("3", MARCCourse.world(p.x, p.y, p.h))
	part(body, Vector3(p.length / 100.0, 0.03, 0.03), Vector3.ZERO, Color("ef9c23"))
	var height := float(p.h) / 100.0
	var half_length := float(p.length) / 200.0 - 0.01
	for x in [-half_length, half_length]:
		part(body, Vector3(0.025, height, 0.025), Vector3(x, -height/2, 0), Color("627086"))
		part(body, Vector3(0.16, 0.025, 0.22), Vector3(x, -height + 0.015, 0), Color("627086"))
	label("3", body.position + Vector3(0, 0.18, 0), 0.004)

func _physics_process(_delta: float) -> void:
	for id in props:
		var body: RigidBody3D = props[id]
		if not body.freeze and not fallen.has(id) and body.global_basis.y.dot(Vector3.UP) < 0.45:
			fallen[id] = true
			obstacle_fallen.emit(id)

func reset_props() -> void:
	for id in props:
		var body: RigidBody3D = props[id]
		body.freeze = true
		body.transform = homes[id]
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
	fallen.clear()

func set_group(is_program: bool) -> void:
	program_group = is_program
	card_meshes["5"].visible = is_program
	if is_instance_valid(report_label): report_label.visible = is_program
	randomize_cards()

func randomize_cards(seed_value := -1) -> void:
	var rng := RandomNumberGenerator.new()
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	for card in course.cards(program_group):
		var choices := ["red", "yellow", "green", "blue"] if card.id == "5" else ["red", "yellow", "green"]
		set_card(card.id, choices[rng.randi_range(0, choices.size() - 1)])

func set_card(id: String, color: String) -> void:
	if card_meshes.has(id) and MARCCourse.COLORS.has(color):
		card_colors[id] = color
		var card_material := material(MARCCourse.COLORS[color])
		card_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		card_meshes[id].material_override = card_material

func sensor_at(point: Vector3) -> Dictionary:
	var p := MARCCourse.coordinates(point)
	var bottom := p.z - float(course.data.drone_radius_cm)
	if bottom > 30.0 or bottom < -1.0:
		return {"id":"", "color":"none"}
	for card in course.cards(program_group):
		if absf(p.x - float(card.x)) <= 20 and absf(p.y - float(card.y)) <= 20:
			return {"id":card.id, "color":card_colors.get(card.id, "none")}
	return {"id":"", "color":"none"}

static func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.7
	return result

static func box(size: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material(color)
	return node

static func torus(inner: float, outer: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 48
	mesh.ring_segments = 12
	node.mesh = mesh
	node.material_override = material(color)
	return node

static func shape_box(parent: Node3D, size: Vector3, at: Vector3, rotation := Vector3.ZERO) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = at
	collision.rotation = rotation
	parent.add_child(collision)

static func part(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	shape_box(parent, size, at)
	var visual := box(size, color)
	visual.position = at
	parent.add_child(visual)

func label(text: String, at: Vector3, pixel: float, flat := false, color := Color("1d334f")) -> Label3D:
	var node := Label3D.new()
	node.text = text
	node.font_size = 44
	node.pixel_size = pixel
	node.modulate = color if flat else Color.WHITE
	node.outline_size = 3 if not flat else 0
	node.position = at
	if flat:
		node.rotation.x = -PI / 2.0
	else:
		node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(node)
	return node
