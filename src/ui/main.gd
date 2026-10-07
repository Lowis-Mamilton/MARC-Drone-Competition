extends Node3D

var arena: MARCArena
var drone: MARCDrone
var competition := MARCCompetition.new()
var bridge: MARCBridge
var camera: Camera3D
var camera_mode := 0
var orbit_yaw := -0.95
var orbit_pitch := 0.65
var orbit_distance := 7.2
var dragging := false
var gamepad := DesktopGamepadInput.new()
var controller_settings := MARCControllerSettings.new()
var controller_panel: MARCControllerPanel
var active_source := "keyboard"
var last_source := "keyboard"
var calibrating := false
var group_option: OptionButton
var source_option: OptionButton
var tabs: TabContainer
var status_label: Label
var state_label: Label
var timer_label: Label
var score_label: Label
var pose_label: Label
var connection_label: Label
var tasks_label: RichTextLabel
var events_label: RichTextLabel
var records_label: RichTextLabel
var notice_label: Label
var notice_seconds := 0.0
var start_button: Button
var begin_button: Button
var reset_button: Button
var flight_button: Button
var color_options: Dictionary = {}
var controller_monitor: Label
var trace := ImmediateMesh.new()
var trace_points: Array[Vector3] = []
var show_trace := false
var trace_clock := 0.0
var camera_drag_hint: Label
var studio_embedded := false
var hud_clock := 0.0
var side_panel: PanelContainer

