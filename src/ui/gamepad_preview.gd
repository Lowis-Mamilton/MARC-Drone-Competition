class_name GamepadPreview
extends Control

const BACKGROUND := Color("101b25")
const RING := Color("3b5160")
const GRID := Color("263b49")
const RAW := Color("8fa3b0")
const OUTPUT := Color("57d9ff")
const TEXT := Color("b7c5cf")

var raw_left := Vector2.ZERO
var raw_right := Vector2.ZERO
var output_left := Vector2.ZERO
var output_right := Vector2.ZERO
var connected := false

func _ready() -> void:
	custom_minimum_size = Vector2(0, 160)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_text = "灰圈為原始輸入，藍點為校正後輸入。"

func set_sticks(raw_axes: Dictionary, output_axes: Dictionary, is_connected: bool) -> void:
	raw_left = Vector2(float(raw_axes.get("left_x", 0.0)), float(raw_axes.get("left_y", 0.0)))
	raw_right = Vector2(float(raw_axes.get("right_x", 0.0)), float(raw_axes.get("right_y", 0.0)))
	output_left = Vector2(float(output_axes.get("left_x", 0.0)), float(output_axes.get("left_y", 0.0)))
	output_right = Vector2(float(output_axes.get("right_x", 0.0)), float(output_axes.get("right_y", 0.0)))
	connected = is_connected
	queue_redraw()

func _draw() -> void:
	draw_style_box(_panel_style(), Rect2(Vector2.ZERO, size))
	var radius := minf(55.0, (size.x - 54.0) * 0.25)
	var center_y := 62.0
	_draw_stick(Vector2(size.x * 0.27, center_y), radius, raw_left, output_left, "左搖桿")
	_draw_stick(Vector2(size.x * 0.73, center_y), radius, raw_right, output_right, "右搖桿")
	if not connected:
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(0, 150), "連接遙控器即可預覽搖桿輸入", HORIZONTAL_ALIGNMENT_CENTER, size.x, 10, TEXT)

func _draw_stick(center: Vector2, radius: float, raw: Vector2, output: Vector2, label: String) -> void:
	draw_circle(center, radius, Color("0a1219"))
	draw_circle(center, radius, RING, false, 2.0, true)
	draw_circle(center, radius * 0.52, GRID, false, 1.0, true)
	draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), GRID, 1.0)
	draw_line(center - Vector2(0, radius), center + Vector2(0, radius), GRID, 1.0)
	var raw_position := center + raw.limit_length(1.0) * radius
	var output_position := center + output.limit_length(1.0) * radius
	draw_circle(raw_position, 7.0, RAW, false, 2.0, true)
	draw_line(center, output_position, Color("57d9ff66"), 3.0, true)
	draw_circle(output_position, 8.0, OUTPUT)
	draw_circle(output_position, 3.0, Color.WHITE)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(center.x - radius, center.y + radius + 21.0), label, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 10, TEXT)

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BACKGROUND
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = GRID
	return style
