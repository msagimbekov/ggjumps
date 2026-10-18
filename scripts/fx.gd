class_name Fx
extends Node2D
## Aim preview, expanding rings and splash droplets, drawn above the land and below the bubble.

var aiming := false
var aim_from := Vector2.ZERO
var aim_to := Vector2.ZERO

var _rings: Array[Dictionary] = []
var _drops: Array[Dictionary] = []


func ring(p: Vector2, radius := 60.0, col := Color(1, 1, 1, 0.8), dur := 0.6) -> void:
	_rings.append({"p": p, "t": 0.0, "dur": dur, "r": radius, "col": col})


func splash(p: Vector2) -> void:
	ring(p, 70.0, Color(0.85, 0.97, 1.0, 0.9), 0.8)
	ring(p, 40.0, Color(1, 1, 1, 0.7), 0.5)
	for i in 14:
		var v := Vector2.from_angle(randf() * TAU) * randf_range(60.0, 180.0)
		_drops.append({"p": p, "v": v, "t": 0.0, "life": randf_range(0.4, 0.7)})


func _process(delta: float) -> void:
	for r in _rings:
		r.t += delta
	_rings = _rings.filter(func(r): return r.t < r.dur)
	for d in _drops:
		d.t += delta
		d.p += d.v * delta
		d.v *= 0.94
	_drops = _drops.filter(func(d): return d.t < d.life)
	queue_redraw()


func _draw() -> void:
	if aiming:
		var d := aim_to - aim_from
		var n := int(d.length() / 20.0)
		for k in range(1, n + 1):
			var u := float(k) / (n + 1)
			draw_circle(aim_from + d * u, 3.5, Color(1, 1, 1, 0.85 - 0.45 * u))
		draw_arc(aim_to, 16.0, 0.0, TAU, 32, Color(1, 1, 1, 0.85), 3.0)
		draw_circle(aim_to, 3.0, Color(1, 1, 1, 0.9))
	for r in _rings:
		var u: float = r.t / r.dur
		var col: Color = r.col
		col.a *= 1.0 - u
		draw_arc(r.p, r.r * (1.0 - pow(1.0 - u, 2.0)), 0.0, TAU, 40, col, 3.0)
	for d in _drops:
		var u: float = d.t / d.life
		draw_circle(d.p, 3.5 * (1.0 - u), Color(0.85, 0.96, 1.0, 1.0 - u))