func _ready() -> void:
	studio_embedded = "--studio-embedded" in OS.get_cmdline_user_args()
	if studio_embedded:
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		get_window().content_scale_size = Vector2i.ZERO
		orbit_distance = 6.6
	arena = MARCArena.new()
	add_child(arena)
	drone = MARCDrone.new()
	drone.profile = JSON.parse_string(FileAccess.get_file_as_string("res://config/profiles/stable.json"))
	drone.profile.input = controller_settings.input.duplicate(true)
	drone.arena = arena
	add_child(drone)
	bridge = MARCBridge.new()
	bridge.drone = drone
	bridge.arena = arena
	bridge.competition = competition
	bridge.reset_requested.connect(_reset)
	bridge.controller_setup_requested.connect(_open_controller_settings)
	add_child(bridge)
	ControlServer.http.scratch_port = bridge.port
	ControlServer.http.scratch_token = bridge.token
	var external := OS.get_executable_path().get_base_dir().path_join("web")
	if FileAccess.file_exists(external.path_join("scratch/index.html")):
		ControlServer.http.external_root = external
	ControlServer.set_status_provider(_phone_status)
	ControlServer.command_received.connect(_phone_command)
	ControlServer.failsafe_triggered.connect(func(_reason: String):
		if active_source == "phone" and drone.manual_enabled and not bridge.running:
			_safe_landing("手機控制中斷，安全降落")
	)
	Input.joy_connection_changed.connect(_joy_connection_changed)
	arena.obstacle_fallen.connect(competition.prop_fallen)
	drone.body_entered.connect(_contact)
	bridge.status_changed.connect(_notice)
	competition.changed.connect(_update_scores)
	competition.phase_changed.connect(_phase_changed)
	competition.match_finished.connect(func(_result: Dictionary): _update_records())
	camera = Camera3D.new()
	camera.near = 0.025
	camera.far = 100
	camera.fov = 60 if studio_embedded else 52
	add_child(camera)
	var path_mesh := MeshInstance3D.new()
	path_mesh.mesh = trace
	path_mesh.material_override = MARCArena.material(Color("f45164"))
	add_child(path_mesh)
	_build_ui()
	_update_scores()
	_update_records()
	_phase_changed()
	print("MARC_SCRATCH_URL=http://127.0.0.1:%d/scratch/" % ControlServer.http.port)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft JhengHei UI", "Microsoft JhengHei", "Noto Sans CJK TC"])
	theme.default_font = font
	theme.default_font_size = 14 if studio_embedded else 16
	for kind in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", kind, _style(Color("20384e")))
		theme.set_stylebox("hover", kind, _style(Color("2e5570")))
		theme.set_stylebox("pressed", kind, _style(Color("147d92")))
		theme.set_stylebox("disabled", kind, _style(Color("162535")))
		theme.set_color("font_color", kind, Color("edf4fa"))
		theme.set_color("font_disabled_color", kind, Color("71869a"))
	theme.set_color("font_color", "Label", Color("d7e6ef"))
	theme.set_color("default_color", "RichTextLabel", Color("d7e6ef"))
	root.theme = theme
	var header := _panel(root, Vector2(18,18), Vector2(-18,72 if studio_embedded else 96), true)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10 if studio_embedded else 22)
	header.add_child(top)
	var title := _label("模擬飛行" if studio_embedded else "MARC  火線救援", 18 if studio_embedded else 25)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	state_label = _label("自由練習", 13 if studio_embedded else 17)
	top.add_child(state_label)
	timer_label = _label("--:--", 20 if studio_embedded else 30)
	timer_label.custom_minimum_size.x = 70 if studio_embedded else 100
	top.add_child(timer_label)
	score_label = _label("0 分", 18 if studio_embedded else 25)
	top.add_child(score_label)
	var side := _panel(root, Vector2(18,130 if studio_embedded else 110), Vector2(310 if studio_embedded else 400,-120), false, true)
	side_panel = side
	side.visible = not studio_embedded
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	side.add_child(content)
	if studio_embedded:
		_button(content, "關閉任務／設定 ×", func(): side.hide())
	group_option = OptionButton.new()
	group_option.add_item("程式控制組  ·  300 分")
	group_option.add_item("遙控＋程式組  ·  200 分")
	group_option.item_selected.connect(func(index: int):
		bridge.stop_program()
		competition.configure("program" if index == 0 else "hybrid")
		arena.set_group(index == 0)
		_reset_world()
		_update_card_controls()
	)
	content.add_child(group_option)
	var row := HBoxContainer.new()
	content.add_child(row)
	start_button = _button(row, "開始比賽", _prepare)
	_button(row, "自由練習", func():
		bridge.stop_program()
		competition.configure(competition.group)
		_reset_world()
	)
	begin_button = _button(content, "裁判口令：開始", func(): competition.begin())
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(tabs)
	var task_tab := _tab("任務")
	tasks_label = _rich(task_tab, 300)
	var scratch_tab := _tab("編程")
	_button(scratch_tab, "內建積木編程" if studio_embedded else "開啟編程工作室", _open_scratch)
	connection_label = _label("Scratch 尚未連線", 14)
	connection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scratch_tab.add_child(connection_label)
	var help := _rich(scratch_tab, 170)
	help.text = "[b]積木控制真實飛行物理[/b]\n\n1. 在自由練習測試積木。\n2. 用綠旗啟動，紅色停止鈕取消指令。\n3. 正式比賽須等裁判口令。\n\n座標與距離均為公分。高度指無人機底部距地面，穿過圓心時需扣除機身半徑 10 公分。\n\n讀色需要在色卡上方 30 公分內；LED 維持同色兩秒才判定。"
	_button(scratch_tab, "停止程式並懸停", func(): bridge.stop_program())
	_button(scratch_tab, "緊急停機", _emergency)
	var control_tab := _tab("控制")
	_button(control_tab, "完整遙控器設定", _open_controller_settings)
	flight_button = _button(control_tab, "起飛／降落  ·  Space", _manual_flight)
	reset_button = _button(control_tab, "重置至停機坪  ·  Backspace", _reset)
	controller_monitor = _label("", 14)
	controller_monitor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control_tab.add_child(controller_monitor)
	var phone_help := _label("手機控制（同一 Wi-Fi）\n" + ControlServer.pairing_url, 13)
	phone_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control_tab.add_child(phone_help)
	var qr = load("res://addons/kenyoni/qr_code/qr_code.gd").new()
	qr.put_byte(ControlServer.pairing_url.to_utf8_buffer())
	var texture := TextureRect.new()
	texture.texture = ImageTexture.create_from_image(qr.generate_image(qr.encode(), 4))
	texture.custom_minimum_size = Vector2(110,110)
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	control_tab.add_child(texture)
	var keys := _label("W/S 前後 · A/D 左右 · Q/E 轉向\nR/F 上升下降 · 放開即懸停\n手把 A 起降 · B 視角 · Menu 重置", 13)
	control_tab.add_child(keys)
	var referee_tab := _tab("裁判")
	for action in [["碰觸選手／裁判 −10", "touch_person"], ["擅自進場 −20", "enter"], ["口令前啟動 −20", "early"], ["第一階段碰觸滅火區道具 −20", "touch_stage_two"], ["未依程序介入：暫停計分", "intervention"], ["自主階段即時操控：零分", "manual_violation"], ["重大違規：回合零分", "major"], ["故障／無法再起飛", "fault"]]:
		_button(referee_tab, action[0], competition.referee.bind(action[1]))
	_button(referee_tab, "宣告結束（須降落且靜止）", func():
		if not competition.request_finish(): _notice("請先降落並完全靜止 0.5 秒")
	)
	var practice_tab := _tab("設定")
	_button(practice_tab, "練習：重新抽取色卡", func():
		if competition.state == "practice":
			arena.randomize_cards()
			_update_card_controls()
	)
	for card in arena.course.cards(true):
		var card_row := HBoxContainer.new()
		practice_tab.add_child(card_row)
		card_row.add_child(_label(card.id, 14))
		var option := OptionButton.new()
		for color_name in ["紅", "黃", "綠", "藍"]:
			option.add_item(color_name)
		if card.id != "5": option.remove_item(3)
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.item_selected.connect(func(index: int):
			if competition.state == "practice": arena.set_card(card.id, ["red","yellow","green","blue"][index])
		)
		card_row.add_child(option)
		color_options[card.id] = option
	var path_toggle := CheckButton.new()
	path_toggle.text = "顯示練習飛行路徑"
	path_toggle.toggled.connect(func(value: bool): show_trace = value; trace.clear_surfaces(); trace_points.clear())
	practice_tab.add_child(path_toggle)
	var settings_help := _label("場地尺寸與道具高度集中於\nconfig/course.json。修改後重新啟動。\n\n正式機型未指定；本模型供教學測試。", 13)
	practice_tab.add_child(settings_help)
	var records_tab := _tab("紀錄")
	records_label = _rich(records_tab, 200)
	_button(records_tab, "匯出比賽紀錄 JSON", _export_records)
	events_label = _rich(records_tab, 200)
	var footer := _panel(root, Vector2(18,-105), Vector2(-18,-18), true, true)
	var footer_content := VBoxContainer.new()
	footer.add_child(footer_content)
	pose_label = _label("", 13 if studio_embedded else 16)
	pose_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer_content.add_child(pose_label)
	status_label = _label("", 12 if studio_embedded else 13)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer_content.add_child(status_label)
	var views := HBoxContainer.new()
	views.add_theme_constant_override("separation", 5)
	views.position = Vector2(18 if studio_embedded else 422,84 if studio_embedded else 111)
	root.add_child(views)
	if studio_embedded:
		_button(views, "任務／設定", func(): side.visible = not side.visible)
	for item in [["選手視角",0],["跟隨",1],["FPV",2],["俯視",3]]:
		var view_button := _button(views, item[0], func(): camera_mode = int(item[1]))
		view_button.tooltip_text = "切換至%s；也可按 C 循環切換" % item[0]
	notice_label = _label("", 16)
	notice_label.position = Vector2(18 if studio_embedded else 430,132 if studio_embedded else 170)
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.size.x = 500
	notice_label.add_theme_color_override("font_color", Color("ffe4a2"))
	root.add_child(notice_label)
	controller_panel = MARCControllerPanel.new()
	root.add_child(controller_panel)
	controller_panel.add_theme_stylebox_override("panel", _style(Color("102039")))
	controller_panel.setup(controller_settings, gamepad, drone, bridge)
	controller_panel.settings_changed.connect(_controller_settings_changed)
	controller_panel.calibration_changed.connect(func(value: bool):
		calibrating = value
		bridge.calibrating = value
	)
	controller_panel.notice.connect(_notice)
	_update_card_controls()

