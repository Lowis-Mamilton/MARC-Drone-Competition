class_name MARCDrone
extends DroneBall

signal command_completed(id: String, ok: bool, message: String)
var hold_enabled := true
var target := Vector3.ZERO
var target_yaw := -PI / 2.0
var manual := DroneInputFrame.neutral()
var command: Dictionary = {}
var command_time := 0.0
var stable_time := 0.0
var landing := false
var led := "white"
var led_material: StandardMaterial3D
var maximum_speed := 0.6
var manual_enabled := true
var altitude_integral := 0.0
var last_motion := Vector3.ZERO
var turn_goal := 0.0
var turn_accumulated := 0.0
var turn_previous := 0.0
var course := MARCCourse.new()
var arena: MARCArena

func _ready() -> void:
	spawn_transform = course.spawn()
	super._ready()
	target = global_position
	target_yaw = -PI / 2.0
	# Stable defaults retain the four-motor force/torque model.
	profile["angle_limit_deg"] = 25.0
	apply_profile(profile)

func _build_visuals() -> void:
	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.1
	collision.shape = sphere
	add_child(collision)
	var body := MARCArena.box(Vector3(0.075, 0.035, 0.09), Color("e6eef6"))
	add_child(body)
	for offset in MOTOR_POSITIONS:
		var arm := MARCArena.box(Vector3(0.025, 0.014, 0.14), Color("24364c"))
		arm.rotation.y = PI / 4.0 if offset.x * offset.z > 0 else -PI / 4.0
		add_child(arm)
		var guard := MARCArena.torus(0.034, 0.039, Color("34a5cb"))
		guard.position = offset
		add_child(guard)
		var propeller := MARCArena.box(Vector3(0.058, 0.003, 0.009), Color("acbcd0"))
		propeller.position = offset + Vector3(0, 0.008, 0)
		add_child(propeller)
	var nose := MARCArena.box(Vector3(0.046, 0.013, 0.008), Color.WHITE)
	nose.position = Vector3(0, 0.01, -0.049)
	led_material = MARCArena.material(Color.WHITE)
	led_material.emission_enabled = true
	led_material.emission_energy_multiplier = 1.5
	nose.material_override = led_material
	add_child(nose)
	set_led("white")

func set_led(color: String) -> void:
	if not MARCCourse.COLORS.has(color):
		return
	led = color
	if led_material:
		led_material.albedo_color = MARCCourse.COLORS[color]
		led_material.emission = MARCCourse.COLORS[color] if color != "off" else Color.BLACK

func reset_marc() -> void:
	cancel_commands("已重置")
	spawn_transform = course.spawn()
	reset_to_spawn()
	target = spawn_transform.origin
	target_yaw = -PI / 2.0
	landing = false
	altitude_integral = 0
	manual = DroneInputFrame.neutral()
	set_led("white")

func pose() -> Dictionary:
	var p := MARCCourse.coordinates(global_position)
	return {"x":p.x,"y":p.y,"h":maxf(0, p.z - 10),"heading":fposmod(rad_to_deg(-rotation.y) - 90, 360),"speed":linear_velocity.length() * 100,"led":led,"armed":armed}

func accept_command(value: Dictionary) -> void:
	command = value.duplicate(true)
	command_time = 0
	stable_time = 0
	landing = false
	var args: Dictionary = command.get("args", {})
	var op := String(command.op)
	if op in ["goto","move","turn"] and not armed:
		_finish(false, "請先起飛")
		return
	match op:
		"takeoff":
			target = global_position
			target.y = (clampf(float(args.get("h", 50)), 10, 220) + 10) / 100.0
			altitude_integral = 0
			set_armed(true)
		"goto":
			target = MARCCourse.world(float(args.get("x", 40)), float(args.get("y", 160)), float(args.get("h", 50)) + 10)
		"move":
			target = global_position + MARCCourse.world(float(args.get("x", 0)), float(args.get("y", 0)), float(args.get("h", 0)))
			var p := MARCCourse.coordinates(target)
			if p.x < 10 or p.x > 390 or p.y < 10 or p.y > 310 or p.z < 10 or p.z > 230:
				_finish(false, "相對移動目的地超出安全飛行範圍")
				target = global_position
		"turn":
			target = global_position
			turn_goal = float(args.get("degrees", 0))
			turn_accumulated = 0
			turn_previous = rotation.y
			target_yaw = rotation.y - deg_to_rad(clampf(turn_goal, -60, 60))
		"land":
			target = global_position
			landing = true
		"wait":
			pass
		"led":
			set_led(String(args.get("color", "white")))
			_finish(true, "燈號已更新")
		"match":
			var sensed := arena.sensor_at(global_position)
			if sensed.color == "none":
				_finish(false, "未偵測到色卡，請降至色卡上方 30 公分內")
			else:
				set_led(sensed.color)
				_finish(true, "燈號已同步")
		_:
			_finish(false, "未知飛行指令")

