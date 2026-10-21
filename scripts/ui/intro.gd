extends Control
## The welcome screen after the boot splash (a plain sea-blue screen): the game's animated sea
## fades in, the "99" springs up and "jumps" writes itself in, then the bubble
## pops up left of the "99", hops across it in a half circle leaving a dotted trail (as on the icon) and dives into
## the water on the right with a splash and ripples. Fades into the game after ~3.5 s; a tap
## skips. Added to main's modal layer, so the game ignores input while it shows.
## No class_name, so the OTA shape doesn't change.

signal finished

const Logo := preload("res://scripts/ui/logo.gd")

## Same as the boot splash colour (project.godot), so the hand-over is seamless.
const BOOT_COLOR := Color(0.05, 0.28, 0.45)
const FADE_IN := 0.35
const SPRING := Vector2(0.3, 0.9)  # the "99" springs up
const WRITE := Vector2(0.8, 1.45)  # "jumps" writes in
const APPEAR := Vector2(1.45, 1.7)  # the bubble pops up
const CROUCH := Vector2(1.7, 1.9)  # it squashes to jump
const FLY := Vector2(1.9, 2.6)  # the hop over the "99"
const DOT_EVERY := 0.06  # trail dots, seconds apart
const BUBBLE_R := 30.0
const END := 3.5
const FADE_OUT := 0.45

var play_sound: Callable  # (name, volume_db, pitch)
var _t := 0.0
var _ending := -1.0  # time the fade out started
var _water_mat: ShaderMaterial
var _fx: Fx
var _art: Node2D
var _cover: ColorRect
var _center := Vector2.ZERO
var _from := Vector2.ZERO  # where the bubble jumps from (left of the "99")
var _to := Vector2.ZERO  # where it dives in (right of it)
var _dots: Array[Dictionary] = []  # {p, r, t}
var _next_dot := 0.0
var _splashed := false
var _sounds := 0  # how many of the letter / hop sounds played


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	var view := get_viewport_rect().size
	_center = Vector2(view.x / 2.0, view.y * 0.42)
	_from = _center + Vector2(-180, 70)
	_to = _center + Vector2(180, 70)

	var water := ColorRect.new()
	water.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	water.mouse_filter = MOUSE_FILTER_IGNORE
	water.z_index = -10  # under the splash's water rings (drawn a little below the fx node)
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = load("res://shaders/water.gdshader")
	_water_mat.set_shader_parameter("area", view)
	_water_mat.set_shader_parameter("origin", Vector2(-600, 900))
	water.material = _water_mat
	add_child(water)
	_fx = Fx.new()
	add_child(_fx)
	_art = Node2D.new()
	_art.draw.connect(_draw_art)
	add_child(_art)

	_cover = ColorRect.new()
	_cover.color = BOOT_COLOR
	_cover.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_cover.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_cover)


func _gui_input(event: InputEvent) -> void:
	var tap: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
	if tap and _t > FADE_IN and _ending < 0.0:
		_ending = _t
	accept_event()


func _process(delta: float) -> void:
	_t += delta
	_water_mat.set_shader_parameter("t", _t + 20.0)
	_cover.modulate.a = 1.0 - smoothstep(0.0, FADE_IN, _t)

	# A soft pluck for each letter of "jumps" as it appears, then one as the bubble takes off.
	var plucks := mini(int(_write() * 6.5), 5)
	while _sounds < plucks:
		_sounds += 1
		_sound("drop", -14.0, 1.0 + 0.1 * _sounds)
	if _sounds == 5 and _t >= FLY.x:
		_sounds += 1
		_sound("land", -6.0, 1.3)

	# The trail: a dot every so often along the hop, a little bigger each time.
	if _t >= FLY.x and _t < FLY.y and _t >= _next_dot:
		_next_dot = _t + DOT_EVERY
		_dots.append({"p": _hop((_t - FLY.x) / (FLY.y - FLY.x)), "r": 3.0 + _dots.size() * 0.55, "t": _t})
	if not _splashed and _t >= FLY.y:
		_splashed = true
		_fx.splash(_to, 1.0, 0.8)
		_fx.ring(_to, 150.0, Color(1, 1, 1, 0.5), 1.6, 0.55, true)
		_fx.ring(_to, 220.0, Color(1, 1, 1, 0.3), 2.2, 0.55, true)
		_sound("splash", -4.0, 1.1)
	_art.queue_redraw()

	if _ending < 0.0 and _t >= END:
		_ending = _t
	if _ending >= 0.0:
		modulate.a = 1.0 - clampf((_t - _ending) / FADE_OUT, 0.0, 1.0)
		if _t - _ending >= FADE_OUT:
			finished.emit()
			queue_free()


func _write() -> float:
	return clampf((_t - WRITE.x) / (WRITE.y - WRITE.x), 0.0, 1.0)


## The hop's path (side view): a half circle from _from up across the "99" down to _to.
func _hop(u: float) -> Vector2:
	var mid := (_from + _to) / 2.0
	var r := _from.distance_to(_to) / 2.0
	var a := PI * (1.0 - u)
	return mid + Vector2(cos(a), -sin(a)) * r


func _draw_art() -> void:
	var bob := sin(_t * 2.0) * 3.0
	if _t >= SPRING.x:
		var u := clampf((_t - SPRING.x) / (SPRING.y - SPRING.x), 0.0, 1.0)
		var s := _back_out(u)
		var squash := Vector2(s * (1.0 + 0.12 * (1.0 - u)), s * (1.0 - 0.12 * (1.0 - u)))
		Logo.number(_art, _center + Vector2(0, bob), 1.0, smoothstep(0.0, 0.25, u), squash)
	if _t >= WRITE.x:
		Logo.word(_art, _center + Vector2(0, bob * 0.7), 1.0, _write())

	# Trail dots fade out a while after they are left behind.
	for d in _dots:
		var a := 1.0 - smoothstep(0.5, 1.1, _t - d.t)
		if a > 0.0:
			_art.draw_circle(d.p, d.r, Color(1, 1, 1, a))

	if _t < APPEAR.x or _splashed:
		return
	var at := _from
	var squash := Vector2.ONE
	if _t < APPEAR.y:  # pops up
		var s := _back_out((_t - APPEAR.x) / (APPEAR.y - APPEAR.x))
		squash = Vector2(s, s)
	elif _t < CROUCH.y:  # crouches
		var u := sin(PI * 0.5 * (_t - CROUCH.x) / (CROUCH.y - CROUCH.x))
		squash = Vector2(1.0 + 0.14 * u, 1.0 - 0.16 * u)
		at.y += BUBBLE_R * 0.25 * u
	else:  # flies, stretched along the way it goes
		var u := (_t - FLY.x) / (FLY.y - FLY.x)
		at = _hop(u)
		var stretch := 0.15 * absf(1.0 - 2.0 * u)
		squash = Vector2(1.0 - stretch, 1.0 + stretch)
		# Shrinks into the water over the last moments.
		squash *= 1.0 - smoothstep(0.85, 1.0, u) * 0.5
	Logo.bubble(_art, at, BUBBLE_R, squash, 1.0, _t)


## 0 -> 1 with a playful overshoot past 1 before settling.
func _back_out(u: float) -> float:
	var c := 2.2
	var v := clampf(u, 0.0, 1.0) - 1.0
	return 1.0 + (c + 1.0) * v * v * v + c * v * v


func _sound(name: String, db: float, pitch: float) -> void:
	if play_sound.is_valid():
		play_sound.call(name, db, pitch)