func _panel(parent: Control, first: Vector2, last: Vector2, full_width := false, bottom := false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color(0.035,0.075,0.12,0.96)))
	if full_width: panel.anchor_right = 1
	if bottom:
		if first.y < 0: panel.anchor_top = 1
		panel.anchor_bottom = 1
	panel.offset_left = first.x
	panel.offset_top = first.y
	panel.offset_right = last.x
	panel.offset_bottom = last.y
	parent.add_child(panel)
	return panel

func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(9)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _label(text: String, size: int) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	return result

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.pressed.connect(callback)
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.focus_mode = Control.FOCUS_NONE
	parent.add_child(result)
	return result

func _tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 9)
	scroll.add_child(box)
	return box

func _rich(parent: Node, height: float) -> RichTextLabel:
	var result := RichTextLabel.new()
	result.bbcode_enabled = true
	result.fit_content = true
	result.custom_minimum_size = Vector2(0, height)
	result.scroll_active = false
	result.add_theme_font_size_override("normal_font_size", 15)
	parent.add_child(result)
	return result

func _prepare() -> void:
	bridge.stop_program()
	_reset_world()
	arena.randomize_cards()
	_update_card_controls()
	competition.prepare()

func _reset_world() -> void:
	drone.reset_marc()
	arena.reset_props()
	trace_points.clear()
	trace.clear_surfaces()

