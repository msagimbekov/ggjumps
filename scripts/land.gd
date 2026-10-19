class_name Land
extends Node2D
## One piece of land. The landing test is a point-in-polygon check on its outline.
## Kinds: grass (stops), ice (slides), treadmill (belt carries the bubble), moving (sways sideways).

enum Kind { GRASS, ICE, TREADMILL, MOVING }

const OUTLINE_POINTS := 32
const BELT_SPEED := 35.0
const BELT_HALF := Vector2(56.0, 90.0)  # every treadmill is this size, always vertical
const SWAY_SPEED := 0.9  # rad/s
const SWAY_AMP := 64.0

var index := 0
var kind := Kind.GRASS
var poly := PackedVector2Array()  # local space, rotated and squashed already
var radius_max := 0.0  # farthest outline point from the centre
var amp := 0.0  # sideways sway amplitude, 0 = static
var frame_delta := Vector2.ZERO  # how far a swaying island moved in the last update
var _inner := PackedVector2Array()
var _shallow_far := PackedVector2Array()
var _shallow_near := PackedVector2Array()
var _foam := PackedVector2Array()
var _deco: Array[Vector2] = []
var _rim_color := Color(0.93, 0.85, 0.6)
var _fill_color := Color(0.45, 0.78, 0.38)
var _deco_color := Color(0.33, 0.66, 0.30)
var _rot := 0.0
var _half := Vector2.ZERO  # treadmill half extents (unrotated)
var _belt_sign := 1.0
var _belt := Vector2.ZERO
var _base_x := 0.0
var _sway_phase := 0.0
var _t := 0.0


## `belt_sign` only matters for treadmills: +1 carries the bubble "forward" (up the screen).
func setup(i: int, k: Kind, radius: float, aspect: float, rot: float, seed_value: int, belt_sign := 1.0) -> void:
	index = i
	kind = k
	_rot = rot
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var ph1 := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	_t = rng.randf() * 10.0
	var xf := Transform2D(rot, Vector2.ZERO)
	poly.clear()
	if kind == Kind.TREADMILL:
		_belt_sign = belt_sign
		_belt = Vector2.UP.rotated(rot) * belt_sign
		_half = BELT_HALF
		var corners := [Vector2(-_half.x, -_half.y), Vector2(_half.x, -_half.y), Vector2(_half.x, _half.y), Vector2(-_half.x, _half.y)]
		for c in 4:
			var a: Vector2 = corners[c]
			var b: Vector2 = corners[(c + 1) % 4]
			var steps := ceili(a.distance_to(b) / 22.0)
			for s in steps:
				poly.append(xf * a.lerp(b, float(s) / steps))
		_inner = _offset(poly, -7.0)
	else:
		for n in OUTLINE_POINTS:
			var a := TAU * n / OUTLINE_POINTS
			var rr := radius * (1.0 + 0.09 * sin(a * 3.0 + ph1) + 0.05 * sin(a * 5.0 + ph2))
			poly.append(xf * Vector2(cos(a) * rr, sin(a) * rr * aspect))
		_inner = PackedVector2Array()
		for p in poly:
			_inner.append(p * 0.88)
		for n in 14:
			var c := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * radius
			if Geometry2D.is_point_in_polygon(c, _inner):
				_deco.append(c)
	radius_max = 0.0
	for p in poly:
		radius_max = maxf(radius_max, p.length())
	_shallow_far = _offset(poly, 22.0)
	_shallow_near = _offset(poly, 11.0)
	_foam = _offset(poly, 3.0)
	match kind:
		Kind.ICE:
			_rim_color = Color(0.86, 0.96, 1.0)
			_fill_color = Color(0.70, 0.89, 0.98)
			_deco_color = Color(1, 1, 1, 0.75)
		Kind.TREADMILL:
			_rim_color = Color(0.55, 0.36, 0.20)
			_fill_color = Color(0.36, 0.66, 0.32)
		Kind.MOVING:
			_rim_color = Color(0.55, 0.36, 0.20)
			_fill_color = Color(0.86, 0.68, 0.42)
			_deco_color = Color(0.45, 0.29, 0.16)
	queue_redraw()


## Makes the island sway sideways around its current x. Call after it is positioned.
func setup_motion(phase: float) -> void:
	amp = SWAY_AMP
	_base_x = position.x
	_sway_phase = phase


