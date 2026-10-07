class_name MARCCompetition
extends RefCounted

signal changed()
signal phase_changed()
signal match_finished(result: Dictionary)
var course := MARCCourse.new()
var group := "program"
var state := "practice"
var stage := 0
var remaining := 0.0
var elapsed := [0.0, 0.0]
var scores := [0, 0]
var counts: Dictionary = {}
var cards_locked: Dictionary = {}
var log: Array[Dictionary] = []
var resets := 0
var suppressed := false
var major_zero := false
var zero_stage_two := false
var progress := -1
var ring_tracking: Dictionary = {}
var pole_angle := 0.0
var pole_previous := NAN
var bridge_step := 0
var tunnel_step := 0
var color_key := ""
var color_seconds := 0.0
var stationary_seconds := 0.0
var last_landing := -1
var previous := Vector3.ZERO
var previous_valid := false
var was_airborne := false
var floor_latched := false
var bounds_latched := false
var failed_props: Dictionary = {}
var wrong_stage: Dictionary = {}
var records: Array = []
const ORDER := ["1A","1B","2","3","4A","4B","4C","5"]
const NAMES := {"takeoff":"首次起飛","1A":"①A 高位圓圈","1B":"①B 低位圓圈","2":"② 環繞標杆","3":"③ 穿越斷橋","4A":"④A 隧道","4B":"④B 隧道","4C":"④C 隧道","combo":"隧道連續加分","5":"⑤ 回報／尋求支援","6":"⑥ 捷徑","7-1":"⑦-1 火點","7-2":"⑦-2 火點","7-3":"⑦-3 火點","7-4":"⑦-4 火點","7-5":"⑦-5 火點","7-6":"⑦-6 火點","8":"⑧ 安全返回"}

func _init() -> void:
	if FileAccess.file_exists("user://marc-matches.json"):
		var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://marc-matches.json"))
		if loaded is Array:
			records = loaded

func configure(next_group: String) -> void:
	group = next_group
	clear_match()
	state = "practice"
	phase_changed.emit()

func clear_match() -> void:
	stage = 0
	remaining = 0
	elapsed = [0.0, 0.0]
	scores = [0, 0]
	counts.clear()
	cards_locked.clear()
	log.clear()
	resets = 0
	suppressed = false
	major_zero = false
	zero_stage_two = false
	progress = -1
	wrong_stage.clear()
	failed_props.clear()
	clear_tracking()
	changed.emit()

func prepare() -> void:
	clear_match()
	state = "prepare"
	remaining = 60 if group == "program" else 30
	_event("準備開始", 0)
	phase_changed.emit()

func begin() -> void:
	if state != "prepare":
		return
	state = "active"
	remaining = 180 if group == "program" else 90
	_event("開始" if group == "program" else "第一階段開始", 0)
	clear_tracking()
	phase_changed.emit()

func clear_tracking() -> void:
	ring_tracking.clear()
	pole_angle = 0
	pole_previous = NAN
	bridge_step = 0
	tunnel_step = 0
	color_key = ""
	color_seconds = 0
	stationary_seconds = 0
	last_landing = -1
	previous_valid = false
	was_airborne = false
	floor_latched = false
	bounds_latched = false

func can_program() -> bool:
	return state == "practice" or (state == "active" and (group == "program" or stage == 1))

func can_manual() -> bool:
	return state == "practice" or (state == "active" and group == "hybrid" and stage == 0)

func reset_allowed() -> bool:
	return state in ["practice", "prepare", "transition", "finished"] or (state == "active" and (group == "program" or stage == 1))

func reset_flight() -> bool:
	if not reset_allowed():
		_event("第一階段不可重置；可由裁判宣告故障進入交接", 0)
		return false
	if state == "active":
		resets += 1
		_event("重置完成，保留得分與色卡判定", 0)
	suppressed = false
	failed_props.clear()
	clear_tracking()
	return true