func _reset() -> void:
	if competition.reset_flight():
		bridge.stop_program()
		_reset_world()
		_notice("已返回停機坪；正式比賽計時持續")

func _phase_changed() -> void:
	if not is_instance_valid(drone): return
	drone.manual_enabled = competition.can_manual() and not bridge.running
	if competition.state == "transition":
		bridge.stop_program()
		_reset_world()
		_notice("交接時間：已將無人機放回停機坪中央")
	elif competition.state == "finished":
		bridge.stop_program()
		if drone.armed: drone.landing = true
	if is_instance_valid(group_option):
		group_option.disabled = competition.state in ["prepare", "active", "transition"]
		_update_card_controls()
	_update_scores()

func _manual_flight() -> void:
	if is_instance_valid(controller_panel) and controller_panel.visible:
		_notice("請先完成並關閉遙控器設定，再起飛")
		return
	if not competition.can_manual() or bridge.running or calibrating:
		_notice("目前為程式控制時段，請使用 Scratch 起降")
		return
	if drone.armed:
		drone.cancel_commands()
		drone.landing = true
	else:
		var source := controller_settings.resolved_source(ControlServer.is_controller_connected())
		var frame := DroneInputFrame.neutral()
		if source == "gamepad":
			var id := controller_settings.selected_device()
			if id < 0:
				_notice("請先連接已選擇的遙控器")
				return
			frame = MARCControllerSettings.adjusted_frame(gamepad.sample_frame(id, controller_settings.input, &"angle"), controller_settings.input)
		elif source == "phone":
			if not ControlServer.is_controller_connected():
				_notice("請先連接手機")
				return
			frame = MARCControllerSettings.adjusted_frame(ControlServer.latest_frame, controller_settings.input)
		if frame.throttle > 0.05:
			_notice("請先將油門降到底，再按起飛")
			return
		drone.accept_command({"id":"ui","op":"takeoff","args":{"h":50}})

func _safe_landing(message: String) -> void:
	drone.cancel_commands()
	drone.manual = DroneInputFrame.neutral()
	if drone.armed: drone.landing = true
	_notice(message)

