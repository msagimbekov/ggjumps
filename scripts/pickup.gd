class_name Pickup
extends Node2D
## A collectable sitting on an island. LIFE: a small bubble, three of them make a bigger one (a life). RADAR: a gold radar lens, switches the landing line on for a while. Collected by settling on it; settling on its island anywhere else makes it vanish.
## Child of its Land, so it rides along on moving islands.

enum Kind { LIFE, RADAR }
enum State { IDLE, COLLECTED, GONE }

const FONT := preload("res://fonts/Fredoka.ttf")
const COLLECT_TIME := 0.9
const VANISH_TIME := 0.5
const BUBBLE := Color(0.30, 0.80, 1.0)
const GOLD := Color(1.0, 0.82, 0.25)

var kind := Kind.LIFE
var state := State.IDLE

var _t := randf() * 10.0
var _phase := randf() * TAU
var _anim := 0.0
var _text := ""
var _bits: Array[Dictionary] = []
var _font: FontVariation


func _ready() -> void:
	_font = FontVariation.new()
	_font.base_font = FONT
	_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 650}


func is_active() -> bool:
	return state == State.IDLE


func _tone() -> Color:
	return BUBBLE if kind == Kind.LIFE else GOLD


## Collected: pops up and fades, with a ring, sparkles and a floating note.
func collect(note: String) -> void:
	state = State.COLLECTED
	_anim = 0.0
	_text = note
	_burst(16, 110.0, _tone())


## Missed: shrinks, sinks and puffs away.
func vanish() -> void:
	state = State.GONE
	_anim = 0.0
	_burst(8, 45.0, Color(0.92, 0.96, 1.0))


func reset() -> void:
	state = State.IDLE
	_anim = 0.0
	_bits.clear()
	visible = true


func _burst(n: int, speed: float, col: Color) -> void:
	for i in n:
		_bits.append({"p": Vector2.ZERO, "v": Vector2.from_angle(randf() * TAU) * randf_range(0.4, 1.0) * speed, "t": 0.0, "life": randf_range(0.35, 0.7), "col": col})


func _process(delta: float) -> void:
	_t += delta
	if state != State.IDLE:
		_anim += delta
		for b in _bits:
			b.t += delta
			b.p += b.v * delta
			b.v *= 0.93
		_bits = _bits.filter(func(b): return b.t < b.life)
		if _anim > COLLECT_TIME + 0.1:
			visible = false
			return
	queue_redraw()


func _draw() -> void:
	var bob := sin(_t * 2.4) * 2.5
	var tone := _tone()
	match state:
		State.IDLE:
			draw_set_transform(Vector2(0, 14), 0.0, Vector2(1.0, 0.4))
			draw_circle(Vector2.ZERO, 12.0 - bob * 0.4, Color(0, 0.08, 0.04, 0.28))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var glow := 0.14 + 0.08 * sin(_t * 3.0)
			draw_circle(Vector2(0, bob), 26.0, Color(tone.r, tone.g, tone.b, glow))
			draw_box(self, Vector2(0, bob - 4.0), 1.0, kind, 1.0, 1.0, _t * 2.5, _phase)
		State.COLLECTED:
			var u := clampf(_anim / COLLECT_TIME, 0.0, 1.0)
			var rise := 1.0 - pow(1.0 - u, 3.0)
			var pop := 1.0 + 0.5 * sin(PI * minf(u * 1.6, 1.0))
			var fade := 1.0 - smoothstep(0.6, 1.0, u)
			draw_arc(Vector2.ZERO, 14.0 + 52.0 * rise, 0.0, TAU, 32, Color(tone.r, tone.g, tone.b, 0.8 * (1.0 - u)), 4.0 * (1.0 - u) + 1.0)
			draw_box(self, Vector2(0, bob - 4.0 - 36.0 * rise), pop, kind, 1.0, fade, _t * 2.5, _phase)
			if _text != "":
				var pos := Vector2(-60, -54.0 - 26.0 * rise)
				draw_string(_font, pos + Vector2(0, 2), _text, HORIZONTAL_ALIGNMENT_CENTER, 120, 22, Color(0, 0.08, 0.16, 0.6 * fade))
				draw_string(_font, pos, _text, HORIZONTAL_ALIGNMENT_CENTER, 120, 22, Color(1, 1, 1, fade))
		State.GONE:
			var u := clampf(_anim / VANISH_TIME, 0.0, 1.0)
			draw_box(self, Vector2(0, bob - 4.0 + 10.0 * u), 1.0 - u, kind, 1.0, 1.0 - u)
	for b in _bits:
		var k: float = 1.0 - b.t / b.life
		var col: Color = b.col
		draw_circle(b.p + Vector2(0, -10), 3.2 * k + 0.5, Color(col.r, col.g, col.b, k))