func set_motion_time(time: float) -> void:
	var nx := _base_x + amp * sin(time * SWAY_SPEED + _sway_phase)
	frame_delta = Vector2(nx - position.x, 0.0)
	position.x = nx


## Unit direction of the belt (treadmills only).
func belt_dir() -> Vector2:
	return _belt


## Where this island pushes whatever stands on it during `delta` seconds.
func carry(delta: float) -> Vector2:
	match kind:
		Kind.TREADMILL:
			return _belt * BELT_SPEED * delta
		Kind.MOVING:
			return frame_delta
	return Vector2.ZERO


func contains_world(p: Vector2) -> bool:
	# Lands are never rotated or scaled, so this also works before the node is in the tree.
	return Geometry2D.is_point_in_polygon(p - position, poly)


func _offset(pg: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := Geometry2D.offset_polygon(pg, d, Geometry2D.JOIN_ROUND)
	return out[0] if out.size() > 0 else pg


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	_draw_shore()
	var shadow := PackedVector2Array()
	for p in poly:
		shadow.append(p + Vector2(5, 9))
	draw_colored_polygon(shadow, Color(0, 0.06, 0.12, 0.28))
	draw_colored_polygon(poly, _rim_color)
	draw_colored_polygon(_inner, _fill_color)
	match kind:
		Kind.GRASS:
			for c in _deco:
				draw_line(c, c + Vector2(-3, -7), _deco_color, 2.0)
				draw_line(c, c + Vector2(3, -8), _deco_color, 2.0)
		Kind.ICE:
			for c in _deco:
				draw_line(c, c + Vector2(12, -6), _deco_color, 2.0)
			if _deco.size() > 0:
				draw_circle(_deco[0] + Vector2(-8, -8), 5.0, Color(1, 1, 1, 0.5))
		Kind.TREADMILL:
			_draw_belt()
		Kind.MOVING:
			_draw_sway()


## Shallows plus waves that roll in and break on the shore.
func _draw_shore() -> void:
	draw_colored_polygon(_shallow_far, Color(0.55, 0.92, 0.95, 0.10))
	draw_colored_polygon(_shallow_near, Color(0.65, 0.95, 0.95, 0.16))
	var foam := 0.0
	for k in 2:
		var u := fposmod(_t * 0.3 + k * 0.5, 1.0)
		var d := lerpf(26.0, 4.0, u * u)
		var a := smoothstep(0.0, 0.25, u) * (1.0 - smoothstep(0.85, 1.0, u))
		foam = maxf(foam, smoothstep(0.7, 0.92, u) * (1.0 - smoothstep(0.92, 1.0, u)))
		for loop in Geometry2D.offset_polygon(poly, d, Geometry2D.JOIN_ROUND):
			var pts := PackedVector2Array(loop)
			pts.append(loop[0])
			var cols := PackedColorArray()
			for n in pts.size():
				cols.append(Color(1, 1, 1, 0.5 * a * (0.55 + 0.45 * sin(n * 0.8 + _t * 2.0 + k * 2.0))))
			draw_polyline_colors(pts, cols, 3.0, true)
	var rim := PackedVector2Array(_foam)
	rim.append(_foam[0])
	draw_polyline(rim, Color(1, 1, 1, 0.35 + 0.5 * foam), 5.0, true)


func _draw_belt() -> void:
	draw_set_transform(Vector2.ZERO, _rot, Vector2.ONE)
	var hw := _half.x
	var hl := _half.y
	var dir := Vector2(0, -_belt_sign)
	var back := -dir
	var step := 34.0
	var span := ceilf(hl * 2.0 / step) * step
	var shift := _t * BELT_SPEED * dir.y
	for k in int(span / step):
		var y := fposmod(k * step + shift, span) - span * 0.5
		var a := clampf((hl - 12.0 - absf(y)) / 18.0, 0.0, 1.0)
		if a <= 0.0:
			continue
		var c := Vector2(0, y)
		var w := hw - 14.0
		var pts := PackedVector2Array([c + Vector2(-w, 0) + back * 11.0, c, c + Vector2(w, 0) + back * 11.0])
		draw_polyline(pts, Color(1.0, 0.82, 0.25, 0.9 * a), 7.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_sway() -> void:
	var n := _inner.size()
	for i in range(0, n, 2):
		draw_line(_inner[i] * 0.93, _inner[(i + 1) % n] * 0.93, _deco_color, 3.0)
