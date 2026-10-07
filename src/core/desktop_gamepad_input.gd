class_name DesktopGamepadInput
extends RefCounted

const CALIBRATION_PATH := "user://gamepad-calibration.json"
const AXIS_SOURCES := ["left_x", "left_y", "right_x", "right_y"]

const DEFAULT_MAPPING := {
	"throttle": "left_y",
	"yaw": "left_x",
	"pitch": "right_y",
	"roll": "right_x",
}
const MODE_1_MAPPING := {
	"throttle": "right_y",
	"yaw": "left_x",
	"pitch": "left_y",
	"roll": "right_x",
}
const BUTTON_COMMANDS := {
	&"toggle_arm": JOY_BUTTON_A,
	&"toggle_mode": JOY_BUTTON_X,
	&"turtle": JOY_BUTTON_Y,
	&"reset": JOY_BUTTON_START,
	&"toggle_camera": JOY_BUTTON_B,
}

var _previous_buttons: Dictionary = {}
var _calibrations: Dictionary = {}
var _range_capture: Dictionary = {}

func _init() -> void:
	_load_calibrations()

func sample_frame(device_id: int, input_config: Dictionary, requested_mode: StringName) -> DroneInputFrame:
	var mapping := mapping_for_config(input_config)
	return frame_from_axes(calibrated_axes(device_id, String(mapping.throttle)), input_config, requested_mode)

func raw_axes(device_id: int) -> Dictionary:
	return {
		"left_x": Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X),
		"left_y": Input.get_joy_axis(device_id, JOY_AXIS_LEFT_Y),
		"right_x": Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_X),
		"right_y": Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_Y),
	}

func calibrated_axes(device_id: int, throttle_source := "") -> Dictionary:
	var raw := raw_axes(device_id)
	var calibration := calibration_for(device_id)
	var result: Dictionary = {}
	for source in AXIS_SOURCES:
		result[source] = calibrate_axis_range(float(raw[source]), calibration[source]) if source == throttle_source else calibrate_axis(float(raw[source]), calibration[source])
	return result

func calibration_for(device_id: int) -> Dictionary:
	var key := _device_key(device_id)
	if not _calibrations.has(key):
		_calibrations[key] = _default_calibration(Input.get_joy_name(device_id))
	return _calibrations[key]

func capture_center(device_id: int, throttle_source := "") -> void:
	var calibration := calibration_for(device_id)
	var raw := raw_axes(device_id)
	for source in AXIS_SOURCES:
		if source == throttle_source:
			continue
		var axis: Dictionary = calibration[source]
		axis["center"] = float(raw[source])
		axis["min"] = minf(float(axis.get("min", -1.0)), float(axis.center) - 0.1)
		axis["max"] = maxf(float(axis.get("max", 1.0)), float(axis.center) + 0.1)
	calibration["name"] = Input.get_joy_name(device_id)
	_calibrations[_device_key(device_id)] = calibration
	_save_calibrations()

func begin_range_calibration(device_id: int) -> void:
	var raw := raw_axes(device_id)
	_range_capture.clear()
	for source in AXIS_SOURCES:
		_range_capture[source] = {"min": float(raw[source]), "max": float(raw[source])}

func capture_range_sample(device_id: int) -> void:
	if _range_capture.is_empty():
		return
	var raw := raw_axes(device_id)
	for source in AXIS_SOURCES:
		var captured: Dictionary = _range_capture[source]
		captured["min"] = minf(float(captured.min), float(raw[source]))
		captured["max"] = maxf(float(captured.max), float(raw[source]))

func finish_range_calibration(device_id: int, throttle_source := "") -> Dictionary:
	var calibration := calibration_for(device_id)
	var incomplete := PackedStringArray()
	for source in AXIS_SOURCES:
		var captured: Dictionary = _range_capture.get(source, {})
		var axis: Dictionary = calibration[source]
		var center := float(axis.center)
		var minimum := float(captured.get("min", center))
		var maximum := float(captured.get("max", center))
		var valid_range := maximum - minimum >= 0.4 if source == throttle_source else center - minimum >= 0.2 and maximum - center >= 0.2
		if valid_range:
			axis["min"] = minimum
			axis["max"] = maximum
			if source == throttle_source:
				axis["center"] = (minimum + maximum) * 0.5
		else:
			incomplete.append(source)
	_range_capture.clear()
	calibration["name"] = Input.get_joy_name(device_id)
	_calibrations[_device_key(device_id)] = calibration
	_save_calibrations()
	return {"ok": incomplete.is_empty(), "incomplete": incomplete}

func cancel_range_calibration() -> void:
	_range_capture.clear()

