class_name LocalHttpServer
extends RefCounted

const MIME_TYPES := {
	"html": "text/html; charset=utf-8",
	"css": "text/css; charset=utf-8",
	"js": "text/javascript; charset=utf-8",
	"mjs": "text/javascript; charset=utf-8",
	"woff": "font/woff",
	"woff2": "font/woff2",
	"mp3": "audio/mpeg",
	"wav": "audio/wav",
	"svg": "image/svg+xml",
	"png": "image/png",
	"json": "application/json; charset=utf-8",
}

var server := TCPServer.new()
var clients: Array[Dictionary] = []
var port := 41730
var ws_port := 41731
var debug_token := ""
var debug_session_id := ""
var scratch_port := 41850
var scratch_token := ""
var external_root := ""

func start(preferred_port: int, websocket_port: int) -> Error:
	ws_port = websocket_port
	for candidate in range(preferred_port, preferred_port + 10):
		var error := server.listen(candidate, "0.0.0.0")
		if error == OK:
			port = candidate
			return OK
	return ERR_CANT_CREATE

func stop() -> void:
	for client in clients:
		var peer: StreamPeerTCP = client.peer
		peer.disconnect_from_host()
	clients.clear()
	server.stop()

func poll() -> void:
	while server.is_connection_available():
		var peer := server.take_connection()
		if peer:
			peer.set_no_delay(true)
			clients.append({"peer": peer, "request": PackedByteArray(), "started": Time.get_ticks_msec(), "response":PackedByteArray(), "sent":0})
	for index in range(clients.size() - 1, -1, -1):
		var client: Dictionary = clients[index]
		var peer: StreamPeerTCP = client.peer
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			if not client.response.is_empty():
				var bytes: PackedByteArray = client.response
				var offset := int(client.sent)
				var result := peer.put_partial_data(bytes.slice(offset, mini(offset + 262144, bytes.size())))
				if result[0] != OK:
					peer.disconnect_from_host()
					clients.remove_at(index)
				else:
					client.sent = offset + int(result[1])
					clients[index] = client
					if int(client.sent) >= bytes.size():
						peer.disconnect_from_host()
						clients.remove_at(index)
				continue
			var available := peer.get_available_bytes()
			if available > 0:
				var read_result := peer.get_data(available)
				if read_result[0] == OK:
					client.request.append_array(read_result[1])
					clients[index] = client
					if client.request.get_string_from_utf8().contains("\r\n\r\n"):
						_serve(peer, client.request.get_string_from_utf8())
					elif client.request.size() > 8192:
						peer.disconnect_from_host()
						clients.remove_at(index)
		elif peer.get_status() in [StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE] or Time.get_ticks_msec() - int(client.started) > 3000:
			peer.disconnect_from_host()
			clients.remove_at(index)

func _serve(peer: StreamPeerTCP, request: String) -> void:
	var first_line := request.split("\r\n", false, 1)[0]
	var pieces := first_line.split(" ")
	if pieces.size() < 2 or pieces[0] != "GET":
		_send(peer, 405, "text/plain; charset=utf-8", "Method not allowed".to_utf8_buffer())
		return
	var route := pieces[1].split("?", true, 1)[0]
	if route == "/health":
		_send(peer, 200, MIME_TYPES.json, JSON.stringify({"ok": true, "protocol_version": 1}).to_utf8_buffer())
		return
	if route == "/config.json":
		_send(peer, 200, MIME_TYPES.json, JSON.stringify({"protocol_version": 1, "ws_port": ws_port}).to_utf8_buffer())
		return
	if route == "/scratch/config.json":
		if peer.get_connected_host() not in ["127.0.0.1", "::1", "::ffff:127.0.0.1"]:
			_send(peer, 403, "text/plain", "Local editor only".to_utf8_buffer())
			return
		_send(peer, 200, MIME_TYPES.json, JSON.stringify({"ws_port":scratch_port,"token":scratch_token}).to_utf8_buffer())
		return
	if route == "/debug/pairing.json" and OS.is_debug_build():
		_send(peer, 200, MIME_TYPES.json, JSON.stringify({"token": debug_token, "session_id": debug_session_id, "ws_port": ws_port}).to_utf8_buffer())
		return
	if route == "/":
		route = "/index.html"
	if ".." in route or not route.begins_with("/"):
		_send(peer, 400, "text/plain; charset=utf-8", "Bad request".to_utf8_buffer())
		return
	var path := "res://web/controller" + route
	if route.begins_with("/scratch/"):
		if route == "/scratch/":
			route = "/scratch/index.html"
		path = "res://web" + route
		if not external_root.is_empty():
			path = external_root + route
	elif route.begins_with("/examples/"):
		path = "res:/" + route
	if not FileAccess.file_exists(path):
		_send(peer, 404, "text/plain; charset=utf-8", "Not found".to_utf8_buffer())
		return
	var extension := path.get_extension().to_lower()
	var extra := ""
	if request.to_lower().contains("accept-encoding:") and request.contains("gzip") and FileAccess.file_exists(path + ".gz"):
		path += ".gz"
		extra = "Content-Encoding: gzip\r\n"
	_send(peer, 200, String(MIME_TYPES.get(extension, "application/octet-stream")), FileAccess.get_file_as_bytes(path), extra)

func _send(peer: StreamPeerTCP, status: int, content_type: String, body: PackedByteArray, extra := "") -> void:
	var reason := "OK" if status == 200 else ("Not Found" if status == 404 else "Error")
	var headers := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n%sConnection: close\r\n\r\n" % [status, reason, content_type, body.size(), extra]
	var response := headers.to_utf8_buffer()
	response.append_array(body)
	for index in clients.size():
		if clients[index].peer == peer:
			clients[index].response = response
			clients[index].sent = 0
			return
