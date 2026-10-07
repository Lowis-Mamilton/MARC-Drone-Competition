class_name MARCBridge
extends Node

signal status_changed(message: String)
signal reset_requested
signal controller_setup_requested(tab_name: String)
var calibrating := false
var websocket := BrowserWebSocketServer.new()
var port := 41850
var token := ""
var controller_peer := 0
var last_heartbeat := 0
var last_status := 0
var running := false
var queue: Array[Dictionary] = []
var seen: Dictionary = {}
var active_id := ""
var stopping := false
var drone: MARCDrone
var arena: MARCArena
var competition: MARCCompetition

func _ready() -> void:
	token = Crypto.new().generate_random_bytes(16).hex_encode()
	for candidate in range(41850, 41860):
		if websocket.start(candidate) == OK:
			port = candidate
			break
	websocket.text_received.connect(_receive)
	websocket.peer_disconnected.connect(_disconnect)
	drone.command_completed.connect(_completed)
	competition.phase_changed.connect(_phase_changed)
	if not websocket.server.is_listening():
		status_changed.emit("Scratch 連線埠無法啟動")

func _exit_tree() -> void:
	websocket.stop()

func _process(_delta: float) -> void:
	websocket.poll()
	var now := Time.get_ticks_msec()
	if controller_peer != 0 and now - last_heartbeat > 3000:
		_disconnect(controller_peer)
	if controller_peer != 0 and now - last_status >= 100:
		_send(controller_peer, {"type":"status","state":snapshot()})
		last_status = now
	if running and active_id.is_empty() and not queue.is_empty():
		var next: Dictionary = queue.pop_front()
		active_id = String(next.id)
		if next.op == "finish":
			var ok := competition.request_finish()
			_completed(active_id, ok, "比賽結束" if ok else "須先降落並靜止 0.5 秒")
		else:
			drone.accept_command(next)

func snapshot() -> Dictionary:
	var value := drone.pose()
	var sense := arena.sensor_at(drone.global_position)
	value["color"] = sense.color
	value["card"] = sense.id
	value["state"] = competition.state
	value["stage"] = competition.stage + 1
	value["remaining"] = competition.remaining
	value["score"] = 0 if competition.major_zero else int(competition.scores[0]) + (0 if competition.zero_stage_two else int(competition.scores[1]))
	value["running"] = running
	return value

func _receive(peer: int, raw: String) -> void:
	var message: Variant = JSON.parse_string(raw)
	if not message is Dictionary:
		return
	var id := String(message.get("id", ""))
	var kind := String(message.get("type", ""))
	if kind == "hello":
		var address := websocket.get_peer_address(peer)
		if address not in ["127.0.0.1", "::1", "::ffff:127.0.0.1"] or String(message.get("token", "")) != token:
			_reply(peer, id, false, "Scratch 僅允許本機配對")
		elif controller_peer != 0 and controller_peer != peer:
			_reply(peer, id, false, "已有其他 Scratch 編輯器取得控制權")
		else:
			controller_peer = peer
			last_heartbeat = Time.get_ticks_msec()
			_reply(peer, id, true, "Scratch 已連線")
			status_changed.emit("Scratch 已連線")
		return
	if peer != controller_peer:
		_reply(peer, id, false, "請先連線")
		return
	if kind == "ping":
		last_heartbeat = Time.get_ticks_msec()
		return
	if kind == "controller_settings":
		controller_setup_requested.emit(String(message.get("tab", "controller")))
		_reply(peer, id, true, "遙控器設定已開啟")
		return
	if kind == "stop":
		stop_program()
		_reply(peer, id, true, "程式已停止")
		return
	if kind == "reset":
		if not competition.reset_allowed():
			_reply(peer, id, false, "目前比賽階段不可重置；第一階段須依規則由裁判處理")
			return
		reset_requested.emit()
		_reply(peer, id, true, "已重置至停機坪，積木程式保留")
		return
	if kind == "start":
		if calibrating:
			_reply(peer, id, false, "請先完成或取消遙控器校正，再執行程式")
			return
		if not competition.can_program():
			competition.referee("early")
			_reply(peer, id, false, "尚未進入程式控制時段，請先在模擬器開始比賽或切換自由練習")
			return
		stop_program()
		running = true
		drone.manual_enabled = false
		_reply(peer, id, true, "程式開始")
		return
	if kind != "command" or not running or not competition.can_program():
		_reply(peer, id, false, "程式未啟動或目前階段不可程式控制")
		return
	if id.is_empty() or seen.has(id):
		_reply(peer, id, false, "指令識別碼重複或缺漏")
		return
	if queue.size() >= 128:
		_reply(peer, id, false, "指令佇列已滿")
		return
	var validation := validate_command(message)
	if not validation.is_empty():
		_reply(peer, id, false, validation)
		return
	seen[id] = true
	queue.append(message)