func _emergency() -> void:
	bridge.stop_program()
	drone.set_armed(false)
	drone.landing = false
	_notice("緊急停機：馬達已關閉")

func _open_scratch() -> void:
	if studio_embedded:
		_notice("使用左側內建積木；上方可切換編程與場地")
		return
	var studio := ProjectSettings.globalize_path("res://.runtime/studio/MARCDroneStudio.exe")
	if not FileAccess.file_exists(studio):
		_notice("請先執行 npm run studio:build 建置內建編程介面")
		return
	if OS.create_process(studio, PackedStringArray([ProjectSettings.globalize_path("res://")])) > 0:
		get_tree().quit()

func _process(delta: float) -> void:
	_update_camera(delta)
	notice_seconds = maxf(0, notice_seconds - delta)
	hud_clock += delta
	if hud_clock >= 0.1:
		hud_clock = 0.0
		_update_hud()
	trace_clock += delta
	if show_trace and competition.state == "practice" and trace_clock > 0.12:
		trace_clock = 0
		trace_points.append(drone.global_position)
		if trace_points.size() > 1000: trace_points.pop_front()
		trace.clear_surfaces()
		if trace_points.size() > 1:
			trace.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
			for point in trace_points: trace.surface_add_vertex(point)
			trace.surface_end()

func _update_hud() -> void:
	var p := drone.pose()
	var sensed := arena.sensor_at(drone.global_position)
	pose_label.text = ("X %.1f · Y %.1f · 高 %.1f cm · %.1f cm/s\n感測 %s · LED %s" if studio_embedded else "X %5.1f   Y %5.1f   底部高度 %5.1f cm     速度 %4.1f cm/s     感測 %s     LED %s") % [p.x,p.y,p.h,p.speed,_color_name(sensed.color),_color_name(drone.led)]
	var phase := {"practice":"自由練習","prepare":"準備／檢查","active":"比賽進行","transition":"階段交接","finished":"比賽結束"}
	state_label.text = phase.get(competition.state, "") + (" · 階段 %d" % (competition.stage + 1) if competition.group == "hybrid" else "")
	timer_label.text = "--:--" if competition.state in ["practice","finished"] else "%02d:%04.1f" % [int(competition.remaining) / 60,fmod(competition.remaining,60)]
	status_label.text = "%s控制 · %s
拖曳旋轉 · 滾輪縮放 · C 視角 · %s" % [{"keyboard":"鍵盤","gamepad":"手把","phone":"手機"}.get(active_source.split(":")[0],"遙控器"),"Scratch 程式執行中" if bridge.running else "定位懸停", "須重置" if competition.suppressed else ""]
	connection_label.text = "Scratch 已連線" if bridge.controller_peer != 0 else "Scratch 尚未連線"
	begin_button.visible = competition.state == "prepare"
	start_button.disabled = competition.state in ["prepare","active","transition"]
	reset_button.disabled = not competition.reset_allowed()
	flight_button.disabled = not competition.can_manual() or bridge.running
	notice_label.visible = notice_seconds > 0
	var pad_id := controller_settings.selected_device()
	controller_monitor.text = "遙控器：" + (Input.get_joy_name(pad_id) if pad_id >= 0 else "未連接")

func _physics_process(delta: float) -> void:
	if not is_instance_valid(drone): return
	drone.manual_enabled = competition.can_manual() and not bridge.running and not calibrating
	if drone.manual_enabled:
		drone.manual = _manual_input()
	else:
		drone.manual = DroneInputFrame.neutral()
		drone.manual.throttle = 0.5
	competition.tick(delta,drone.global_position,drone.linear_velocity,drone.armed,drone.led,arena.sensor_at(drone.global_position))

