class_name Land
extends Node2D
## One piece of land. The landing test is a point-in-polygon check on its blobby outline.

enum Kind { GRASS, ICE }

const OUTLINE_POINTS := 32

var index := 0
var kind := Kind.GRASS
var poly := PackedVector2Array()  # local space, rotated and squashed already
var _inner := PackedVector2Array()
var _deco: Array[Vector2] = []
var _rim_color := Color(0.93, 0.85, 0.6)
var _fill_color := Color(0.45, 0.78, 0.38)
var _deco_color := Color(0.33, 0.66, 0.30)


func setup(i: int, k: Kind, radius: float, aspect: float, rot: float, seed_value: int) -> void:
	index = i
	kind = k
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var ph1 := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	var xf := Transform2D(rot, Vector2.ZERO)
	poly.clear()
	for n in OUTLINE_POINTS:
		var a := TAU * n / OUTLINE_POINTS
		var rr := radius * (1.0 + 0.09 * sin(a * 3.0 + ph1) + 0.05 * sin(a * 5.0 + ph2))
		poly.append(xf * Vector2(cos(a) * rr, sin(a) * rr * aspect))
	_inner = PackedVector2Array()
	for p in poly:
		_inner.append(p * 0.88)
	_deco.clear()
	for n in 14:
		var c := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * radius
		if Geometry2D.is_point_in_polygon(c, _inner):
			_deco.append(c)
	if kind == Kind.ICE:
		_rim_color = Color(0.86, 0.96, 1.0)
		_fill_color = Color(0.70, 0.89, 0.98)
		_deco_color = Color(1, 1, 1, 0.75)
	queue_redraw()


func contains_world(p: Vector2) -> bool:
	# Lands are never rotated or scaled, so this also works before the node is in the tree.
	return Geometry2D.is_point_in_polygon(p - position, poly)


func _draw() -> void:
	var shadow := PackedVector2Array()
	for p in poly:
		shadow.append(p + Vector2(5, 9))
	draw_colored_polygon(shadow, Color(0, 0.06, 0.12, 0.28))
	draw_colored_polygon(poly, _rim_color)
	draw_colored_polygon(_inner, _fill_color)
	if kind == Kind.GRASS:
		for c in _deco:
			draw_line(c, c + Vector2(-3, -7), _deco_color, 2.0)
			draw_line(c, c + Vector2(3, -8), _deco_color, 2.0)
	else:
		for c in _deco:
			draw_line(c, c + Vector2(12, -6), _deco_color, 2.0)
		if _deco.size() > 0:
			draw_circle(_deco[0] + Vector2(-8, -8), 5.0, Color(1, 1, 1, 0.5))
