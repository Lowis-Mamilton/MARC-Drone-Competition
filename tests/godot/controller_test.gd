extends SceneTree

class VirtualRadio extends DesktopGamepadInput:
	var axes := {"left_x":0.0,"left_y":1.0,"right_x":0.0,"right_y":0.0}
	func raw_axes(_id: int) -> Dictionary:
		return axes.duplicate()
	func sample_frame(_id: int, config: Dictionary, mode: StringName) -> DroneInputFrame:
		return frame_from_axes(axes, config, mode)
	func poll_commands(_id: int) -> Array[StringName]:
		return []

class VirtualSettings extends MARCControllerSettings:
	var test_device := 77
	func selected_device() -> int:
		return test_device
	func resolved_source(_phone_connected := false) -> String:
		return "gamepad"

var failures := 0
var checks := 0
func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var config: Dictionary = MARCControllerSettings.DEFAULT_INPUT.duplicate(true)
	var axes := {"left_x":0.2,"left_y":-1.0,"right_x":0.4,"right_y":-0.8}
	var frame := DesktopGamepadInput.frame_from_axes(axes, config, &"angle")
	expect(is_equal_approx(frame.throttle,1.0) and is_equal_approx(frame.pitch,0.8),"Mode 2 maps throttle and pitch")
	config.mode = 1
	frame = DesktopGamepadInput.frame_from_axes(axes, config, &"angle")
	expect(is_equal_approx(frame.throttle,0.9) and is_equal_approx(frame.pitch,1.0),"Mode 1 swaps the vertical sticks")
	config.mode = 3
	config.mapping = {"throttle":"right_x","yaw":"left_x","pitch":"left_y","roll":"right_y"}
	frame = DesktopGamepadInput.frame_from_axes(axes, config, &"angle")
	expect(is_equal_approx(frame.throttle,0.7) and is_equal_approx(frame.roll,0.8),"Custom axes map each physical channel")
	config = MARCControllerSettings.DEFAULT_INPUT.duplicate(true)
	config.deadzone = 0.1
	config.sensitivity = 1.5
	config.reverse.yaw = true
	frame = DroneInputFrame.neutral()
	frame.throttle = 0.2
	frame.yaw = 0.4
	frame.pitch = 0.05
	frame.roll = 1
	var adjusted := MARCControllerSettings.adjusted_frame(frame, config)
	expect(is_zero_approx(adjusted.pitch),"Deadzone suppresses drift")
	expect(is_equal_approx(adjusted.yaw,-0.5) and adjusted.roll == 1.0,"Sensitivity, reversal and clipping apply to flight channels")
	expect(frame.yaw == 0.4,"Adjusting input preserves the raw frame")
	config.reverse.throttle = true
	expect(is_equal_approx(MARCControllerSettings.adjusted_frame(frame,config).throttle,0.8),"Throttle reversal works independently")
	var range_data := {"min":-0.8,"center":0.1,"max":0.9}
	expect(is_zero_approx(DesktopGamepadInput.calibrate_axis(0.1,range_data)),"Center calibration removes offset")
	expect(is_equal_approx(DesktopGamepadInput.calibrate_axis(-0.8,range_data),-1.0) and is_equal_approx(DesktopGamepadInput.calibrate_axis(0.9,range_data),1.0),"Calibrated endpoints reach full travel")
	expect(is_zero_approx(DesktopGamepadInput.calibrate_axis_range(0.05,range_data)),"Non-spring throttle uses full endpoint range")
	var settings := MARCControllerSettings.new()
	var doc := settings.document()
	expect(MARCControllerSettings.validation(doc).is_empty(),"Default settings are valid")
	doc.input.mapping.yaw = doc.input.mapping.throttle
	expect(not MARCControllerSettings.validation(doc).is_empty(),"Duplicate channel assignments are rejected")
	doc = settings.document()
	doc.input.sensitivity = "bad"
	expect(not MARCControllerSettings.validation(doc).is_empty(),"Malformed numeric import is rejected")
	settings.input.mode = 1
	settings.input.reverse.roll = true
	var path := "user://controller-test-export.json"
	expect(settings.write_document(path),"Controller settings export")
	var imported := MARCControllerSettings.new()
	var import_error := imported.import_document(path)
	expect(import_error.is_empty() and imported.input.mode == 1 and imported.input.reverse.roll,"Controller settings import round trip")
	settings.input = MARCControllerSettings.DEFAULT_INPUT.duplicate(true)
	settings.save()

	var scene = load("res://src/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var radio := VirtualRadio.new()
	var virtual_settings := VirtualSettings.new()
	virtual_settings.input = MARCControllerSettings.DEFAULT_INPUT.duplicate(true)
	scene.controller_settings = virtual_settings
	scene.gamepad = radio
	scene.controller_panel.settings = virtual_settings
	scene.controller_panel.gamepad = radio
	scene._controller_settings_changed()
	scene._manual_input()
	radio.axes.left_y = 0.0
	scene._manual_flight()
	expect(not scene.drone.armed,"USB takeoff requires throttle fully lowered")
	radio.axes.left_y = 1.0
	scene._manual_flight()
	expect(scene.drone.armed,"USB takeoff accepts low throttle")
	for _step in 150:
		await create_timer(0.1).timeout
		if scene.drone.command.is_empty(): break
	expect(scene.drone.pose().h > 35,"Virtual radio starts real physical flight")
	radio.axes.left_y = 0.0
	radio.axes.right_y = -1.0
	var start_x: float = scene.drone.global_position.x
	await create_timer(1.2).timeout
	expect(scene.drone.global_position.x > start_x + 0.15,"Pushing forward on the radio flies toward the drone nose")
	scene._joy_connection_changed(77,false)
	expect(scene.drone.landing and scene.drone.command.is_empty(),"Losing the active radio cancels motion and starts safe landing")
	scene._reset()
	scene.controller_panel.open_panel()
	scene.controller_panel.toggle_range()
	expect(scene.calibrating and scene.bridge.calibrating,"Calibration blocks manual and programmed flight")
	scene._manual_flight()
	expect(not scene.drone.armed,"Calibration cannot start motors")
	scene.controller_panel.close_panel()
	expect(not scene.calibrating and not scene.bridge.calibrating,"Closing settings cancels calibration")
	expect(scene.controller_panel.mapping_options.size() == 4 and scene.controller_panel.axis_labels.size() == 4,"Controller UI contains all mappings and live axis monitors")
	scene.competition.configure("program")
	scene.competition.prepare()
	scene.competition.begin()
	scene._manual_flight()
	expect(not scene.drone.armed,"Autonomous competition phase rejects radio takeoff")
	scene.queue_free()
	await process_frame
	print("MARC_CONTROLLER_TESTS checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
