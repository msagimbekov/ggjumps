class_name SettingsPanel
extends Control
## Gear button in the bottom-right corner and the sound panel it opens: music and effects
## sliders, each with an icon that mutes it (tap again to bring the old volume back).
## Input comes from main.gd through handle(), before the game sees it.

const FONT := preload("res://fonts/Fredoka.ttf")
const BUTTON := 52.0
const PANEL := Vector2(300.0, 150.0)
const ICON := 44.0
const MINT := Color(0.55, 0.93, 0.72)
const INK := Color(0.02, 0.12, 0.22, 0.55)

var sound: Sound
var bottom_inset := 0.0  # home indicator / nav bar, in viewport units
var is_open := false

var _drag_row := -1  # slider being dragged: 0 music, 1 effects
var _font: FontVariation
var _pill := StyleBoxFlat.new()
var _card := StyleBoxFlat.new()


func _init() -> void:
	_font = FontVariation.new()
	_font.base_font = FONT
	_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600}
	for sb: StyleBoxFlat in [_pill, _card]:
		sb.bg_color = Color(0.02, 0.14, 0.26, 0.42)
		sb.border_color = Color(1, 1, 1, 0.18)
		sb.set_border_width_all(2)
	_pill.set_corner_radius_all(16)
	_card.bg_color = Color(0.02, 0.14, 0.26, 0.82)
	_card.set_corner_radius_all(24)


func button_rect() -> Rect2:
	return Rect2(size.x - BUTTON - 18.0, size.y - BUTTON - 18.0 - bottom_inset, BUTTON, BUTTON)


func panel_rect() -> Rect2:
	var b := button_rect()
	return Rect2(b.end.x - PANEL.x, b.position.y - 12.0 - PANEL.y, PANEL.x, PANEL.y)


func _icon_rect(row: int) -> Rect2:
	var p := panel_rect()
	return Rect2(p.position.x + 16.0, p.position.y + 46.0 + row * 52.0, ICON, ICON)


func _track_rect(row: int) -> Rect2:
	var ic := _icon_rect(row)
	var x := ic.end.x + 18.0
	return Rect2(x, ic.get_center().y - 3.0, panel_rect().end.x - 24.0 - x, 6.0)


