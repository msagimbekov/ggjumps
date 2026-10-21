extends Button
## A quiet text link for the windows: small muted text with an "opens outside the game" icon
## (a box with an arrow leaving it) after it, centred, brighter while pressed. `url` opens in
## the phone's browser when tapped.

const SIZE := 20
const ICON := 15.0
const GAP := 7.0

var url := ""

var _font: Font


func _init(label: String, link: String) -> void:
	url = link
	tooltip_text = link
	flat = true
	focus_mode = FOCUS_NONE
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	custom_minimum_size.y = 40
	_font = preload("res://scripts/ui/modal.gd").ui_theme().default_font
	text = ""  # drawn below, with the icon
	set_meta("label", label)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	pressed.connect(func(): OS.shell_open(url))
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func _draw() -> void:
	var label: String = get_meta("label")
	var col := Color(1, 1, 1, 0.95 if is_pressed() else 0.65)
	var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
	var x := (size.x - w - GAP - ICON) * 0.5
	var base := size.y * 0.5 + _font.get_ascent(SIZE) * 0.5 - 2.0
	draw_string(_font, Vector2(x, base), label, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, col)
	# Underline, like a link.
	draw_line(Vector2(x, base + 3.0), Vector2(x + w, base + 3.0), Color(col, col.a * 0.6), 1.5, true)
	# Icon: an open box (top-right corner missing) with an arrow out of that corner.
	var o := Vector2(x + w + GAP, size.y * 0.5 - ICON * 0.5)
	var s := ICON
	var pts := PackedVector2Array([o + Vector2(s * 0.45, 0), o, o + Vector2(0, s), o + Vector2(s, s), o + Vector2(s, s * 0.55)])
	draw_polyline(pts, col, 1.8, true)
	draw_line(o + Vector2(s * 0.4, s * 0.6), o + Vector2(s, 0), col, 1.8, true)
	draw_polyline(PackedVector2Array([o + Vector2(s * 0.55, 0), o + Vector2(s, 0), o + Vector2(s, s * 0.45)]), col, 1.8, true)