func _manual_input() -> DroneInputFrame:
	var pad_id := controller_settings.selected_device()
	var source := controller_settings.resolved_source(ControlServer.is_controller_connected())
	active_source = "gamepad:%d" % pad_id if source == "gamepad" else source
	if active_source != last_source:
		if drone.armed: _safe_landing("控制來源切換，先安全降落")
		if pad_id >= 0: gamepad.prime_button_state(pad_id)
	last_source = active_source
	var neutral := DroneInputFrame.neutral()
	neutral.throttle = 0.5
	if controller_panel.visible or calibrating: return neutral
	if source == "phone":
		return MARCControllerSettings.flight_frame(ControlServer.get_input_frame(), controller_settings.input) if ControlServer.is_controller_connected() else neutral
	if source == "gamepad":
		if pad_id < 0: return neutral
		var frame := MARCControllerSettings.flight_frame(gamepad.sample_frame(pad_id, controller_settings.input, &"angle"), controller_settings.input)
		for command in gamepad.poll_commands(pad_id):
			match command:
				&"toggle_arm": _manual_flight()
				&"reset": _reset()
				&"toggle_camera": camera_mode = (camera_mode + 1) % 4
		return frame
	if source != "keyboard" or (studio_embedded and not DisplayServer.window_is_focused()): return neutral
	neutral.pitch = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	neutral.roll = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
	neutral.yaw = float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
	neutral.throttle += (float(Input.is_physical_key_pressed(KEY_R)) - float(Input.is_physical_key_pressed(KEY_F))) * 0.5
	return neutral

func _phone_command(command: StringName) -> void:
	if controller_settings.resolved_source(ControlServer.is_controller_connected()) != "phone" or calibrating or controller_panel.visible: return
	if command in [&"arm", &"toggle_arm"]: _manual_flight()
	elif command == &"reset": _reset()

func _open_controller_settings(tab_name := "controller") -> void:
	if is_instance_valid(controller_panel): controller_panel.open_panel(tab_name)

func _controller_settings_changed() -> void:
	drone.profile.input = controller_settings.input.duplicate(true)
	gamepad.clear_button_state()
	var id := controller_settings.selected_device()
	if id >= 0: gamepad.prime_button_state(id)

func _joy_connection_changed(id: int, connected: bool) -> void:
	if not connected and active_source == "gamepad:%d" % id and drone.manual_enabled and not bridge.running:
		_safe_landing("遙控器已斷線，取消移動並安全降落")
	if is_instance_valid(controller_panel):
		if not connected and controller_panel.capture_device == id: controller_panel.cancel_calibration()
		controller_panel.refresh_devices()

func _contact(body: Node) -> void:
	if competition.state == "active" and competition.group == "hybrid" and competition.stage == 0 and body.name == "Prop_6":
		competition.penalty("第一階段碰觸第二階段捷徑道具",20)

