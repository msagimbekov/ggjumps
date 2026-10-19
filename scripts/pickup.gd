class_name Pickup
extends Node2D
## A collectable sitting on an island. LIFE: a coral drop, three of them give a life. RADAR: a gold
## lens, switches the landing line on for a while. It is collected by settling on it; settling on its
## island anywhere else makes it vanish. Child of its Land, so it rides along on moving islands.

enum Kind { LIFE, RADAR }
enum State { IDLE, COLLECTED, GONE }

const FONT := preload("res://fonts/Fredoka.ttf")
const COLLECT_TIME := 0.9
const VANISH_TIME := 0.5
const DROP_FILL := Color(1.0, 0.45, 0.58)
const DROP_EDGE := Color(0.78, 0.17, 0.36)
const GOLD := Color(1.0, 0.82, 0.25)
const GOLD_EDGE := Color(0.62, 0.42, 0.05)

var kind := Kind.LIFE
var state := State.IDLE

var _t := randf() * 10.0
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


## Collected: pops up and fades, with a ring, sparkles and a floating note.
func collect(note: String) -> void:
	state = State.COLLECTED
	_anim = 0.0
	_text = note
	_burst(16, 110.0, DROP_FILL if kind == Kind.LIFE else GOLD)


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
	var bob := sin(_t * 2.4) * 3.0
	match state:
		State.IDLE:
			var glow := 0.22 + 0.1 * sin(_t * 3.0)
			var tone := DROP_FILL if kind == Kind.LIFE else GOLD
			draw_set_transform(Vector2(0, 8), 0.0, Vector2(1.0, 0.45))
			draw_circle(Vector2.ZERO, 13.0 - bob * 0.4, Color(0, 0.08, 0.04, 0.25))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_circle(Vector2(0, bob), 24.0, Color(tone.r, tone.g, tone.b, glow))
			_body(Vector2(0, bob), 1.0, 1.0)
		State.COLLECTED:
			var u := clampf(_anim / COLLECT_TIME, 0.0, 1.0)
			var rise := 1.0 - pow(1.0 - u, 3.0)
			var pop := 1.0 + 0.55 * sin(PI * minf(u * 1.6, 1.0))
			var fade := 1.0 - smoothstep(0.6, 1.0, u)
			var tone := DROP_FILL if kind == Kind.LIFE else GOLD
			draw_arc(Vector2.ZERO, 14.0 + 52.0 * rise, 0.0, TAU, 32, Color(tone.r, tone.g, tone.b, 0.8 * (1.0 - u)), 4.0 * (1.0 - u) + 1.0)
			_body(Vector2(0, bob - 36.0 * rise), pop, fade)
			if _text != "":
				var pos := Vector2(-60, -50.0 - 26.0 * rise)
				draw_string(_font, pos + Vector2(0, 2), _text, HORIZONTAL_ALIGNMENT_CENTER, 120, 22, Color(0, 0.08, 0.16, 0.6 * fade))
				draw_string(_font, pos, _text, HORIZONTAL_ALIGNMENT_CENTER, 120, 22, Color(1, 1, 1, fade))
		State.GONE:
			var u := clampf(_anim / VANISH_TIME, 0.0, 1.0)
			_body(Vector2(0, bob + 10.0 * u), 1.0 - u, 1.0 - u)
	for b in _bits:
		var k: float = 1.0 - b.t / b.life
		var col: Color = b.col
		draw_circle(b.p + Vector2(0, -10), 3.2 * k + 0.5, Color(col.r, col.g, col.b, k))


func _body(pos: Vector2, s: float, alpha: float) -> void:
	if kind == Kind.LIFE:
		draw_drop(self, pos, s, 1.0, alpha)
	else:
		draw_lens(self, pos, s, alpha, _t * 2.5)


## A teardrop. `fill` 0 is an empty outline (HUD slot), 1 the full coral drop.
static func draw_drop(ci: CanvasItem, pos: Vector2, s: float, fill: float, alpha: float) -> void:
	if s <= 0.01 or alpha <= 0.0:
		return
	var pts := PackedVector2Array([pos + Vector2(0, -21) * s])
	var steps := 20
	for i in steps + 1:
		var th := lerpf(-PI / 2.0 + 1.047, 3.0 * PI / 2.0 - 1.047, float(i) / steps)
		pts.append(pos + (Vector2(0, 5) + Vector2(cos(th), sin(th)) * 13.0) * s)
	var body := Color(0.0, 0.1, 0.2, 0.3).lerp(DROP_FILL, fill)
	var edge := Color(1, 1, 1, 0.5).lerp(DROP_EDGE, fill)
	body.a *= alpha
	edge.a *= alpha
	ci.draw_colored_polygon(pts, body)
	var loop := PackedVector2Array(pts)
	loop.append(pts[0])
	ci.draw_polyline(loop, edge, 2.5 * s, true)
	if fill > 0.0:
		ci.draw_circle(pos + Vector2(-4.5, 3) * s, 3.4 * s, Color(1, 1, 1, 0.85 * fill * alpha))
		ci.draw_circle(pos + Vector2(-1.5, 9) * s, 1.5 * s, Color(1, 1, 1, 0.5 * fill * alpha))


## A radar lens: ring, four ticks, centre dot and a sweeping wedge.
static func draw_lens(ci: CanvasItem, pos: Vector2, s: float, alpha: float, sweep: float) -> void:
	if s <= 0.01 or alpha <= 0.0:
		return
	var dark := Color(GOLD_EDGE.r, GOLD_EDGE.g, GOLD_EDGE.b, 0.55 * alpha)
	var gold := Color(GOLD.r, GOLD.g, GOLD.b, alpha)
	ci.draw_arc(pos, 13.0 * s, 0.0, TAU, 28, dark, 6.5 * s, true)
	ci.draw_arc(pos, 13.0 * s, 0.0, TAU, 28, gold, 3.5 * s, true)
	for i in 4:
		var d := Vector2.from_angle(i * PI / 2.0)
		ci.draw_line(pos + d * 16.0 * s, pos + d * 22.0 * s, dark, 6.0 * s, true)
		ci.draw_line(pos + d * 16.0 * s, pos + d * 22.0 * s, gold, 3.0 * s, true)
	ci.draw_circle(pos, 3.6 * s, gold)
	ci.draw_arc(pos, 7.5 * s, sweep - 1.0, sweep, 8, Color(1, 1, 1, 0.7 * alpha), 5.0 * s)
