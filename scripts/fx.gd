class_name Fx
extends Node2D
## Drag indicator, rings and water splashes, drawn above the land and below the bubble.

const GRAVITY := 900.0
const ARC_COUNT := 7
const ARC_WIDTH := 2.5
## All the drag arcs together are at most two bubble diameters wide.
const ARC_BAND := Bubble.R * 2.2

## Quarter circles around the bubble towards the jump direction; more drag, more arcs.
var arcs_on := false
var arcs_from := Vector2.ZERO
var arcs_angle := 0.0
var arcs_power := 0.0
## Test aid: landing line + reticle.
var aiming := false
var aim_from := Vector2.ZERO
var aim_to := Vector2.ZERO

var _rings: Array[Dictionary] = []
var _drops: Array[Dictionary] = []
var _jets: Array[Dictionary] = []


func ring(p: Vector2, radius := 60.0, col := Color(1, 1, 1, 0.8), dur := 0.6, squash := 1.0) -> void:
	_rings.append({"p": p, "t": 0.0, "dur": dur, "r": radius, "col": col, "sq": squash})


## A water splash: rings, a rising jet and a crown of droplets that fly out and fall back.
func splash(p: Vector2, k := 1.0, rise := -1.0) -> void:
	if rise < 0.0:
		rise = k
	ring(p, 80.0 * k, Color(0.85, 0.97, 1.0, 0.9), 0.9, 0.55)
	ring(p, 46.0 * k, Color(1, 1, 1, 0.7), 0.6, 0.55)
	_jets.append({"p": p, "t": 0.0, "dur": 0.6, "k": rise})
	var crown := int(18.0 * k) + 4
	for i in crown:
		var a := TAU * i / crown + randf_range(-0.15, 0.15)
		var sp := randf_range(60.0, 125.0) * k
		_drops.append({"p": p, "z": 2.0, "vz": randf_range(230.0, 340.0) * sqrt(rise), "v": Vector2.from_angle(a) * sp, "r": randf_range(2.2, 3.6) * sqrt(k)})
	for i in int(6.0 * k) + 2:
		var v := Vector2.from_angle(randf() * TAU) * randf_range(8.0, 35.0) * k
		_drops.append({"p": p, "z": 6.0, "vz": randf_range(380.0, 520.0) * sqrt(rise), "v": v, "r": randf_range(3.0, 4.6) * sqrt(k)})


func _process(delta: float) -> void:
	for r in _rings:
		r.t += delta
	_rings = _rings.filter(func(r): return r.t < r.dur)
	for j in _jets:
		j.t += delta
	_jets = _jets.filter(func(j): return j.t < j.dur)
	var landed: Array[Dictionary] = []
	for d in _drops:
		d.p += d.v * delta
		d.z += d.vz * delta
		d.vz -= GRAVITY * delta
		if d.z <= 0.0 and d.vz < 0.0:
			landed.append(d)
	for d in landed:
		_drops.erase(d)
		ring(d.p, 7.0 + d.r * 2.0, Color(1, 1, 1, 0.6), 0.35, 0.6)
	queue_redraw()


func _draw() -> void:
	if arcs_on:
		_draw_arcs()
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
		draw_set_transform(r.p, 0.0, Vector2(1.0, r.sq))
		draw_arc(Vector2.ZERO, r.r * (1.0 - pow(1.0 - u, 2.0)), 0.0, TAU, 40, col, 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for j in _jets:
		_draw_jet(j)
	for d in _drops:
		var pos: Vector2 = d.p + Vector2(0, -d.z)
		var vel: Vector2 = d.v + Vector2(0, -d.vz)
		draw_circle(d.p, d.r * 0.8, Color(0, 0.1, 0.2, 0.12))
		draw_line(pos, pos - vel * 0.025, Color(0.85, 0.96, 1.0, 0.7), d.r * 1.3)
		draw_circle(pos, d.r, Color(0.92, 0.98, 1.0, 0.95))


## Soft palette taken from the game: sea-foam mint, beach sand, coral.
func _tone(u: float) -> Color:
	var mint := Color(0.55, 0.93, 0.72)
	var sand := Color(0.98, 0.88, 0.55)
	var coral := Color(1.0, 0.52, 0.45)
	return mint.lerp(sand, u * 2.0) if u < 0.5 else sand.lerp(coral, u * 2.0 - 1.0)


## Power gauge: a stack of chevrons pointing along the jump, growing and turning from green to
## red as the drag gets longer. Dark outlines keep them readable on any water.
func _draw_arcs() -> void:
	var dir := Vector2.from_angle(arcs_angle)
	var step := (ARC_BAND - ARC_WIDTH) / (ARC_COUNT - 1)
	var shown := arcs_power * ARC_COUNT
	for k in ARC_COUNT:
		var a := clampf(shown - k, 0.0, 1.0)
		if a <= 0.0:
			break
		var tip := arcs_from + dir * (Bubble.R + 14.0 + k * step)
		var r := Bubble.R + 14.0 + k * step
		var lat := r * 0.24 * (0.6 + 0.4 * a)  # half width: a third of a quarter circle's
		var w1 := tip - dir * lat * 0.7 + dir.orthogonal() * lat
		var w2 := tip - dir * lat * 0.7 - dir.orthogonal() * lat
		var pts := PackedVector2Array([w1, tip, w2])
		var tone := _tone(float(k) / (ARC_COUNT - 1))
		draw_polyline(pts, Color(0, 0.08, 0.16, 0.4 * a), ARC_WIDTH + 3.0, true)
		for q in pts:
			draw_circle(q, (ARC_WIDTH + 3.0) * 0.5, Color(0, 0.08, 0.16, 0.4 * a))
		draw_polyline(pts, Color(tone.r, tone.g, tone.b, a), ARC_WIDTH, true)
		for q in pts:
			draw_circle(q, ARC_WIDTH * 0.5, Color(tone.r, tone.g, tone.b, a))


## The water column thrown up where something hits the surface.
func _draw_jet(j: Dictionary) -> void:
	var u: float = j.t / j.dur
	var k: float = j.k
	var h := 58.0 * k * pow(sin(PI * u), 0.8)
	var w := 14.0 * k * (1.0 - 0.5 * u)
	var p: Vector2 = j.p
	var fade := 1.0 - u * 0.6
	var shape := PackedVector2Array([
		p + Vector2(-w * 1.3, 0), p + Vector2(-w, -h * 0.5), p + Vector2(-w * 0.45, -h * 0.9),
		p + Vector2(0, -h - 4.0 * k), p + Vector2(w * 0.45, -h * 0.9), p + Vector2(w, -h * 0.5), p + Vector2(w * 1.3, 0),
	])
	if h > 2.0:
		draw_colored_polygon(shape, Color(0.80, 0.94, 1.0, 0.75 * fade))
		draw_colored_polygon(PackedVector2Array([p + Vector2(-w * 0.4, -2), p + Vector2(0, -h * 0.9), p + Vector2(w * 0.4, -2)]), Color(1, 1, 1, 0.55 * fade))
