class_name MARCCourse
extends RefCounted

const COLORS := {"red":Color("ed414b"),"yellow":Color("ffc737"),"green":Color("35b87a"),"blue":Color("327df3"),"white":Color.WHITE,"off":Color("182235")}
var data: Dictionary

func _init() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string("res://config/course.json"))

static func world(x: float, y: float, h: float) -> Vector3:
	return Vector3(x, h, -y) / 100.0

static func coordinates(point: Vector3) -> Vector3:
	return Vector3(point.x, -point.z, point.y) * 100.0

func spawn() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -PI / 2.0), world(data.pad.x, data.pad.y, float(data.drone_radius_cm) + 0.5))

func cards(program_group: bool) -> Array:
	var result: Array = data.cards.duplicate(true)
	if program_group:
		result.append(data.report_card.duplicate(true))
	return result
