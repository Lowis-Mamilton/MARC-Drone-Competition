class_name MARCControllerPanel
extends PanelContainer

signal settings_changed
signal calibration_changed(capturing: bool)
signal notice(message: String)

const AXIS_NAMES := {"left_x":"左搖桿 X","left_y":"左搖桿 Y","right_x":"右搖桿 X","right_y":"右搖桿 Y"}
const CHANNEL_NAMES := {"throttle":"油門／升降","yaw":"轉向","pitch":"前後","roll":"左右"}
var settings: MARCControllerSettings
var gamepad: DesktopGamepadInput
var drone: MARCDrone
var bridge: MARCBridge
var source_option: OptionButton
var device_option: OptionButton
var mode_option: OptionButton
var preview: GamepadPreview
var calibration_status: Label
var connection_status: Label
var range_button: Button
var center_button: Button
var reset_calibration_button: Button
var output_status: Label
var axis_labels: Dictionary = {}
var mapping_options: Dictionary = {}
var reverse_options: Dictionary = {}
var editable: Array[Control] = []
var deadzone: SpinBox
var sensitivity: SpinBox
var custom_grid: GridContainer
var capturing := false
var capture_device := -1
var syncing := false
var device_signature := ""
var monitor_clock := 0.0
var setup_tabs: TabContainer
var phone_url: LineEdit
var phone_qr: TextureRect
var network_option: OptionButton