func reset_calibration(device_id: int) -> void:
	_calibrations[_device_key(device_id)] = _default_calibration(Input.get_joy_name(device_id))
	_range_capture.clear()
	_save_calibrations()

func poll_commands(device_id: int) -> Array[StringName]:
	var buttons := _read_buttons(device_id)
	var commands := commands_from_buttons(buttons, _previous_buttons)
	_previous_buttons = buttons
	return commands

func prime_button_state(device_id: int) -> void:
	_previous_buttons = _read_buttons(device_id)

func clear_button_state() -> void:
	_previous_buttons.clear()

func _read_buttons(device_id: int) -> Dictionary:
	var buttons: Dictionary = {}
	for command in BUTTON_COMMANDS:
		buttons[command] = Input.is_joy_button_pressed(device_id, BUTTON_COMMANDS[command])
	return buttons

static func frame_from_axes(raw_axes: Dictionary, input_config: Dictionary, requested_mode: StringName) -> DroneInputFrame:
	var mapping := mapping_for_config(input_config)
	var physical: Dictionary = {}
	for source in ["left_x", "left_y", "right_x", "right_y"]:
		var value := clampf(float(raw_axes.get(source, 0.0)), -1.0, 1.0)
		physical[source] = -value if source.ends_with("_y") else value
	var frame := DroneInputFrame.new()
	var throttle_source := String(mapping.get("throttle", DEFAULT_MAPPING.throttle))
	frame.throttle = clampf((float(physical.get(throttle_source, -1.0)) + 1.0) * 0.5, 0.0, 1.0)
	for channel in ["yaw", "pitch", "roll"]:
		var source := String(mapping.get(channel, DEFAULT_MAPPING[channel]))
		frame.set(channel, float(physical.get(source, 0.0)))
	frame.requested_mode = requested_mode
	return frame

static func commands_from_buttons(buttons: Dictionary, previous_buttons: Dictionary) -> Array[StringName]:
	var commands: Array[StringName] = []
	for command in BUTTON_COMMANDS:
		if bool(buttons.get(command, false)) and not bool(previous_buttons.get(command, false)):
			commands.append(command)
	return commands

static func mapping_for_config(input_config: Dictionary) -> Dictionary:
	var mode := int(input_config.get("mode", 2))
	if mode == 1:
		return MODE_1_MAPPING
	if mode == 3:
		return input_config.get("mapping", DEFAULT_MAPPING)
	return DEFAULT_MAPPING

static func calibrate_axis(value: float, calibration: Dictionary) -> float:
	var minimum := float(calibration.get("min", -1.0))
	var center := float(calibration.get("center", 0.0))
	var maximum := float(calibration.get("max", 1.0))
	if value >= center:
		return clampf((value - center) / maxf(0.001, maximum - center), 0.0, 1.0)
	return clampf((value - center) / maxf(0.001, center - minimum), -1.0, 0.0)

static func calibrate_axis_range(value: float, calibration: Dictionary) -> float:
	var minimum := float(calibration.get("min", -1.0))
	var maximum := float(calibration.get("max", 1.0))
	return clampf(((value - minimum) / maxf(0.001, maximum - minimum)) * 2.0 - 1.0, -1.0, 1.0)

func _device_key(device_id: int) -> String:
	var guid := Input.get_joy_guid(device_id).strip_edges()
	return guid if not guid.is_empty() else "name:" + Input.get_joy_name(device_id).strip_edges()

func _default_calibration(device_name: String) -> Dictionary:
	var calibration := {"name": device_name, "axes": {}}
	for source in AXIS_SOURCES:
		calibration.axes[source] = {"min": -1.0, "center": 0.0, "max": 1.0}
	return _flatten_calibration(calibration)

func _flatten_calibration(calibration: Dictionary) -> Dictionary:
	var result := {"name": String(calibration.get("name", ""))}
	var axes: Dictionary = calibration.get("axes", calibration)
	for source in AXIS_SOURCES:
		var axis: Dictionary = axes.get(source, {})
		result[source] = {
			"min": clampf(float(axis.get("min", -1.0)), -1.0, 1.0),
			"center": clampf(float(axis.get("center", 0.0)), -1.0, 1.0),
			"max": clampf(float(axis.get("max", 1.0)), -1.0, 1.0),
		}
	return result

func _load_calibrations() -> void:
	if not FileAccess.file_exists(CALIBRATION_PATH):
		return
	var file := FileAccess.open(CALIBRATION_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var devices: Variant = parsed.get("devices", {})
	if not devices is Dictionary:
		return
	for key in devices:
		if devices[key] is Dictionary:
			_calibrations[String(key)] = _flatten_calibration(devices[key])

func _save_calibrations() -> void:
	var file := FileAccess.open(CALIBRATION_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"version": 1, "devices": _calibrations}, "  "))
