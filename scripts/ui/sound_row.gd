extends Control
## One volume control in the settings window: an icon that mutes / restores, and a slider.
## kind 0 = music, 1 = sound effects.

const MINT := Color(0.55, 0.93, 0.72)
const ICON := 48.0

var sound: Sound
var kind := 0
var _dragging := false


func _init(s: Sound, k: int) -> void:
	sound = s
	kind = k
	custom_minimum_size = Vector2(0, 60)
	mouse_filter = MOUSE_FILTER_STOP


func _volume() -> float:
	return sound.music_volume if kind == 0 else sound.sfx_volume


func _icon_rect() -> Rect2:
	return Rect2(0, (size.y - ICON) * 0.5, ICON, ICON)


func _track_rect() -> Rect2:
	var x := ICON + 22.0
	return Rect2(x, size.y * 0.5 - 3.0, size.x - x - 14.0, 6.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _icon_rect().grow(6.0).has_point(event.position):
				if kind == 0:
					sound.toggle_music()
				else:
					sound.toggle_sfx()
				sound.save()
				_feedback()
			elif event.position.x >= _track_rect().position.x - 14.0:
				_dragging = true
				_slide(event.position)
			queue_redraw()
		elif _dragging:
			_dragging = false
			sound.save()
			_feedback()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_slide(event.position)
		accept_event()


func _slide(p: Vector2) -> void:
	var r := _track_rect()
	var v := clampf((p.x - r.position.x) / r.size.x, 0.0, 1.0)
	if kind == 0:
		sound.set_music(v)
	else:
		sound.set_sfx(v)
	queue_redraw()


## Lets you hear the new effects level.
func _feedback() -> void:
	if kind == 1 and sound.sfx_volume > 0.0:
		sound.play("drop")


func _draw() -> void:
	var v := _volume()
	var ic := _icon_rect()
	var c := ic.get_center()
	draw_circle(c, ICON * 0.5, Color(0.20, 0.62, 0.32, 0.65) if v > 0.0 else Color(0.5, 0.15, 0.15, 0.5))
	draw_arc(c, ICON * 0.5, 0.0, TAU, 40, Color(1, 1, 1, 0.2), 2.0, true)
	var col := Color.WHITE if v > 0.0 else Color(1, 1, 1, 0.55)
	if kind == 0:
		_note(c, col)
	else:
		_speaker(c, col, v)
	if v <= 0.0:  # muted: a slash across the icon
		draw_line(c + Vector2(-14, -14), c + Vector2(14, 14), Color(0.02, 0.14, 0.26, 0.9), 6.0, true)
		draw_line(c + Vector2(-14, -14), c + Vector2(14, 14), Color(1, 0.55, 0.5), 3.0, true)
	var tr := _track_rect()
	var y := tr.get_center().y
	draw_line(Vector2(tr.position.x, y), Vector2(tr.end.x, y), Color(0, 0.08, 0.16, 0.6), 8.0, true)
	draw_line(Vector2(tr.position.x, y), Vector2(tr.end.x, y), Color(1, 1, 1, 0.18), 6.0, true)
	var kx := tr.position.x + tr.size.x * v
	if v > 0.0:
		draw_line(Vector2(tr.position.x, y), Vector2(kx, y), MINT, 6.0, true)
	draw_circle(Vector2(kx, y), 13.0, Color(0, 0.08, 0.16, 0.35))
	draw_circle(Vector2(kx, y - 1.0), 12.0, Color.WHITE)
	draw_circle(Vector2(kx, y - 1.0), 5.0, MINT if v > 0.0 else Color(0.7, 0.75, 0.8))


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