func cancel_commands(reason := "程式已停止") -> void:
	if not command.is_empty():
		_finish(false, reason)
	landing = false
	target = global_position

func _finish(ok: bool, message: String) -> void:
	var id := String(command.get("id", ""))
	command.clear()
	command_completed.emit(id, ok, message)

func _physics_process(delta: float) -> void:
	if command.get("op", "") == "turn":
		turn_accumulated -= rad_to_deg(wrapf(rotation.y - turn_previous, -PI, PI))
		turn_previous = rotation.y
		target_yaw = rotation.y - deg_to_rad(clampf(turn_goal - turn_accumulated, -60, 60))
	if manual_enabled and command.is_empty() and armed and not landing:
		var velocity := Vector3(manual.roll, 0, manual.pitch) * 0.65
		velocity = Basis(Vector3.UP, rotation.y) * velocity
		target += velocity * delta
		target.y += (manual.throttle - 0.5) * 0.8 * delta
		target.y = maxf(0.105, target.y)
		target_yaw -= manual.yaw * 1.6 * delta
		# Release sticks to brake and hold the current position.
		if velocity.length() < 0.02 and last_motion.length() > 0.02:
			target.x = global_position.x
			target.z = global_position.z
		last_motion = velocity
	if landing:
		target.y = maxf(0.095, target.y - delta * 0.22)
		if global_position.y <= 0.112 and absf(linear_velocity.y) < 0.08:
			set_armed(false)
			landing = false
			if not command.is_empty():
				_finish(true, "已降落")
	if armed:
		input_frame = _position_frame(delta)
	else:
		input_frame = DroneInputFrame.neutral()
	if not command.is_empty():
		command_time += delta
		var op := String(command.op)
		if op == "wait":
			if command_time >= float(command.get("args", {}).get("seconds", 1)):
				_finish(true, "等待完成")
		elif op != "land":
			var close := global_position.distance_to(target) <= 0.03 and linear_velocity.length() < 0.08
			close = close and absf(wrapf(target_yaw - rotation.y, -PI, PI)) < deg_to_rad(5)
			if op == "turn": close = close and absf(turn_goal - turn_accumulated) < 5
			stable_time = stable_time + delta if close else 0
			if stable_time >= 0.3:
				_finish(true, "飛行動作完成")
		if not command.is_empty() and command_time > float(command.get("timeout", 30)):
			_finish(false, "動作逾時，已停止並懸停")
			target = global_position
			landing = false

func _position_frame(delta: float) -> DroneInputFrame:
	var error := target - global_position
	var desired_velocity := error * 2.0
	var horizontal := Vector2(desired_velocity.x, desired_velocity.z).limit_length(maximum_speed)
	desired_velocity.x = horizontal.x
	desired_velocity.z = horizontal.y
	desired_velocity.y = clampf(desired_velocity.y, -0.45, 0.55)
	var acceleration := (desired_velocity - linear_velocity) * 3.8
	acceleration.x = clampf(acceleration.x, -2.8, 2.8)
	acceleration.z = clampf(acceleration.z, -2.8, 2.8)
	altitude_integral = clampf(altitude_integral + error.y * delta, -0.5, 0.5)
	acceleration.y += altitude_integral * 0.8
	var local_acceleration := Basis(Vector3.UP, rotation.y).inverse() * acceleration
	var frame := DroneInputFrame.neutral()
	var angle_limit := deg_to_rad(float(profile.get("angle_limit_deg", 25)))
	frame.pitch = clampf(atan2(local_acceleration.z, GRAVITY) / angle_limit, -1, 1)
	frame.roll = clampf(atan2(local_acceleration.x, GRAVITY) / angle_limit, -1, 1)
	frame.yaw = clampf(wrapf(target_yaw - rotation.y, -PI, PI) * 1.5, -0.6, 0.6)
	var tilt := maxf(0.4, global_basis.y.dot(Vector3.UP))
	var ratio := float(profile.drone.thrust_to_weight)
	frame.throttle = sqrt(clampf((GRAVITY + acceleration.y) / (GRAVITY * ratio * tilt), 0, 1))
	return frame