func tick(delta: float, position: Vector3, velocity: Vector3, armed: bool, led: String, sensed: Dictionary) -> void:
	if state in ["prepare", "transition"]:
		remaining = maxf(0, remaining - delta)
		if remaining <= 0:
			if state == "prepare":
				begin()
			else:
				stage = 1
				state = "active"
				remaining = 150
				clear_tracking()
				_event("第二階段開始", 0)
				phase_changed.emit()
		return
	if state != "active":
		return
	var dt := minf(delta, remaining)
	remaining -= dt
	elapsed[stage] += dt
	var p := MARCCourse.coordinates(position)
	var radius := float(course.data.drone_radius_cm)
	var grounded := p.z <= radius + 1.5
	var still := grounded and velocity.length() < 0.025 and not armed
	stationary_seconds = stationary_seconds + dt if still else 0
	if not still:
		last_landing = -1
	if stationary_seconds >= 0.5 and was_airborne:
		last_landing = landing_points(p)
	if armed and p.z > radius + 5:
		was_airborne = true
		if group == "program":
			award("takeoff")
	var on_pad := Vector2(p.x - float(course.data.pad.x), p.y - float(course.data.pad.y)).length() <= float(course.data.pad.outer_diameter) / 2.0 + radius
	if group == "hybrid" and stage == 0 and was_airborne and grounded and not floor_latched and not on_pad:
		penalty("第一階段接觸地面", 10)
		if String(sensed.get("id", "")).begins_with("7-"):
			penalty("第一階段碰觸第二階段色卡", 20)
	floor_latched = grounded
	var outside := p.x - radius < 0 or p.x + radius > float(course.data.width_cm) or p.y - radius < 0 or p.y + radius > float(course.data.depth_cm) or p.z + radius > float(course.data.ceiling_cm)
	if outside and not bounds_latched:
		_event("超出場地或限高，裁判可要求重置", 0)
	bounds_latched = outside
	if previous_valid and not suppressed:
		for ring in course.data.rings:
			_track_ring(ring, previous, p, radius)
		_track_pole(p, radius)
		_track_bridge(previous, p, radius)
	if not suppressed:
		_track_color(dt, led, sensed)
	if group == "hybrid" and stage == 0 and was_airborne and stationary_seconds >= 0.5:
		if Vector2(p.x - float(course.data.pad.x), p.y - float(course.data.pad.y)).length() <= float(course.data.pad.outer_diameter) / 2.0 + radius:
			attempt("5")
			award("5")
			end_first_stage()
	previous = p
	previous_valid = true
	if state == "active" and remaining <= 0:
		if group == "hybrid" and stage == 0:
			end_first_stage()
		else:
			finish()

func _track_ring(ring: Dictionary, before: Vector3, p: Vector3, radius: float) -> void:
	var id := String(ring.id)
	if failed_props.has(id):
		return
	var center := Vector3(ring.x, ring.y, ring.h)
	var axis := 2 if ring.axis == "h" else 0
	var direction := float(ring.direction)
	var a := (before[axis] - center[axis]) * direction
	var b := (p[axis] - center[axis]) * direction
	var aperture := float(ring.diameter) / 2.0
	var radial_a := (Vector2(before.x - center.x, before.y - center.y) if axis == 2 else Vector2(before.y - center.y, before.z - center.z)).length()
	var radial_b := (Vector2(p.x - center.x, p.y - center.y) if axis == 2 else Vector2(p.y - center.y, p.z - center.z)).length()
	if a * b <= 0 and a != b and minf(radial_a, radial_b) < aperture + radius:
		attempt(id)
	if (a < -radius and radial_a + radius <= aperture) or (b < -radius and radial_b + radius <= aperture):
		ring_tracking[id] = true
	if not ring_tracking.get(id, false):
		return
	if absf(b) <= radius and radial_b + radius > aperture:
		ring_tracking.erase(id)
	elif b > radius and a <= radius:
		ring_tracking.erase(id)
		if maxf(radial_a, radial_b) + radius <= aperture:
			award(id)

func _track_pole(p: Vector3, radius: float) -> void:
	if failed_props.has("2"):
		return
	var pole: Dictionary = course.data.pole
	if p.z + radius >= float(pole.h) or Vector2(p.x - float(pole.x), p.y - float(pole.y)).length() < radius + 1.5:
		pole_previous = NAN
		pole_angle = 0
		return
	var angle := atan2(p.y - float(pole.y), p.x - float(pole.x))
	if not is_nan(pole_previous):
		var turn := wrapf(angle - pole_previous, -PI, PI)
		pole_angle += turn
		if pole_angle >= TAU - 0.001:
			attempt("2")
			award("2")
			pole_angle = 0
		elif pole_angle < -0.05:
			pole_angle = 0
	pole_previous = angle

