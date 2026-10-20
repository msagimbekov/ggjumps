extends Node2D
## Fireworks over the screen when the bubble lands on the last island: rockets climb with a sparkling trail
## and burst into rings of falling, twinkling stars. Drawn in screen space (UI layer).
## `finished` fires once the show has had its moment; the last sparks keep fading after it.

signal finished

const ROCKETS := 10
const SHOW_TIME := 4.2  # seconds until `finished`
const GRAVITY := 170.0
const COLORS := [
	Color(1.0, 0.82, 0.25), Color(1.0, 0.52, 0.45), Color(0.55, 0.93, 0.72),
	Color(0.45, 0.80, 1.0), Color(1.0, 0.60, 0.85), Color(1.0, 1.0, 1.0),
]

var play_sound: Callable  # (name, volume_db, pitch)
var _t := 0.0
var _launches: Array[float] = []
var _rockets: Array[Dictionary] = []
var _sparks: Array[Dictionary] = []
var _done := false


func start() -> void:
	_t = 0.0
	_done = false
	_launches.clear()
	for k in ROCKETS:
		_launches.append(k * 0.32 + randf_range(0.0, 0.2))
	set_process(true)


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	_t += delta
	var view := get_viewport_rect().size
	while not _launches.is_empty() and _launches[0] <= _t:
		_launches.pop_front()
		var from := Vector2(randf_range(80.0, view.x - 80.0), view.y + 10.0)
		var to := Vector2(from.x + randf_range(-60.0, 60.0), randf_range(view.y * 0.15, view.y * 0.45))
		_rockets.append({"from": from, "to": to, "t": 0.0, "dur": randf_range(0.8, 1.1), "col": COLORS.pick_random()})
		_sound("fw_launch", -8.0, randf_range(0.9, 1.15))
	for r in _rockets:
		r.t += delta
		var u: float = minf(r.t / r.dur, 1.0)
		var e := 1.0 - pow(1.0 - u, 2.0)  # slows as it climbs
		r.p = (r.from as Vector2).lerp(r.to, e)
		if randf() < 0.8:
			_sparks.append({"p": r.p, "v": Vector2(randf_range(-20, 20), randf_range(20, 60)), "life": 0.0, "max": 0.4, "col": Color(1, 0.9, 0.6), "r": 1.6, "drag": 0.5})
		if u >= 1.0:
			_burst(r.p, r.col)
	_rockets = _rockets.filter(func(r): return r.t < r.dur)
	for s in _sparks:
		s.life += delta
		s.v *= pow(s.drag, delta)
		s.v.y += GRAVITY * delta
		s.p += s.v * delta
	_sparks = _sparks.filter(func(s): return s.life < s.max)
	if not _done and _t >= SHOW_TIME:
		_done = true
		finished.emit()
	if _done and _rockets.is_empty() and _sparks.is_empty() and _launches.is_empty():
		set_process(false)
	queue_redraw()


func _burst(p: Vector2, col: Color) -> void:
	var count := randi_range(46, 64)
	var speed := randf_range(170.0, 240.0)
	var second: Color = COLORS.pick_random()
	for k in count:
		var a := TAU * k / count + randf_range(-0.05, 0.05)
		var v := Vector2.from_angle(a) * speed * randf_range(0.85, 1.0)
		_sparks.append({"p": p, "v": v, "life": 0.0, "max": randf_range(1.3, 1.9), "col": col if k % 3 else second, "r": randf_range(2.2, 3.2), "drag": 0.25})
	# A soft inner puff.
	for k in 14:
		_sparks.append({"p": p, "v": Vector2.from_angle(randf() * TAU) * randf_range(20.0, 80.0), "life": 0.0, "max": 0.9, "col": Color(1, 1, 0.9), "r": 2.0, "drag": 0.3})
	_sound("fw_burst", -2.0, randf_range(0.85, 1.15))


func _sound(name: String, db: float, pitch: float) -> void:
	if play_sound.is_valid():
		play_sound.call(name, db, pitch)


func _draw() -> void:
	for r in _rockets:
		var p: Vector2 = r.p
		draw_circle(p, 3.0, Color(1, 0.95, 0.8))
	for s in _sparks:
		var u: float = s.life / s.max
		var col: Color = s.col
		var twinkle := 0.75 + 0.25 * sin(s.life * 40.0 + s.p.x)
		col.a = (1.0 - u * u) * twinkle
		var tail: Vector2 = s.v * 0.045
		draw_line(s.p - tail, s.p, Color(col.r, col.g, col.b, col.a * 0.5), s.r, true)
		draw_circle(s.p, s.r * (1.0 - 0.4 * u), col)
		if u < 0.15:
			draw_circle(s.p, s.r * 2.2, Color(col.r, col.g, col.b, 0.25 * (1.0 - u / 0.15)))