## How visible the pickup radar is with `left` seconds to go: steady, then a slow soft pulse over
## the last two seconds that fades out for good at the end (no hard flashing).
static func radar_alpha(left: float) -> float:
	if left <= 0.0:
		return 0.0
	if left > 2.0:
		return 1.0
	var pulse := 0.65 + 0.35 * cos((2.0 - left) * TAU * 0.8)
	return pulse * smoothstep(0.0, 0.5, left)


## One pickup, centred on `pos`. LIFE: a small bubble (half the player's size); `fill` 0 is a
## faint empty outline (HUD slot), 1 the full bubble. RADAR: the gold radar lens.
static func draw_box(ci: CanvasItem, pos: Vector2, s: float, k: Kind, fill: float, alpha: float, sweep := 0.0, phase := 0.0) -> void:
	if s <= 0.01 or alpha <= 0.0:
		return
	if k == Kind.RADAR:
		draw_lens(ci, pos, s, alpha * fill, sweep)
	else:
		draw_bubble(ci, pos, 11.0 * s, fill, alpha, phase)


## A small liquid drop in the player's colours: a wobbling, gently squashing blob, never a
## perfect circle. `fill` 0 is just a faint outline. `phase` keeps neighbours out of step.
static func draw_bubble(ci: CanvasItem, pos: Vector2, r: float, fill: float, alpha: float, phase := 0.0) -> void:
	var t := Time.get_ticks_msec() * 0.001 + phase
	var squash := 0.07 * sin(t * 2.3)
	var pts := PackedVector2Array()
	for n in 24:
		var a := TAU * n / 24.0
		var rr := r * (1.0 + 0.09 * sin(a * 2.0 + t * 3.1) + 0.06 * sin(a * 3.0 - t * 2.4) + 0.035 * sin(a * 5.0 + t * 4.2))
		pts.append(pos + Vector2(cos(a) * rr * (1.0 + squash), sin(a) * rr * (1.0 - squash)))
	var line := Color(1, 1, 1, 0.5).lerp(Color(0.10, 0.50, 0.80), fill)
	line.a *= alpha
	if fill > 0.0:
		ci.draw_colored_polygon(pts, Color(0.30, 0.80, 1.0, 0.95 * fill * alpha))
		var core := PackedVector2Array()
		for q in pts:
			core.append(pos + (q - pos) * 0.68 + Vector2(-0.1, -0.16) * r)
		ci.draw_colored_polygon(core, Color(0.62, 0.95, 1.0, 0.5 * fill * alpha))
		ci.draw_circle(pos + Vector2(-0.33, -0.36) * r, r * 0.22, Color(1, 1, 1, 0.85 * fill * alpha))
		ci.draw_circle(pos + Vector2(0.24, 0.4) * r, r * 0.1, Color(1, 1, 1, 0.5 * fill * alpha))
	var loop := PackedVector2Array(pts)
	loop.append(pts[0])
	ci.draw_polyline(loop, line, maxf(r * 0.09, 1.2), true)


## The radar lens: ring, four ticks, centre dot and a sweeping wedge.
static func draw_lens(ci: CanvasItem, pos: Vector2, s: float, alpha: float, sweep: float) -> void:
	if s <= 0.01 or alpha <= 0.0:
		return
	var dark := Color(0.62, 0.42, 0.05, 0.55 * alpha)
	var gold := Color(GOLD.r, GOLD.g, GOLD.b, alpha)
	ci.draw_arc(pos, 13.0 * s, 0.0, TAU, 28, dark, 6.5 * s, true)
	ci.draw_arc(pos, 13.0 * s, 0.0, TAU, 28, gold, 3.5 * s, true)
	for i in 4:
		var d := Vector2.from_angle(i * PI / 2.0)
		ci.draw_line(pos + d * 16.0 * s, pos + d * 22.0 * s, dark, 6.0 * s, true)
		ci.draw_line(pos + d * 16.0 * s, pos + d * 22.0 * s, gold, 3.0 * s, true)
	ci.draw_circle(pos, 3.6 * s, gold)
	ci.draw_arc(pos, 7.5 * s, sweep - 1.0, sweep, 8, Color(1, 1, 1, 0.7 * alpha), 5.0 * s)
