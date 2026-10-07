class_name MARCControllerSettings
extends RefCounted

const PATH := "user://marc_drone/controller.json"
const CHANNELS := ["throttle", "yaw", "pitch", "roll"]
const DEFAULT_INPUT := {
	"mode": 2, "deadzone": 0.035, "sensitivity": 1.0,
	"mapping": {"throttle":"left_y", "yaw":"left_x", "pitch":"right_y", "roll":"right_x"},
	"reverse": {"throttle":false, "yaw":false, "pitch":false, "roll":false}
}
var input: Dictionary = DEFAULT_INPUT.duplicate(true)
var source := "auto"
var device_guid := ""
var device_name := ""
var selected_id := -1

func _init() -> void:
	if FileAccess.file_exists(PATH):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if data is Dictionary and validation(data).is_empty():
			apply_document(data)

func document() -> Dictionary:
	return {"schema_version":1, "source":source, "device_guid":device_guid, "device_name":device_name, "input":input.duplicate(true)}

func apply_document(data: Dictionary) -> void:
	input = data.input.duplicate(true)
	source = String(data.get("source", "auto"))
	device_guid = String(data.get("device_guid", ""))
	device_name = String(data.get("device_name", ""))

func save() -> bool:
	return write_document(PATH)

func write_document(path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file: return false
	file.store_string(JSON.stringify(document(), "\t"))
	return true

func import_document(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file: return "無法讀取設定檔"
	var data: Variant = JSON.parse_string(file.get_as_text())
	var error := validation(data)
	if not error.is_empty(): return error
	var previous := document()
	apply_document(data)
	if not save():
		apply_document(previous)
		return "無法儲存設定"
	return ""

static func validation(data: Variant) -> String:
	if not data is Dictionary or data.get("schema_version") != 1:
		return "設定檔版本或格式不正確"
	if data.get("source", "auto") not in ["auto","keyboard","gamepad","phone"]:
		return "控制來源不正確"
	for key in ["device_guid","device_name"]:
		if not data.get(key, "") is String: return "裝置資料不正確"
	var config: Variant = data.get("input")
	if not config is Dictionary: return "缺少搖桿設定"
	var mode: Variant = config.get("mode")
	if not (mode is int or mode is float) or float(mode) not in [1.0,2.0,3.0]: return "搖桿模式不正確"
	for spec in [["deadzone",0.0,0.25],["sensitivity",0.25,2.0]]:
		var value: Variant = config.get(spec[0])
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < spec[1] or float(value) > spec[2]:
			return "死區或靈敏度超出範圍"
	var mapping: Variant = config.get("mapping")
	var reverse: Variant = config.get("reverse")
	if not mapping is Dictionary or not reverse is Dictionary: return "缺少通道或反向設定"
	var used: Array[String] = []
	for channel in CHANNELS:
		var axis: Variant = mapping.get(channel)
		if axis not in DesktopGamepadInput.AXIS_SOURCES or axis in used:
			return "每個通道須對應不同的搖桿軸"
		used.append(axis)
		if not reverse.get(channel) is bool: return "反向設定必須為布林值"
	return ""

func selected_device() -> int:
	var pads := Input.get_connected_joypads()
	if selected_id in pads and Input.get_joy_guid(selected_id) == device_guid: return selected_id
	if device_guid.is_empty() and device_name.is_empty():
		return pads[0] if not pads.is_empty() else -1
	for id in pads:
		if (not device_guid.is_empty() and Input.get_joy_guid(id) == device_guid) or (device_guid.is_empty() and Input.get_joy_name(id) == device_name):
			return id
	return pads[0] if source == "auto" and not pads.is_empty() else -1

func select_device(id: int) -> void:
	selected_id = id
	device_guid = Input.get_joy_guid(id)
	device_name = Input.get_joy_name(id)

func resolved_source(phone_connected := false) -> String:
	if source != "auto": return source
	if phone_connected: return "phone"
	return "gamepad" if selected_device() >= 0 else "keyboard"

static func adjusted_frame(frame: DroneInputFrame, config: Dictionary) -> DroneInputFrame:
	var adjusted := DroneInputFrame.from_wire(frame.to_dictionary(), frame.received_time_ms)
	var deadzone := clampf(float(config.get("deadzone", 0.035)), 0, 0.25)
	var sensitivity := clampf(float(config.get("sensitivity", 1.0)), 0.25, 2.0)
	var reverse: Dictionary = config.get("reverse", {})
	for channel in ["yaw","pitch","roll"]:
		var value: float = adjusted.get(channel)
		value = 0.0 if absf(value) <= deadzone else signf(value) * (absf(value) - deadzone) / (1.0 - deadzone)
		value = clampf(value * sensitivity, -1.0, 1.0)
		adjusted.set(channel, -value if bool(reverse.get(channel, false)) else value)
	if bool(reverse.get("throttle", false)): adjusted.throttle = 1.0 - adjusted.throttle
	return adjusted

static func flight_frame(frame: DroneInputFrame, config: Dictionary) -> DroneInputFrame:
	var adjusted := adjusted_frame(frame, config)
	# Stick-up is positive in the shared radio protocol; MARC forward is local -Z.
	adjusted.pitch *= -1.0
	return adjusted
