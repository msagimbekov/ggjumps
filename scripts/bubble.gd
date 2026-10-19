class_name Bubble
extends Node2D
## The player: a small liquid bubble. Purely visual; main.gd moves it and sets height/pull/sink.

const R := 22.0
const PULL_REF := 160.0
const POINTS := 28
const REFLECTION_LAYERS := 6

var height := 0.0  # 0 on the ground, up to 1 at the top of a jump
var pull := Vector2.ZERO  # drag vector while aiming (bubble to pointer)
var sink := 0.0  # 0..1 while falling into the water
var squash := 0.0  # landing squash, tweened back to 0
var on_land := true  # set by main.gd: is there land under the bubble
var ground := 1.0  # on_land eased, so shadow and reflection cross-fade at island edges
var _t := 0.0


func land_squash() -> void:
	squash = 0.45
	var tw := create_tween()
	tw.tween_property(self, "squash", 0.0, 0.55).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func reset() -> void:
	height = 0.0
	pull = Vector2.ZERO
	sink = 0.0
	squash = 0.0


func _process(delta: float) -> void:
	_t += delta
	ground = move_toward(ground, 1.0 if on_land else 0.0, delta * 8.0)
	queue_redraw()


func _draw() -> void:
	var al := 1.0 - sink
	var sc := (1.0 + height * 0.4) * (1.0 - sink * 0.6)

	var below := Vector2(0, 7 + height * 34)
	# Shadow only falls on land and shrinks/fades as the bubble rises.
	if ground > 0.01:
		draw_set_transform(below, 0.0, Vector2(1.0, 0.6) * (1.0 - height * 0.25))
		draw_circle(Vector2.ZERO, R * 0.95, Color(0, 0, 0, 0.28 * al * ground))
	# Over water it is a reflection instead: the higher the bubble, the smaller, fainter and
	# blurrier (soft edge built from stacked discs); near the surface it is almost bubble-sized.
	var water := 1.0 - ground
	if water > 0.01:
		var rs := lerpf(1.0, 0.5, height)
		var blur := height * 0.9 + 0.12
		var base := lerpf(0.55, 0.12, height) * al * water
		draw_set_transform(below, 0.0, Vector2(1.0, 0.85))
		for k in REFLECTION_LAYERS:
			var u := float(k) / (REFLECTION_LAYERS - 1)
			var rr := R * rs * (1.0 + blur * (1.0 - u))
			draw_circle(Vector2.ZERO, rr, Color(0.55, 0.9, 1.0, base / REFLECTION_LAYERS * 1.8))

	var offset := Vector2(0, -height * 46) + pull * 0.18
	var angle := 0.0
	var scl := Vector2.ONE
	var p := clampf(pull.length() / PULL_REF, 0.0, 1.0)
	if pull.length() > 1.0:
		angle = pull.angle()
		scl = Vector2(1.0 - 0.22 * p, 1.0 + 0.16 * p)
	else:
		scl = Vector2(1.0 + squash * 0.5, 1.0 - squash * 0.5)
	draw_set_transform(offset, angle, scl * sc)

	var pts := PackedVector2Array()
	for n in POINTS:
		var a := TAU * n / POINTS
		var r := R * (1.0 + 0.05 * sin(a * 3.0 + _t * 4.0) + 0.035 * sin(a * 5.0 - _t * 3.3))
		pts.append(Vector2(cos(a), sin(a)) * r)
	var core := PackedVector2Array()
	for q in pts:
		core.append(q * 0.7 + Vector2(-2.0, -3.5))
	draw_colored_polygon(pts, Color(0.30, 0.80, 1.0, 0.9 * al))
	draw_colored_polygon(core, Color(0.62, 0.95, 1.0, 0.5 * al))
	var ring := pts.duplicate()
	ring.append(pts[0])
	draw_polyline(ring, Color(0.10, 0.50, 0.80, 0.9 * al), 2.0)
	draw_circle(Vector2(-7, -8), 5.5, Color(1, 1, 1, 0.85 * al))
	draw_circle(Vector2(5, 8), 2.4, Color(1, 1, 1, 0.5 * al))
