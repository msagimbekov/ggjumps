class_name Critters
extends Node2D
## Fish under the water surface, and now and then one that leaps out and dives back in.
## Must sit below the lands in the tree so islands cover the swimmers.

const SWIMMERS := 8

var fx: Fx
var focus := Vector2.ZERO  # world position the fish keep around (the camera focus)
var water_at := Callable()  # (Vector2, margin) -> bool: open water, no land within margin

var _swim: Array[Dictionary] = []
var _leaps: Array[Dictionary] = []
var _next_leap := 2.5
var _t := 0.0


func _ready() -> void:
	for i in SWIMMERS:
		_swim.append(_new_swimmer(randf_range(-650.0, 650.0)))


func _new_swimmer(dy: float) -> Dictionary:
	return {
		"p": Vector2(randf_range(0.0, 540.0), focus.y + dy), "a": randf() * TAU,
		"spd": randf_range(22.0, 48.0), "len": randf_range(24.0, 42.0),
		"ph": randf() * TAU, "turn": randf_range(-0.4, 0.4),
	}


func _process(delta: float) -> void:
	_t += delta
	for f in _swim:
		f.a += (f.turn + sin(_t * 0.5 + f.ph) * 0.6) * delta
		f.p += Vector2.from_angle(f.a) * f.spd * delta
		f.ph += delta * (5.0 + f.spd * 0.12)
		if f.p.x < -40.0 or f.p.x > 580.0:
			f.a = PI - f.a
			f.p.x = clampf(f.p.x, -40.0, 580.0)
	for i in _swim.size():
		if absf(_swim[i].p.y - focus.y) > 800.0:
			_swim[i] = _new_swimmer(signf(randf() - 0.5) * randf_range(450.0, 650.0))
	_next_leap -= delta
	if _next_leap <= 0.0:
		_next_leap = randf_range(2.5, 6.0)
		_try_leap()
	for l in _leaps:
		l.t += delta
		if l.t >= l.dur:
			fx.splash(l.p1, 0.45)
	_leaps = _leaps.filter(func(l): return l.t < l.dur)
	queue_redraw()


func _try_leap() -> void:
	if not water_at.is_valid():
		return
	for k in 10:
		var p := Vector2(randf_range(40.0, 500.0), focus.y + randf_range(-420.0, 260.0))
		var d := Vector2.from_angle(randf() * TAU) * randf_range(60.0, 95.0)
		if water_at.call(p, 30.0) and water_at.call(p + d, 30.0) and water_at.call(p + d * 0.5, 30.0):
			_leaps.append({"p0": p, "p1": p + d, "t": 0.0, "dur": 0.9, "h": randf_range(40.0, 60.0)})
			fx.splash(p, 0.45)
			return


## A leap from `p` (a double tap on the water): it dives back in a little way off, over open
## water when there is a way to.
func leap_at(p: Vector2) -> void:
	var d := Vector2.from_angle(randf() * TAU) * 70.0
	if water_at.is_valid():
		for k in 10:
			var off := Vector2.from_angle(randf() * TAU) * randf_range(60.0, 95.0)
			if water_at.call(p + off, 30.0) and water_at.call(p + off * 0.5, 30.0):
				d = off
				break
	_leaps.append({"p0": p, "p1": p + d, "t": 0.0, "dur": 0.9, "h": randf_range(40.0, 60.0)})
	fx.splash(p, 0.45)


func _draw() -> void:
	for f in _swim:
		_fish(f.p, f.a, f.len, f.ph, Color(0.02, 0.18, 0.30, 0.38), Color(0.02, 0.18, 0.30, 0.30))
	for l in _leaps:
		var u: float = l.t / l.dur
		var ground: Vector2 = l.p0.lerp(l.p1, u)
		var z: float = l.h * 4.0 * u * (1.0 - u)
		var vel: Vector2 = (l.p1 - l.p0) + Vector2(0, -l.h * 4.0 * (1.0 - 2.0 * u))
		draw_set_transform(ground + Vector2(0, 4), 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, 12.0 * (1.0 - z / 120.0), Color(0, 0.1, 0.2, 0.22))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_fish(ground + Vector2(0, -z), vel.angle(), 34.0, _t * 30.0, Color(0.80, 0.90, 0.97), Color(1.0, 0.65, 0.35))


func _fish(pos: Vector2, ang: float, len: float, wiggle: float, body: Color, fin: Color) -> void:
	draw_set_transform(pos, ang, Vector2.ONE)
	var shape := PackedVector2Array()
	for n in 12:
		var a := TAU * n / 12.0
		shape.append(Vector2(cos(a) * len * 0.5, sin(a) * len * 0.17))
	draw_colored_polygon(shape, body)
	var w := sin(wiggle) * len * 0.1
	draw_colored_polygon(PackedVector2Array([
		Vector2(-len * 0.4, 0), Vector2(-len * 0.72, -len * 0.2 + w), Vector2(-len * 0.64, w), Vector2(-len * 0.72, len * 0.2 + w),
	]), fin)
	draw_colored_polygon(PackedVector2Array([Vector2(len * 0.1, -len * 0.14), Vector2(-len * 0.1, -len * 0.28), Vector2(-len * 0.18, -len * 0.14)]), fin)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