func validate_command(message: Dictionary) -> String:
	var op := String(message.get("op", ""))
	if op not in ["takeoff","goto","move","turn","land","wait","led","match","finish"]:
		return "未知指令"
	if not message.get("args", {}) is Dictionary:
		return "指令參數格式錯誤"
	var timeout: Variant = message.get("timeout",30)
	if not (timeout is int or timeout is float) or not is_finite(float(timeout)) or float(timeout) <= 0 or float(timeout) > 185:
		return "動作逾時須介於 0 至 185 秒"
	var args: Dictionary = message.get("args", {})
	for key in args:
		if key == "color":
			if String(args[key]) not in MARCCourse.COLORS:
				return "不支援的 LED 顏色"
		elif not (args[key] is float or args[key] is int) or not is_finite(float(args[key])):
			return "參數須為有限數值"
	if op == "goto" and (float(args.get("x", 40)) < 10 or float(args.get("x", 40)) > 390 or float(args.get("y", 160)) < 10 or float(args.get("y", 160)) > 310 or float(args.get("h", 50)) < 0 or float(args.get("h", 50)) > 220):
		return "目的地超出安全飛行範圍"
	if op == "takeoff" and (float(args.get("h", 50)) < 10 or float(args.get("h", 50)) > 220):
		return "起飛高度須介於 10 至 220 公分"
	if op in ["goto","move","turn"] and not drone.armed and active_id.is_empty() and queue.is_empty():
		return "請先起飛"
	if op == "move" and (absf(float(args.get("x",0))) > 400 or absf(float(args.get("y",0))) > 320 or absf(float(args.get("h",0))) > 220):
		return "相對移動距離超出場地範圍"
	if op == "turn" and absf(float(args.get("degrees",0))) > 360:
		return "單次轉向須介於 −360 至 360 度"
	if op == "wait" and (float(args.get("seconds", 1)) < 0 or float(args.get("seconds", 1)) > 180):
		return "等待秒數須介於 0 至 180"
	return ""

func _completed(id: String, ok: bool, message: String) -> void:
	if id != active_id:
		return
	active_id = ""
	_reply(controller_peer, id, ok, message)
	if not ok and not stopping:
		stop_program()
		status_changed.emit(message)

func stop_program() -> void:
	if stopping:
		return
	stopping = true
	running = false
	var pending := queue.duplicate()
	queue.clear()
	for command in pending:
		_reply(controller_peer, command.id, false, "程式已停止，取消待執行指令")
	drone.cancel_commands()
	active_id = ""
	seen.clear()
	drone.manual_enabled = competition.can_manual()
	stopping = false

func _disconnect(peer: int) -> void:
	if peer != controller_peer:
		return
	stop_program()
	controller_peer = 0
	if drone.armed:
		drone.landing = true
	status_changed.emit("Scratch 已斷線，取消指令並安全降落")

func _phase_changed() -> void:
	if not competition.can_program():
		stop_program()

func _reply(peer: int, id: String, ok: bool, message: String) -> void:
	if peer != 0:
		_send(peer, {"type":"result","id":id,"ok":ok,"message":message})

func _send(peer: int, message: Dictionary) -> void:
	websocket.send_text(peer, JSON.stringify(message))
