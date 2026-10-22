extends Control
## A modal window: a card centred over the dimmed game with a title, a close button and a
## content column. Built in code in the game's style (glassy navy card, Fredoka, mint buttons).
## No class_name on purpose: new global classes change the OTA build shape, so this is
## preloaded by path.

signal closed

const FONT := preload("res://fonts/Fredoka.ttf")
const NAVY := Color(0.02, 0.14, 0.26)
const MINT := Color(0.55, 0.93, 0.72)
const GREEN := Color(0.20, 0.62, 0.32)

static var _theme: Theme

## Put the window's own controls in here.
var content: VBoxContainer
var card: PanelContainer
var _title: Label
var _center: CenterContainer
var _closable := true
var _opened_frame := -1  # the press that opened the window reaches it too: not a tap outside


func _init(title_text: String, width := 460.0, closable := true) -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	theme = ui_theme()
	mouse_filter = MOUSE_FILTER_STOP
	_closable = closable
	var dim := ColorRect.new()
	dim.color = Color(0, 0.04, 0.09, 0.6)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	add_child(dim)
	_center = CenterContainer.new()
	_center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_center)
	card = PanelContainer.new()
	card.custom_minimum_size.x = width
	_center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	card.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_title = Label.new()
	_title.text = title_text
	_title.theme_type_variation = "TitleLabel"
	_title.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(_title)
	if closable:
		var x := Button.new()
		x.text = "×"
		x.theme_type_variation = "CloseButton"
		x.custom_minimum_size = Vector2(48, 48)
		x.pressed.connect(close)
		head.add_child(x)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	col.add_child(content)


## Keeps the card above the on-screen keyboard while typing.
func _process(_delta: float) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return
	var kb := float(DisplayServer.virtual_keyboard_get_height())
	var win_h := float(DisplayServer.window_get_size().y)
	var lift := kb * get_viewport_rect().size.y / win_h if kb > 0.0 and win_h > 0.0 else 0.0
	_center.offset_bottom = -lift


## A closable window also closes on a tap anywhere outside the card.
func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:  # not _ready: windows override that
		_opened_frame = Engine.get_process_frames()


func _gui_input(event: InputEvent) -> void:
	if _closable and Engine.get_process_frames() > _opened_frame and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			and not card.get_global_rect().has_point(event.global_position):
		accept_event()
		close()


func set_title(text: String) -> void:
	_title.text = text


func close() -> void:
	closed.emit()
	queue_free()


## Shared look for every window.
static func ui_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = _weight(500)
	t.default_font_size = 24
	var bold := _weight(650)

	t.set_color("font_color", "Label", Color.WHITE)
	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", bold)
	t.set_font_size("font_size", "TitleLabel", 34)
	t.set_type_variation("MutedLabel", "Label")
	t.set_color("font_color", "MutedLabel", Color(1, 1, 1, 0.65))
	t.set_font_size("font_size", "MutedLabel", 20)
	t.set_type_variation("BigLabel", "Label")
	t.set_font("font", "BigLabel", bold)
	t.set_font_size("font_size", "BigLabel", 44)
	t.set_color("font_color", "BigLabel", MINT)

	var panel := _box(Color(NAVY.r, NAVY.g, NAVY.b, 0.94), 32, 2, Color(1, 1, 1, 0.18))
	panel.set_content_margin_all(26)
	t.set_stylebox("panel", "PanelContainer", panel)

	# Buttons: solid green; GhostButton: outlined; CloseButton: round glass.
	for v: Array in [["Button", GREEN, 0.0], ["GhostButton", Color(1, 1, 1, 0.0), 2.0], ["CloseButton", Color(1, 1, 1, 0.08), 0.0]]:
		var type: String = v[0]
		if type != "Button":
			t.set_type_variation(type, "Button")
		var base: Color = v[1]
		var radius := 24 if type == "CloseButton" else 22
		var normal := _box(base, radius, int(v[2]), Color(1, 1, 1, 0.35))
		normal.content_margin_left = 22
		normal.content_margin_right = 22
		normal.content_margin_top = 10
		normal.content_margin_bottom = 12
		var hover := normal.duplicate() as StyleBoxFlat
		hover.bg_color = base.lightened(0.12) if base.a > 0.0 else Color(1, 1, 1, 0.08)
		var pressed := normal.duplicate() as StyleBoxFlat
		pressed.bg_color = base.darkened(0.15) if base.a > 0.0 else Color(1, 1, 1, 0.14)
		var disabled := normal.duplicate() as StyleBoxFlat
		disabled.bg_color = Color(0.5, 0.55, 0.6, 0.35) if base.a > 0.0 else base
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_font("font", type, bold)
		t.set_color("font_color", type, Color.WHITE)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, Color(1, 1, 1, 0.5))
	t.set_font_size("font_size", "CloseButton", 34)
	var close_box := t.get_stylebox("normal", "CloseButton") as StyleBoxFlat
	for s in ["normal", "hover", "pressed", "hover_pressed"]:
		var b := t.get_stylebox(s, "CloseButton") as StyleBoxFlat
		b.set_content_margin_all(0)
		b.content_margin_bottom = 6
	close_box.content_margin_bottom = 6

	var edit := _box(Color(1, 1, 1, 0.10), 18, 2, Color(1, 1, 1, 0.25))
	edit.content_margin_left = 18
	edit.content_margin_right = 18
	edit.content_margin_top = 10
	edit.content_margin_bottom = 10
	var edit_focus := edit.duplicate() as StyleBoxFlat
	edit_focus.border_color = MINT
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", edit_focus)
	t.set_font_size("font_size", "LineEdit", 30)
	t.set_color("font_color", "LineEdit", Color.WHITE)
	t.set_color("font_placeholder_color", "LineEdit", Color(1, 1, 1, 0.4))
	t.set_color("caret_color", "LineEdit", MINT)
	t.set_color("selection_color", "LineEdit", Color(MINT.r, MINT.g, MINT.b, 0.35))

	var grab := _box(Color(1, 1, 1, 0.35), 4, 0, Color.WHITE)
	grab.content_margin_left = 6
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	var track := _box(Color(1, 1, 1, 0.06), 4, 0, Color.WHITE)
	track.content_margin_left = 6
	t.set_stylebox("scroll", "VScrollBar", track)
	_theme = t
	return t


static func _weight(w: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = FONT
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): w}
	return f


static func _box(bg: Color, radius: int, border: int, border_color: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.set_corner_radius_all(radius)
	b.set_border_width_all(border)
	b.border_color = border_color
	b.anti_aliasing = true
	return b
