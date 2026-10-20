class_name SettingsPanel
extends Control
## Gear button in the bottom-right corner; it opens the Settings window: music and effects
## volume (each with an icon that mutes it and brings the old volume back), then the bubble colour.
## Taps come from main.gd through handle(), before the game sees them.

const Modal := preload("res://scripts/ui/modal.gd")
const SoundRow := preload("res://scripts/ui/sound_row.gd")
const SkinRow := preload("res://scripts/ui/skin_row.gd")
const BUTTON := 52.0

var sound: Sound
var modal_parent: Node  # layer the window opens in
var on_skin_change: Callable  # the bubble colour was changed
var bottom_inset := 0.0  # home indicator / nav bar, in viewport units
var is_open := false

var _pill := StyleBoxFlat.new()


func _init() -> void:
	_pill.bg_color = Color(0.02, 0.14, 0.26, 0.42)
	_pill.border_color = Color(1, 1, 1, 0.18)
	_pill.set_border_width_all(2)
	_pill.set_corner_radius_all(16)


func button_rect() -> Rect2:
	return Rect2(size.x - BUTTON - 18.0, size.y - BUTTON - 18.0 - bottom_inset, BUTTON, BUTTON)


## Returns true when the event belonged to the settings (the game should ignore it).
func handle(event: InputEvent) -> bool:
	if is_open:
		return true  # the window's own controls take it
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if button_rect().has_point(event.position):
			open()
			return true
	return false


func open() -> void:
	if is_open:
		return
	is_open = true
	var m := Modal.new("Settings")
	var heading := Label.new()
	heading.text = "Sound"
	heading.theme_type_variation = "MutedLabel"
	m.content.add_child(heading)
	m.content.add_child(SoundRow.new(sound, 0))
	m.content.add_child(SoundRow.new(sound, 1))
	var look := Label.new()
	look.text = "Bubble"
	look.theme_type_variation = "MutedLabel"
	m.content.add_child(look)
	var skins := SkinRow.new()
	skins.on_change = on_skin_change
	m.content.add_child(skins)
	m.closed.connect(_on_closed)
	modal_parent.add_child(m)
	queue_redraw()


func _on_closed() -> void:
	is_open = false
	sound.save()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var b := button_rect()
	draw_style_box(_pill, b)
	_gear(b.get_center(), Color(1, 1, 1, 0.85))


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