func setup(next_settings: MARCControllerSettings, next_gamepad: DesktopGamepadInput, next_drone: MARCDrone, next_bridge: MARCBridge) -> void:
	settings = next_settings
	gamepad = next_gamepad
	drone = next_drone
	bridge = next_bridge
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 12
	offset_right = -12
	offset_top = 12
	offset_bottom = -12
	z_index = 20
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 10)
	add_child(shell)
	var heading := HBoxContainer.new()
	shell.add_child(heading)
	var title := label("遙控器設定", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	button(heading, "完成／關閉", close_panel)
	connection_status = label("", 14)
	shell.add_child(connection_status)
	setup_tabs = TabContainer.new()
	setup_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(setup_tabs)
	var connect_tab := tab("連線與校正")
	connect_tab.add_child(label("控制來源（自動：手機 → 遙控器 → 鍵盤）", 15))
	source_option = OptionButton.new()
	for text in ["自動選擇","鍵盤","USB／藍牙遙控器","手機"]: source_option.add_item(text)
	connect_tab.add_child(source_option)
	editable.append(source_option)
	source_option.item_selected.connect(func(index: int):
		if syncing: return
		settings.source = ["auto","keyboard","gamepad","phone"][index]
		commit()
	)
	connect_tab.add_child(label("指定遙控器", 15))
	device_option = OptionButton.new()
	device_option.fit_to_longest_item = false
	device_option.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	connect_tab.add_child(device_option)
	editable.append(device_option)
	device_option.item_selected.connect(func(index: int):
		if syncing: return
		var id := int(device_option.get_item_metadata(index))
		if id < 0: return
		settings.select_device(id)
		settings.source = "gamepad"
		gamepad.prime_button_state(id)
		commit()
		sync_form()
	)
	preview = GamepadPreview.new()
	connect_tab.add_child(preview)
	connect_tab.add_child(label("灰圈：原始輸入　藍點：校正後輸入", 13))
	calibration_status = label("1. 放開會回中的軸，擷取中心。\n2. 開始行程校正，將所有軸推至兩端，再完成儲存。", 14)
	connect_tab.add_child(calibration_status)
	var actions := HBoxContainer.new()
	connect_tab.add_child(actions)
	center_button = button(actions, "① 擷取中心", capture_center)
	range_button = button(actions, "② 開始行程校正", toggle_range)
	reset_calibration_button = button(connect_tab, "還原此裝置校正", reset_calibration)
	var axis_grid := GridContainer.new()
	axis_grid.columns = 2
	connect_tab.add_child(axis_grid)
	for axis in DesktopGamepadInput.AXIS_SOURCES:
		var item := label("", 12)
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		axis_grid.add_child(item)
		axis_labels[axis] = item
	output_status = label("", 14)
	connect_tab.add_child(output_status)
	var sticks := tab("搖桿設定")
	sticks.add_child(label("Mode 2：左手升降／轉向，右手前後／左右。\nMode 1：右手升降／左右，左手前後／轉向。", 14))
	mode_option = OptionButton.new()
	for text in ["Mode 1","Mode 2","自訂通道"]: mode_option.add_item(text)
	sticks.add_child(mode_option)
	editable.append(mode_option)
	mode_option.item_selected.connect(func(index: int):
		if syncing: return
		settings.input.mode = index + 1
		commit()
		sync_form()
	)
	custom_grid = GridContainer.new()
	custom_grid.columns = 2
	custom_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sticks.add_child(custom_grid)
	for channel in MARCControllerSettings.CHANNELS:
		var channel_label := label(CHANNEL_NAMES[channel], 14)
		channel_label.custom_minimum_size.x = 140
		custom_grid.add_child(channel_label)
		var option := OptionButton.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for axis in DesktopGamepadInput.AXIS_SOURCES: option.add_item(AXIS_NAMES[axis])
		custom_grid.add_child(option)
		mapping_options[channel] = option
		editable.append(option)
		option.item_selected.connect(func(index: int, target: String = channel):
			if syncing: return
			var axis: String = DesktopGamepadInput.AXIS_SOURCES[index]
			var previous: String = settings.input.mapping[target]
			for other in MARCControllerSettings.CHANNELS:
				if other != target and settings.input.mapping[other] == axis:
					settings.input.mapping[other] = previous
			settings.input.mapping[target] = axis
			commit()
			sync_form()
		)
	var numeric := GridContainer.new()
	numeric.columns = 2
	numeric.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sticks.add_child(numeric)
	var deadzone_label := label("搖桿死區", 15)
	deadzone_label.custom_minimum_size.x = 140
	numeric.add_child(deadzone_label)
	deadzone = number_field(numeric, 0, 0.25, 0.005)
	deadzone.value_changed.connect(func(value: float):
		if syncing: return
		settings.input.deadzone = value
		commit()
	)
	var sensitivity_label := label("靈敏度（倍數）", 15)
	sensitivity_label.custom_minimum_size.x = 140
	numeric.add_child(sensitivity_label)
	sensitivity = number_field(numeric, 0.25, 2, 0.05)
	sensitivity.value_changed.connect(func(value: float):
		if syncing: return
		settings.input.sensitivity = value
		commit()
	)
	for channel in MARCControllerSettings.CHANNELS:
		var check := CheckBox.new()
		check.text = CHANNEL_NAMES[channel] + "反向"
		sticks.add_child(check)
		reverse_options[channel] = check
		editable.append(check)
		check.toggled.connect(func(value: bool, target: String = channel):
			if syncing: return
			settings.input.reverse[target] = value
			commit()
		)
	sticks.add_child(label("設定自動儲存；自訂通道會交換重複軸，避免一軸控制兩個通道。\n升降搖桿在中央為懸停，上推上升、下推下降。USB 遙控器起飛前請先將油門降到底。", 14))
	var files := HBoxContainer.new()
	sticks.add_child(files)
	editable.append(button(files, "匯出設定 JSON", func(): file_dialog(false)))
	editable.append(button(files, "匯入設定 JSON", func(): file_dialog(true)))
	editable.append(button(sticks, "還原搖桿設定（Mode 2）", func():
		settings.input = MARCControllerSettings.DEFAULT_INPUT.duplicate(true)
		commit()
		sync_form()
	))
	var phone := tab("手機與按鍵")
	phone.add_child(label("手機與電腦連接同一個 Wi-Fi，掃描下方 QR Code。\n搖桿模式、反向、死區與靈敏度會與此處同步。", 14))
	network_option = OptionButton.new()
	network_option.fit_to_longest_item = false
	phone.add_child(network_option)
	network_option.item_selected.connect(func(index: int):
		ControlServer.select_address(network_option.get_item_text(index))
		update_phone_qr()
	)
	button(phone, "重新整理電腦網路位址", refresh_network)
	phone_url = LineEdit.new()
	phone_url.editable = false
	phone.add_child(phone_url)
	phone_qr = TextureRect.new()
	phone_qr.custom_minimum_size = Vector2(180,180)
	phone_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	phone_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	phone.add_child(phone_qr)
	phone.add_child(label("① 手機與電腦使用同一個 Wi-Fi，掃描上方 QR Code。\n② 在電腦按「完成／關閉」，手機橫放後按「起飛」。\n③ 起飛後升降搖桿自動置中；上推上升、下推下降、中央懸停。\n④ 右搖桿前後左右，左搖桿橫向轉向；按「降落」返回地面。\n模式預設為 Mode 2，可在「搖桿設定」切換。", 14))
	refresh_network()
	phone.add_child(label("Xbox A／PS ×：起飛或降落\nXbox B／PS ○：切換視角\nMenu／Options：重置\n\n鍵盤：Space 起降、W/S 前後、A/D 左右、Q/E 轉向、R/F 升降。\nMARC 使用定位懸停；放開方向搖桿後煞停。\n遙控＋程式組：第一階段可遙控，第二階段改用積木。\n正式自主階段不接受即時遙控。", 15))
	sync_form()
	refresh_devices()
	hide()

func label(text: String, font_size: int) -> Label:
	var result := Label.new()
	result.text = text
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_font_size_override("font_size", font_size)
	return result

func button(parent: Node, text: String, action: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.pressed.connect(action)
	parent.add_child(result)
	return result

func number_field(parent: Node, minimum: float, maximum: float, step: float) -> SpinBox:
	var field := SpinBox.new()
	field.min_value = minimum
	field.max_value = maximum
	field.step = step
	field.custom_minimum_size = Vector2(160, 40)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(field)
	editable.append(field)
	return field

func tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	setup_tabs.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	return body

func commit() -> void:
	if not settings.save(): notice.emit("遙控器設定無法儲存")
	settings_changed.emit()

func sync_form() -> void:
	syncing = true
	source_option.select(["auto","keyboard","gamepad","phone"].find(settings.source))
	mode_option.select(int(settings.input.mode) - 1)
	deadzone.value = float(settings.input.deadzone)
	sensitivity.value = float(settings.input.sensitivity)
	custom_grid.visible = int(settings.input.mode) == 3
	for channel in MARCControllerSettings.CHANNELS:
		mapping_options[channel].select(DesktopGamepadInput.AXIS_SOURCES.find(settings.input.mapping[channel]))
		reverse_options[channel].button_pressed = bool(settings.input.reverse[channel])
	syncing = false

func refresh_devices() -> void:
	syncing = true
	device_option.clear()
	for id in Input.get_connected_joypads():
		device_option.add_item("%s · 裝置 %d" % [Input.get_joy_name(id),id + 1])
		device_option.set_item_metadata(device_option.item_count - 1, id)
		if id == settings.selected_device(): device_option.select(device_option.item_count - 1)
	if device_option.item_count == 0 or settings.selected_device() < 0:
		device_option.add_item("尚未連接遙控器" if settings.device_name.is_empty() else settings.device_name + "（已斷線）")
		device_option.set_item_metadata(device_option.item_count - 1, -1)
		device_option.select(device_option.item_count - 1)
	syncing = false

func open_panel(tab_name := "controller") -> void:
	sync_form()
	refresh_devices()
	if tab_name == "phone":
		setup_tabs.current_tab = 2
		refresh_network()
	else: setup_tabs.current_tab = 0
	show()
	move_to_front()

func close_panel() -> void:
	cancel_calibration()
	var id := settings.selected_device()
	if id >= 0: gamepad.prime_button_state(id)
	hide()

func can_calibrate() -> bool:
	return not drone.armed and not bridge.running and settings.selected_device() >= 0

func throttle_axis() -> String:
	return String(DesktopGamepadInput.mapping_for_config(settings.input).throttle)

func capture_center() -> void:
	if not can_calibrate() or capturing: return
	gamepad.capture_center(settings.selected_device(), throttle_axis())
	calibration_status.text = "中心已儲存（油門軸使用完整行程，不必回中）。接著校正兩端行程。"

func toggle_range() -> void:
	if not can_calibrate(): return
	if capturing:
		var result := gamepad.finish_range_calibration(capture_device, throttle_axis())
		capturing = false
		capture_device = -1
		calibration_changed.emit(false)
		range_button.text = "② 開始行程校正"
		calibration_status.text = "行程校正已儲存，請檢查所有藍點可到達兩端。" if result.ok else "部分軸行程不足，原校正值保留；請將所有搖桿推至兩端後重試。"
		gamepad.prime_button_state(settings.selected_device())
	else:
		capture_device = settings.selected_device()
		gamepad.begin_range_calibration(capture_device)
		capturing = true
		calibration_changed.emit(true)
		range_button.text = "完成並儲存行程"
		calibration_status.text = "校正中：慢慢轉動左右搖桿至每個端點，再按「完成並儲存行程」。"

func cancel_calibration() -> void:
	if not capturing: return
	gamepad.cancel_range_calibration()
	capturing = false
	capture_device = -1
	calibration_changed.emit(false)
	range_button.text = "② 開始行程校正"
	calibration_status.text = "行程校正已取消，原校正值保留。"

func reset_calibration() -> void:
	if not can_calibrate() or capturing: return
	gamepad.reset_calibration(settings.selected_device())
	calibration_status.text = "已還原此裝置校正為 −1／0／+1。"

func _process(delta: float) -> void:
	if not visible or not is_instance_valid(settings) or not is_instance_valid(source_option): return
	if capturing: gamepad.capture_range_sample(capture_device)
	monitor_clock += delta
	if monitor_clock < 0.05: return
	monitor_clock = 0.0
	var pads := Input.get_connected_joypads()
	var signature := str(pads)
	for id in pads: signature += Input.get_joy_guid(id) + Input.get_joy_name(id)
	if signature != device_signature:
		device_signature = signature
		if capturing and capture_device not in pads: cancel_calibration()
		refresh_devices()
	var id := settings.selected_device()
	var locked := drone.armed or bridge.running
	connection_status.text = "先降落並停止積木程式，才能修改設定。" if locked else ("校正中，飛行輸入已暫停。" if capturing else "設定自動儲存；USB／藍牙連線後會自動出現在裝置清單。")
	for control in editable:
		if control is BaseButton: control.disabled = locked or capturing or (control == device_option and pads.is_empty())
		elif control is SpinBox: control.editable = not locked and not capturing
	center_button.disabled = locked or capturing or id < 0
	range_button.disabled = locked or id < 0
	reset_calibration_button.disabled = locked or capturing or id < 0
	if id < 0:
		preview.set_sticks({}, {}, false)
		output_status.text = "尚未偵測到遙控器。請以 USB／藍牙連線。"
		for axis in axis_labels: axis_labels[axis].text = AXIS_NAMES[axis] + "：—"
		return
	var raw := gamepad.raw_axes(id)
	var calibrated := gamepad.calibrated_axes(id, throttle_axis())
	preview.set_sticks(raw, calibrated, true)
	var calibration := gamepad.calibration_for(id)
	for axis in axis_labels:
		var range_data: Dictionary = calibration[axis]
		axis_labels[axis].text = "%s　原始 %+.2f／校正 %+.2f\n最小 %+.2f／中心 %+.2f／最大 %+.2f" % [AXIS_NAMES[axis],raw[axis],calibrated[axis],range_data.min,range_data.center,range_data.max]
	var frame := MARCControllerSettings.adjusted_frame(gamepad.sample_frame(id, settings.input, &"angle"), settings.input)
	output_status.text = "通道輸出：升降 %3.0f%%／轉向 %+.2f／前後 %+.2f／左右 %+.2f" % [frame.throttle * 100,frame.yaw,frame.pitch,frame.roll]

func file_dialog(importing: bool) -> void:
	if drone.armed or bridge.running or capturing: return
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE if importing else FileDialog.FILE_MODE_SAVE_FILE
	dialog.add_filter("*.json", "遙控器設定")
	dialog.current_file = "MARC-controller.json"
	add_child(dialog)
	dialog.file_selected.connect(func(path: String):
		if drone.armed or bridge.running or capturing:
			notice.emit("飛行或校正中無法變更設定")
		elif importing:
			var error := settings.import_document(path)
			if error.is_empty():
				sync_form()
				refresh_devices()
				settings_changed.emit()
				notice.emit("遙控器設定已匯入")
			else: notice.emit(error)
		else:
			notice.emit("遙控器設定已匯出" if settings.write_document(path) else "無法匯出設定")
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.9)

func refresh_network() -> void:
	network_option.clear()
	var addresses := ControlServer.private_addresses()
	for address in addresses: network_option.add_item(address)
	if addresses.is_empty():
		network_option.add_item(ControlServer.local_address)
	else:
		var index := addresses.find(ControlServer.local_address)
		network_option.select(maxi(0, index))
		ControlServer.select_address(network_option.get_item_text(network_option.selected))
	update_phone_qr()

func update_phone_qr() -> void:
	phone_url.text = ControlServer.pairing_url
	var qr = load("res://addons/kenyoni/qr_code/qr_code.gd").new()
	qr.put_byte(ControlServer.pairing_url.to_utf8_buffer())
	phone_qr.texture = ImageTexture.create_from_image(qr.generate_image(qr.encode(), 4))