func _track_bridge(before: Vector3, p: Vector3, radius: float) -> void:
	if failed_props.has("3"):
		return
	var bridge: Dictionary = course.data.bridge
	var center_y := float(bridge.y)
	if absf(p.x - float(bridge.x)) + radius > float(bridge.length) / 2.0:
		bridge_step = 0
		return
	if before.y > center_y and p.y <= center_y:
		attempt("3")
		if maxf(before.z, p.z) + radius < float(bridge.h) - 1.5:
			bridge_step = 1
		else:
			bridge_step = 0
	if bridge_step == 1 and p.y + radius < center_y and p.z + radius < float(bridge.h) - 1.5:
		bridge_step = 2
	elif bridge_step == 1 and absf(p.y - center_y) < radius and p.z + radius >= float(bridge.h) - 1.5:
		bridge_step = 0
	if before.y < center_y and p.y >= center_y:
		attempt("3")
		if bridge_step == 2 and minf(before.z, p.z) - radius > float(bridge.h) + 1.5:
			bridge_step = 3
		else:
			bridge_step = 0
	if bridge_step == 3 and absf(p.y - center_y) < radius and p.z - radius <= float(bridge.h) + 1.5:
		bridge_step = 0
	if bridge_step == 3 and p.y - radius > center_y:
		award("3")
		bridge_step = 0

func _track_color(dt: float, led: String, sensed: Dictionary) -> void:
	var id := String(sensed.get("id", ""))
	if id.is_empty() or led in ["white", "off"] or cards_locked.has(id):
		color_key = ""
		color_seconds = 0
		return
	var key := id + ":" + led
	if key != color_key:
		color_key = key
		color_seconds = 0
	color_seconds += dt
	if color_seconds + 0.000001 >= 2.0:
		attempt(id)
		if not _valid_stage(id):
			return
		cards_locked[id] = led == String(sensed.get("color", "none"))
		if cards_locked[id]:
			award(id)
		else:
			_event("%s 首次燈號錯誤，本場鎖定" % NAMES.get(id, id), 0)

func _valid_stage(id: String) -> bool:
	if group == "program":
		return true
	var first := id in ORDER
	return (stage == 0 and first) or (stage == 1 and not first and id != "takeoff" and id != "combo")

func attempt(id: String) -> void:
	if state != "active" or suppressed or group != "hybrid":
		return
	if not _valid_stage(id):
		if not wrong_stage.has(id):
			wrong_stage[id] = true
			penalty("執行非本階段任務 " + id, 30)
		return
	if stage == 0:
		var index := ORDER.find(id)
		if index > progress:
			progress = index

func points_and_limit(id: String) -> Vector2i:
	if group == "program":
		if id == "takeoff": return Vector2i(10, 1)
		if id in ["1A","1B","2","3","6","combo"]: return Vector2i(10, 2)
		if id in ["4A","4B","4C"]: return Vector2i(5, 2)
		if id == "5": return Vector2i(20, 1)
		if id.begins_with("7-"): return Vector2i(15, 1)
	else:
		if id in ["1A","1B"]: return Vector2i(20, 1)
		if id in ["2","3","4A","4B","4C","5","6"] or id.begins_with("7-"): return Vector2i(10, 1)
	return Vector2i(0, 0)

func award(id: String) -> bool:
	if state != "active" or suppressed or not _valid_stage(id):
		return false
	if group == "hybrid" and stage == 0 and ORDER.find(id) < progress:
		return false
	var rule := points_and_limit(id)
	if rule.x <= 0 or int(counts.get(id, 0)) >= rule.y:
		return false
	counts[id] = int(counts.get(id, 0)) + 1
	scores[stage] += rule.x
	_event(String(NAMES.get(id, id)), rule.x)
	if group == "program":
		if id == "4A":
			tunnel_step = 1
		elif id == "4B" and tunnel_step == 1:
			tunnel_step = 2
		elif id == "4C" and tunnel_step == 2:
			tunnel_step = 0
			award("combo")
		else:
			tunnel_step = 0
	return true