## Returns true when the event belonged to the settings (the game should ignore it).
func handle(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = event.position
		if event.pressed:
			if button_rect().has_point(p):
				_set_open(not is_open)
				return true
			if not is_open:
				return false
			for row in 2:
				if _icon_rect(row).grow(4.0).has_point(p):
					if row == 0:
						sound.toggle_music()
					else:
						sound.toggle_sfx()
					sound.save()
					_feedback(row)
					queue_redraw()
					return true
				if _track_rect(row).grow_individual(14.0, 20.0, 14.0, 20.0).has_point(p):
					_drag_row = row
					_slide(p)
					return true
			if not panel_rect().has_point(p):
				_set_open(false)  # tap outside closes the panel
			return true
		if _drag_row >= 0:
			_slide(p)
			_feedback(_drag_row)
			_drag_row = -1
			sound.save()
			return true
		return is_open
	if event is InputEventMouseMotion and _drag_row >= 0:
		_slide(event.position)
		return true
	return false


func _set_open(on: bool) -> void:
	is_open = on
	_drag_row = -1
	if not on:
		sound.save()
	queue_redraw()


func _slide(p: Vector2) -> void:
	var r := _track_rect(_drag_row)
	var v := clampf((p.x - r.position.x) / r.size.x, 0.0, 1.0)
	if _drag_row == 0:
		sound.set_music(v)
	else:
		sound.set_sfx(v)
	queue_redraw()


## Lets you hear the new effects level.
func _feedback(row: int) -> void:
	if row == 1 and sound.sfx_volume > 0.0:
		sound.play("drop")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var b := button_rect()
	var sb := _pill.duplicate() as StyleBoxFlat
	if is_open:
		sb.bg_color = Color(0.02, 0.14, 0.26, 0.82)
	draw_style_box(sb, b)
	_gear(b.get_center(), Color(1, 1, 1, 0.95 if is_open else 0.8))
	if not is_open:
		return
	var p := panel_rect()
	draw_style_box(_card, p)
	draw_string(_font, Vector2(p.position.x + 20.0, p.position.y + 34.0 + 2.0), "Sound", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK)
	draw_string(_font, Vector2(p.position.x + 20.0, p.position.y + 34.0), "Sound", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	for row in 2:
		var v := sound.music_volume if row == 0 else sound.sfx_volume
		var ic := _icon_rect(row)
		var isb := _pill.duplicate() as StyleBoxFlat
		isb.set_corner_radius_all(22)
		isb.bg_color = Color(0.20, 0.62, 0.32, 0.6) if v > 0.0 else Color(0.5, 0.15, 0.15, 0.45)
		draw_style_box(isb, ic)
		var col := Color.WHITE if v > 0.0 else Color(1, 1, 1, 0.55)
		if row == 0:
			_note(ic.get_center(), col)
		else:
			_speaker(ic.get_center(), col, v)
		if v <= 0.0:  # muted: a slash across the icon
			var c := ic.get_center()
			draw_line(c + Vector2(-13, -13), c + Vector2(13, 13), Color(0.02, 0.14, 0.26, 0.9), 6.0, true)
			draw_line(c + Vector2(-13, -13), c + Vector2(13, 13), Color(1, 0.55, 0.5), 3.0, true)
		var tr := _track_rect(row)
		var y := tr.get_center().y
		draw_line(Vector2(tr.position.x, y), Vector2(tr.end.x, y), Color(0, 0.08, 0.16, 0.6), 8.0, true)
		draw_line(Vector2(tr.position.x, y), Vector2(tr.end.x, y), Color(1, 1, 1, 0.18), 6.0, true)
		var kx := tr.position.x + tr.size.x * v
		if v > 0.0:
			draw_line(Vector2(tr.position.x, y), Vector2(kx, y), MINT, 6.0, true)
		draw_circle(Vector2(kx, y), 12.0, Color(0, 0.08, 0.16, 0.35))
		draw_circle(Vector2(kx, y - 1.0), 11.0, Color.WHITE)
		draw_circle(Vector2(kx, y - 1.0), 5.0, MINT if v > 0.0 else Color(0.7, 0.75, 0.8))


func _gear(c: Vector2, col: Color) -> void:
	const TEETH := 8
	for k in TEETH:
		var a := TAU * k / TEETH
		var d := Vector2.from_angle(a)
		var s := d.orthogonal()
		draw_colored_polygon(PackedVector2Array([
			c + d * 10.0 + s * 4.5, c + d * 17.0 + s * 3.2, c + d * 17.0 - s * 3.2, c + d * 10.0 - s * 4.5,
		]), col)
	draw_arc(c, 9.5, 0.0, TAU, 32, col, 6.0, true)


## Two beamed eighth notes.
func _note(c: Vector2, col: Color) -> void:
	var h1 := c + Vector2(-7, 8)
	var h2 := c + Vector2(7, 5)
	draw_set_transform(h1, -0.4, Vector2(1.25, 0.9))
	draw_circle(Vector2.ZERO, 4.6, col)
	draw_set_transform(h2, -0.4, Vector2(1.25, 0.9))
	draw_circle(Vector2.ZERO, 4.6, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_line(h1 + Vector2(4.5, 0), c + Vector2(-2.5, -11), col, 2.5)
	draw_line(h2 + Vector2(4.5, 0), c + Vector2(11.5, -14), col, 2.5)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-3.7, -11), c + Vector2(12.7, -14), c + Vector2(12.7, -9), c + Vector2(-3.7, -6),
	]), col)


## Speaker cone with sound waves; fewer waves at lower volume.
func _speaker(c: Vector2, col: Color, v: float) -> void:
	var o := c + Vector2(-6, 0)
	draw_colored_polygon(PackedVector2Array([
		o + Vector2(-8, -5), o + Vector2(-3, -5), o + Vector2(5, -12), o + Vector2(5, 12), o + Vector2(-3, 5), o + Vector2(-8, 5),
	]), col)
	if v > 0.0:
		draw_arc(o + Vector2(6, 0), 7.0, -0.8, 0.8, 10, col, 2.5, true)
	if v > 0.5:
		draw_arc(o + Vector2(6, 0), 13.0, -0.8, 0.8, 12, col, 2.5, true)