func _update_camera(_delta: float) -> void:
	var focus := Vector3(2,0.25,-1.6)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	if camera_mode in [0,1]:
		if camera_mode == 1: focus = drone.global_position
		var offset := Vector3(sin(orbit_yaw)*cos(orbit_pitch),sin(orbit_pitch),cos(orbit_yaw)*cos(orbit_pitch))*orbit_distance
		camera.position = focus + offset
		camera.look_at(focus)
	elif camera_mode == 2:
		camera.global_transform = drone.global_transform
		camera.position += -drone.global_basis.z * 0.11 + Vector3(0,0.03,0)
	else:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 5.6
		camera.position = Vector3(2.0 if studio_embedded else 1.2,7,-1.6)
		if studio_embedded:
			camera.size = maxf(5.6,5.0 / maxf(0.4,get_viewport().get_visible_rect().size.x / get_viewport().get_visible_rect().size.y))
		camera.rotation_degrees = Vector3(-90,0,0)
	# Offset world view to the right of the controls.
	camera.h_offset = (-0.4 if side_panel.visible else 0.0) if studio_embedded else (-0.65 if camera_mode != 2 else 0.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE: _manual_flight()
			KEY_BACKSPACE: _reset()
			KEY_C: camera_mode = (camera_mode + 1) % 4
			KEY_ESCAPE: _emergency()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT: dragging = event.pressed
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: orbit_distance = maxf(1.5, orbit_distance - 0.3)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: orbit_distance = minf(10, orbit_distance + 0.3)
	if event is InputEventMouseMotion and dragging:
		orbit_yaw -= event.relative.x * 0.006
		orbit_pitch = clampf(orbit_pitch + event.relative.y * 0.006,0.1,1.45)

func _update_scores() -> void:
	if not is_instance_valid(tasks_label): return
	var score := int(competition.scores[0]) + (0 if competition.zero_stage_two else int(competition.scores[1]))
	if competition.major_zero: score = 0
	score_label.text = "%d / %d 分" % [score,300 if competition.group == "program" else 200]
	var text := "[b]任務進度[/b]\n"
	for id in MARCCompetition.NAMES:
		if competition.group == "hybrid" and id in ["takeoff","combo"]: continue
		var rule := competition.points_and_limit(id)
		if id == "8":
			text += "\n⑧ 最後降落：%d 分（暫定）\n" % maxi(0, competition.last_landing)
		else:
			text += "\n%s   %d / %d" % [MARCCompetition.NAMES[id],int(competition.counts.get(id,0)),rule.y]
			if competition.cards_locked.has(id): text += "  ✓" if competition.cards_locked[id] else "  × 鎖定"
	text += "\n\n[b]方向與條件[/b]\n①A 向下 / ①B 向上\n② 逆時針 / ③ 下穿後上返\n④ 向 0 欄 / ⑥ 向 9 欄\n色卡：30 cm 內、LED 同色 2 秒\n\n重置 %d 次" % competition.resets
	tasks_label.text = text
	var event_text := "[b]本場判定紀錄[/b]\n"
	for event in competition.log:
		event_text += "\n%.1fs  %s  %+d" % [event.time,event.reason,event.points]
	events_label.text = event_text

func _update_card_controls() -> void:
	for id in color_options:
		var option: OptionButton = color_options[id]
		option.disabled = competition.state != "practice"
		option.get_parent().visible = id != "5" or competition.group == "program"
		option.select(["red","yellow","green","blue"].find(arena.card_colors.get(id,"red")))

func _update_records() -> void:
	if not is_instance_valid(records_label): return
	var text := "[b]最近三場成績[/b]\n"
	for item in competition.ranked_records():
		text += "\n[b]%d 分[/b] · %.2f 秒 · 重置 %d 次\n%s\n" % [item.score,item.time,item.resets,item.recorded]
	text += "\n程式組同分：次高場次，再比最高場時間。\n混合組同分：總飛行時間，再比次高場次。"
	records_label.text = text

func _export_records() -> void:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.add_filter("*.json", "比賽紀錄")
	dialog.current_file = "MARC-results.json"
	add_child(dialog)
	dialog.file_selected.connect(func(path: String):
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(competition.records,"\t"))
			_notice("比賽紀錄已匯出")
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.7)

func _notice(message: String) -> void:
	if not is_instance_valid(notice_label): return
	notice_label.text = message
	notice_seconds = 7

func _color_name(color: String) -> String:
	return {"red":"紅","yellow":"黃","green":"綠","blue":"藍","white":"白","off":"關閉","none":"無色卡"}.get(color,color)

func _phone_status() -> Dictionary:
	var setup_open := is_instance_valid(controller_panel) and controller_panel.visible
	var source := controller_settings.resolved_source(ControlServer.is_controller_connected())
	return {
		"altitude_m":drone.pose().h / 100.0, "speed_mps":drone.linear_velocity.length(),
		"armed":drone.armed, "flight_mode":"angle", "lesson_objective":"MARC 火線救援",
		"input_config":controller_settings.input, "input_source":source, "supported_modes":["angle"],
		"supports_turtle":false, "position_hold":true, "setup_open":setup_open,
		"manual_allowed":source == "phone" and competition.can_manual() and not bridge.running and not calibrating and not setup_open,
		"reset_allowed":competition.reset_allowed()
	}