func landing_points(p: Vector3) -> int:
	var distance := Vector2(p.x - float(course.data.pad.x), p.y - float(course.data.pad.y)).length()
	var radius := float(course.data.drone_radius_cm)
	var inner := float(course.data.pad.inner_diameter) / 2.0
	var half_line := float(course.data.line_width_cm) / 2.0
	if distance + radius < inner - half_line:
		return 30
	if distance <= inner and distance + radius >= inner - half_line:
		return 10
	return 0

func penalty(reason: String, amount: int) -> void:
	if state != "active":
		return
	scores[stage] -= amount
	_event(reason, -amount)

func prop_fallen(id: String) -> void:
	failed_props[id] = true
	penalty("道具碰倒 " + id, 20)

func referee(action: String) -> void:
	match action:
		"touch_person": penalty("碰觸選手或裁判", 10)
		"enter":
			if group == "hybrid": penalty("擅自進場", 20)
			elif state == "active": _event("裁判記錄：選手進場；若有介入須登錄並重置",0)
		"touch_stage_two":
			if group == "hybrid" and stage == 0: penalty("第一階段碰觸第二階段道具", 20)
		"early":
			if state == "prepare" or state == "transition":
				scores[0 if state == "prepare" else 1] -= 20
				_event("口令前啟動程式或起飛", -20)
		"intervention":
			if state == "active" and (group == "program" or stage == 1):
				suppressed = true
				_event("未依重置程序介入，暫停任務計分", 0)
		"manual_violation":
			if state == "active" and (group == "program" or stage == 1):
				if group == "program": major_zero = true
				else: zero_stage_two = true
				_event("自主階段即時操控，適用階段零分", 0)
				finish()
		"major":
			if state == "active":
				major_zero = true
				_event("重大違規，本回合零分", 0)
				finish()
		"fault":
			if state == "active":
				if group == "hybrid" and stage == 0: end_first_stage()
				else: finish()

func end_first_stage() -> void:
	if group != "hybrid" or stage != 0 or state != "active":
		return
	state = "transition"
	remaining = 30
	clear_tracking()
	_event("第一階段結束，交接 30 秒", 0)
	phase_changed.emit()

func request_finish() -> bool:
	if state != "active" or stationary_seconds < 0.5:
		return false
	if group == "hybrid" and stage == 0:
		end_first_stage()
	else:
		finish()
	return true

func finish() -> void:
	if state != "active":
		return
	if last_landing > 0 and not suppressed:
		scores[stage] += last_landing
		counts["8"] = last_landing
		_event("⑧ 安全返回", last_landing)
	state = "finished"
	var total := int(scores[0]) + (0 if zero_stage_two else int(scores[1]))
	if major_zero:
		total = 0
	var result := {"group":group,"score":total,"stage_scores":scores.duplicate(),"elapsed":elapsed.duplicate(),"time":float(elapsed[0])+float(elapsed[1]),"resets":resets,"counts":counts.duplicate(),"cards":cards_locked.duplicate(),"events":log.duplicate(true),"recorded":Time.get_datetime_string_from_system(),"major_zero":major_zero,"zero_stage_two":zero_stage_two}
	records.append(result)
	# Each group retains the most recent three rounds.
	var matching := 0
	for i in range(records.size() - 1, -1, -1):
		if records[i].get("group") == group:
			matching += 1
			if matching > 3:
				records.remove_at(i)
	var file := FileAccess.open("user://marc-matches.json.tmp", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(records, "\t"))
		file.close()
		DirAccess.rename_absolute("user://marc-matches.json.tmp", "user://marc-matches.json")
	match_finished.emit(result)
	phase_changed.emit()
	changed.emit()

func ranked_records() -> Array:
	var result := records.filter(func(item: Dictionary): return item.get("group") == group)
	result.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.score) != int(b.score): return int(a.score) > int(b.score)
		return float(a.time) < float(b.time)
	)
	return result

func _event(reason: String, points: int) -> void:
	log.append({"stage":stage + 1,"time":snappedf(float(elapsed[stage]), 0.01),"reason":reason,"points":points})
	changed.emit()
