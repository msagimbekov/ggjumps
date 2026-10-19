class_name Pickup
extends Node2D
## A crate sitting on an island. LIFE: a white wooden first-aid crate with a red cross, three of
## them give a life. RADAR: a dark steel crate with a gold radar on it, switches the landing line on
## for a while. Collected by settling on it; settling on its island anywhere else makes it vanish.
## Child of its Land, so it rides along on moving islands.

enum Kind { LIFE, RADAR }
enum State { IDLE, COLLECTED, GONE }

const FONT := preload("res://fonts/Fredoka.ttf")
const COLLECT_TIME := 0.9
const VANISH_TIME := 0.5
const HALF := 16.0  # half the crate's side at scale 1
const RED := Color(0.90, 0.16, 0.20)
const WOOD := Color(0.55, 0.38, 0.22)
const CREAM := Color(0.97, 0.94, 0.86)
const STEEL := Color(0.15, 0.26, 0.37)
const GOLD := Color(1.0, 0.82, 0.25)

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


func _tone() -> Color:
	return RED if kind == Kind.LIFE else GOLD


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
			draw_circle(Vector2.ZERO, 16.0 - bob * 0.4, Color(0, 0.08, 0.04, 0.28))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var glow := 0.14 + 0.08 * sin(_t * 3.0)
			draw_circle(Vector2(0, bob), 28.0, Color(tone.r, tone.g, tone.b, glow))
			draw_box(self, Vector2(0, bob - 4.0), 1.0, kind, 1.0, 1.0, _t * 2.5)
		State.COLLECTED:
			var u := clampf(_anim / COLLECT_TIME, 0.0, 1.0)
			var rise := 1.0 - pow(1.0 - u, 3.0)
			var pop := 1.0 + 0.5 * sin(PI * minf(u * 1.6, 1.0))
			var fade := 1.0 - smoothstep(0.6, 1.0, u)
			draw_arc(Vector2.ZERO, 14.0 + 52.0 * rise, 0.0, TAU, 32, Color(tone.r, tone.g, tone.b, 0.8 * (1.0 - u)), 4.0 * (1.0 - u) + 1.0)
			draw_box(self, Vector2(0, bob - 4.0 - 36.0 * rise), pop, kind, 1.0, fade, _t * 2.5)
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


## A rounded square outline made of points, `half` from the centre to each side.
static func _rounded(pos: Vector2, half: float, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]
	for c in 4:
		var centre: Vector2 = pos + (corners[c] as Vector2) * (half - r)
		for i in 5:
			var a := (-PI / 2.0 + c * PI / 2.0) + float(i) / 4.0 * PI / 2.0
			pts.append(centre + Vector2(cos(a), sin(a)) * r)
	return pts


## How visible the pickup radar is with `left` seconds to go: steady, then a slow soft pulse over
## the last two seconds that fades out for good at the end (no hard flashing).
static func radar_alpha(left: float) -> float:
	if left <= 0.0:
		return 0.0
	if left > 2.0:
		return 1.0
	var pulse := 0.65 + 0.35 * cos((2.0 - left) * TAU * 0.8)
	return pulse * smoothstep(0.0, 0.5, left)


## One crate, centred on `pos`, about 32 px wide at scale 1. `fill` 0 is a dark empty slot (HUD),
## 1 the full crate.
static func draw_box(ci: CanvasItem, pos: Vector2, s: float, k: Kind, fill: float, alpha: float, sweep := 0.0) -> void:
	if s <= 0.01 or alpha <= 0.0:
		return
	var h := HALF * s
	var outer := _rounded(pos, h, 4.0 * s)
	var inner := _rounded(pos, h - 3.0 * s, 2.5 * s)
	var edge: Color
	var face: Color
	if k == Kind.LIFE:
		edge = WOOD.lerp(Color(1, 1, 1, 0.5), 1.0 - fill)
		face = CREAM.lerp(Color(0.0, 0.1, 0.2, 0.3), 1.0 - fill)
	else:
		edge = GOLD.lerp(Color(1, 1, 1, 0.5), 1.0 - fill)
		face = STEEL.lerp(Color(0.0, 0.1, 0.2, 0.3), 1.0 - fill)
	edge.a *= alpha
	face.a *= alpha
	ci.draw_colored_polygon(outer, edge)
	ci.draw_colored_polygon(inner, face)
	if k == Kind.LIFE:
		var plank := Color(WOOD.r, WOOD.g, WOOD.b, 0.28 * fill * alpha)
		ci.draw_line(pos + Vector2(-h + 4.0 * s, -h * 0.5), pos + Vector2(h - 4.0 * s, -h * 0.5), plank, 1.5 * s)
		ci.draw_line(pos + Vector2(-h + 4.0 * s, h * 0.5), pos + Vector2(h - 4.0 * s, h * 0.5), plank, 1.5 * s)
		var cross := Color(RED.r, RED.g, RED.b, alpha).lerp(Color(1, 1, 1, 0.35 * alpha), 1.0 - fill)
		var arm := 4.0 * s
		var reach := h * 0.62
		ci.draw_rect(Rect2(pos + Vector2(-arm, -reach), Vector2(arm * 2.0, reach * 2.0)), cross)
		ci.draw_rect(Rect2(pos + Vector2(-reach, -arm), Vector2(reach * 2.0, arm * 2.0)), cross)
	else:
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			ci.draw_circle(pos + corner * (h - 5.0 * s), 1.6 * s, Color(GOLD.r, GOLD.g, GOLD.b, 0.8 * fill * alpha))
		draw_lens(ci, pos, 0.55 * s, alpha * fill, sweep)


## The radar image: ring, four ticks, centre dot and a sweeping wedge.
static func draw_lens(ci: CanvasItem, pos: Vector2, s: float, alpha: float, sweep: float) -> void:
	if s <= 0.01 or alpha <= 0.0:
		return
	var gold := Color(GOLD.r, GOLD.g, GOLD.b, alpha)
	ci.draw_arc(pos, 13.0 * s, 0.0, TAU, 28, gold, 3.2 * s, true)
	for i in 4:
		var d := Vector2.from_angle(i * PI / 2.0)
		ci.draw_line(pos + d * 15.0 * s, pos + d * 21.0 * s, gold, 3.0 * s, true)
	ci.draw_circle(pos, 3.2 * s, gold)
	ci.draw_arc(pos, 7.5 * s, sweep - 1.0, sweep, 8, Color(1, 1, 1, 0.75 * alpha), 4.0 * s)
