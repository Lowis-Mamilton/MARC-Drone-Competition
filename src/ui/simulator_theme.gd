class_name SimulatorTheme
extends RefCounted

const COLORS := {
	"background": Color("0b1219"),
	"panel": Color("111d28"),
	"panel_alt": Color("1b2c39"),
	"line": Color("304451"),
	"mint": Color("b8ef77"),
	"blue": Color("7dcfff"),
	"red": Color("ff8291"),
	"text": Color("f0f5f7"),
	"muted": Color("a4b6c4"),
}

static func box(color: Color, radius: int = 10, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1)
	style.border_color = border
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

static func create() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 15
	for type in ["Label", "Button", "OptionButton", "CheckBox", "LineEdit", "PopupMenu"]:
		theme.set_color("font_color", type, COLORS.text)
	for type in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type, box(COLORS.panel_alt, 9, COLORS.line))
		theme.set_stylebox("hover", type, box(Color("293f4b"), 9, COLORS.muted))
		theme.set_stylebox("pressed", type, box(Color("304533"), 9, COLORS.mint))
		theme.set_stylebox("disabled", type, box(Color("14212b"), 9, Color("263642")))
		theme.set_stylebox("focus", type, box(Color.TRANSPARENT, 9, COLORS.mint))
		theme.set_color("font_hover_color", type, COLORS.text)
		theme.set_color("font_pressed_color", type, COLORS.mint)
		theme.set_color("font_disabled_color", type, Color("667d8d"))
	theme.set_stylebox("normal", "LineEdit", box(COLORS.background, 8, COLORS.line))
	theme.set_stylebox("focus", "LineEdit", box(COLORS.background, 8, COLORS.mint))
	theme.set_stylebox("read_only", "LineEdit", box(COLORS.background, 8, COLORS.line))
	theme.set_stylebox("panel", "PopupMenu", box(COLORS.panel, 10, COLORS.line))
	theme.set_stylebox("hover", "PopupMenu", box(COLORS.panel_alt, 6))
	theme.set_stylebox("panel", "TooltipPanel", box(COLORS.panel_alt, 6, COLORS.line))
	theme.set_color("font_color", "TooltipLabel", COLORS.text)
	for entry in [["scroll", Color("15232e")], ["grabber", COLORS.line], ["grabber_highlight", COLORS.muted], ["grabber_pressed", COLORS.mint]]:
		var scrollbar := box(entry[1], 3)
		scrollbar.content_margin_left = 3
		scrollbar.content_margin_right = 3
		scrollbar.content_margin_top = 0
		scrollbar.content_margin_bottom = 0
		theme.set_stylebox(entry[0], "VScrollBar", scrollbar)
	var separator := StyleBoxLine.new()
	separator.color = COLORS.line
	theme.set_stylebox("separator", "HSeparator", separator)
	return theme
