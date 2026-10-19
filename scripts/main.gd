extends Node2D
## Game orchestrator: level layout, drag-to-jump input, flight / slide / fall states, lives.
## The jump is a plain arc computed from the drag (no rigid body): direction = opposite of the
## drag, distance = drag length * MAX_RANGE. Landing = the bubble's centre inside a land polygon.

const TOTAL_JUMPS := 99
const START_LIVES := 3
const MAX_RANGE := 470.0  # jump distance at full drag
const MAX_DRAG := 160.0
const MIN_DRAG := 24.0  # shorter drags cancel the jump
const GRAB_RADIUS := 80.0
const SLIDE_SPEED := 560.0
const ICE_DECEL := 650.0
const GRASS_DECEL := 3200.0
const LEVEL_SEED := 99
const LEVEL_ATTEMPTS := 60
const SOLVE_MIN_WINDOW := 8  # in 1% power steps (~38 px of landing tolerance)
const SOLVE_MIN_WINDOW_OFFSET := 4
## Landing line + reticle while dragging. A test aid: switch off for production builds so
## players have to judge the jump by feel.
const SHOW_AIM_LINE := true

enum State { AIM, FLY, SLIDE, FALL, OVER, WON }

var state := State.AIM
var lands: Array[Land] = []
var cur := 0  # land the bubble last settled on
var best := 0  # highest land reached = jumps made
var lives := START_LIVES

var _cam: Camera2D
var _fx: Fx
var _bubble: Bubble
var _hud: Hud
var _water: ColorRect
var _water_mat: ShaderMaterial

var _dragging := false
var _drag := Vector2.ZERO  # bubble to pointer, clamped to MAX_DRAG
var _fly_from := Vector2.ZERO
var _fly_to := Vector2.ZERO
var _fly_dir := Vector2.UP
var _fly_power := 0.0
var _fly_t := 0.0
var _fly_dur := 0.5
var _slide_vel := Vector2.ZERO
var _fall_t := 0.0
var _time := 0.0


func _ready() -> void:
	_build_nodes()
	_build_level()
	_restart()


func _build_nodes() -> void:
	var bg := CanvasLayer.new()
	bg.layer = -10
	add_child(bg)
	_water = ColorRect.new()
	_water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = load("res://shaders/water.gdshader")
	_water.material = _water_mat
	bg.add_child(_water)
	_water.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_cam = Camera2D.new()
	_cam.position_smoothing_enabled = true
	_cam.position_smoothing_speed = 4.0
	add_child(_cam)
	_cam.make_current()

	_fx = Fx.new()
	_bubble = Bubble.new()
	# Order matters: lands (added in _build_level) < fx < bubble.
	_fx.z_index = 1
	_bubble.z_index = 2
	add_child(_fx)
	add_child(_bubble)

	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	_hud = Hud.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.total = TOTAL_JUMPS
	_hud.max_lives = START_LIVES
	ui.add_child(_hud)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var win_h := float(DisplayServer.window_get_size().y)
	if win_h > 0.0:
		var inset := float(DisplayServer.get_display_safe_area().position.y)
		_hud.top_inset = inset * get_viewport_rect().size.y / win_h


## Same layout on every device: one seeded RNG, always drawing the same numbers per land.
func _build_level() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = LEVEL_SEED
	var pos := Vector2(270, 0)
	_add_land(_make_land(0, Land.Kind.GRASS, pos, 120.0, 1.0, 0.0))
	for i in range(1, TOTAL_JUMPS + 1):
		var t := float(i) / TOTAL_JUMPS
		var prev_radius := _land_radius(lands[i - 1])
		var l: Land = null
		# Reroll an ice island nobody can stop on; after enough tries fall back to grass.
		for attempt in LEVEL_ATTEMPTS:
			var gap := rng.randf_range(lerpf(60.0, 130.0, t), lerpf(110.0, 230.0, t))  # water between the edges
			var ang := -PI / 2.0 + rng.randf_range(-0.7, 0.7)
			var radius := lerpf(100.0, 48.0, t) * rng.randf_range(0.9, 1.1)
			var dist := prev_radius + radius + gap
			var thin_roll := rng.randf()
			var ice_roll := rng.randf()
			var rot := rng.randf() * PI
			var dir := Vector2.from_angle(ang)
			var next := pos + dir * dist
			if next.x < 80.0 or next.x > 460.0:
				dir.x = -dir.x
				next = pos + dir * dist
				next.x = clampf(next.x, 80.0, 460.0)
			var thin := i >= 6 and thin_roll < lerpf(0.05, 0.45, t)
			var ice := i >= 10 and ice_roll < lerpf(0.1, 0.5, t)
			var kind := Land.Kind.ICE if ice else Land.Kind.GRASS
			if attempt == LEVEL_ATTEMPTS - 1:
				kind = Land.Kind.GRASS
			if l:
				l.free()
			l = _make_land(i, kind, next, radius, 0.55 if thin else 1.0, rot)
			if _is_solvable(lands[i - 1], l):
				break
		_add_land(l)
		pos = l.position


func _make_land(i: int, kind: Land.Kind, at: Vector2, radius: float, aspect: float, rot: float) -> Land:
	var l := Land.new()
	l.position = at
	l.setup(i, kind, radius, aspect, rot, LEVEL_SEED * 1000 + i)
	return l


func _add_land(l: Land) -> void:
	add_child(l)
	lands.append(l)


func _land_radius(l: Land) -> float:
	var r := 0.0
	for p in l.poly:
		r = maxf(r, p.length())
	return r


## Whether a jump from `from` can end up settled on `to`. Tries start spots across the
## previous island (centre and 55% towards / away from the target), aiming at a few points
## of the target, and sweeps the power. Needs a window of powers wide enough to hit by hand.
func _is_solvable(from: Land, to: Land) -> bool:
	var axis := (to.position - from.position).normalized()
	var r := _land_radius(from)
	var starts := [from.position, from.position + axis * r * 0.55, from.position - axis * r * 0.55]
	for s: Vector2 in starts:
		if not from.contains_world(s):
			continue
		var need := SOLVE_MIN_WINDOW if s == from.position else SOLVE_MIN_WINDOW_OFFSET
		if _best_window(s, to) < need:
			return false
	return true


func _best_window(s: Vector2, to: Land) -> int:
	var r := _land_radius(to)
	var best_count := 0
	for off: float in [0.0, -0.4, 0.4]:
		var side := (to.position - s).normalized().orthogonal()
		var dir := (to.position + side * off * r - s).normalized()
		var count := 0
		var run := 0
		for k in range(int(MIN_DRAG / MAX_DRAG * 100.0) + 1, 101):
			if _jump_settles(s, dir, k / 100.0, to):
				run += 1
				count = maxi(count, run)
			else:
				run = 0
		best_count = maxi(best_count, count)
	return best_count


## Mirrors _on_landed / SLIDE: does a jump of this power end settled on `to`?
func _jump_settles(s: Vector2, dir: Vector2, power: float, to: Land) -> bool:
	var p := s + dir * power * MAX_RANGE
	if not to.contains_world(p):
		return false
	if to.kind != Land.Kind.ICE or power <= 0.12:
		return true
	# Constant deceleration: the slide is a straight line that stops below 8 px/s.
	var speed := power * SLIDE_SPEED
	var run := maxf(speed * speed - 64.0, 0.0) / (2.0 * ICE_DECEL)
	for k in range(1, 9):
		if not to.contains_world(p + dir * run * k / 8.0):
			return false
	return true


## Debug aid: the widest-run of workable powers for every jump, worst first. Run headless via
## `godot --headless --script scripts/verify_levels.gd`.
func verify_levels() -> Array:
	var rows := []
	for i in range(1, lands.size()):
		var s := lands[i - 1].position
		rows.append([_best_window(s, lands[i]), i, lands[i].kind])
	rows.sort()
	return rows


func _restart() -> void:
	lives = START_LIVES
	cur = 0
	best = 0
	_dragging = false
	_drag = Vector2.ZERO
	_bubble.reset()
	_bubble.position = lands[0].position
	_bubble.land_squash()
	state = State.AIM
	_cam.global_position = _cam_target()
	_cam.reset_smoothing()


func _cam_target() -> Vector2:
	var focus := lands[cur].position
	if state == State.FLY or state == State.SLIDE:
		focus = _bubble.position
	# Scrolls vertically only: the level is laid out inside the 540 px wide viewport.
	return Vector2(270.0, focus.y - get_viewport_rect().size.y * 0.2)


func _land_at(p: Vector2) -> Land:
	for i in range(maxi(cur - 4, 0), mini(cur + 7, lands.size())):
		if lands[i].contains_world(p):
			return lands[i]
	return null


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if state == State.OVER or state == State.WON:
				_restart()
			elif state == State.AIM and get_global_mouse_position().distance_to(_bubble.position) <= GRAB_RADIUS:
				_dragging = true
				_drag = Vector2.ZERO
		elif _dragging:
			_dragging = false
			var v := -_drag
			_drag = Vector2.ZERO
			_bubble.pull = Vector2.ZERO
			if state == State.AIM and v.length() >= MIN_DRAG:
				_jump(v)
	elif event is InputEventMouseMotion and _dragging:
		_drag = (get_global_mouse_position() - _bubble.position).limit_length(MAX_DRAG)


func _jump(v: Vector2) -> void:
	_fly_power = clampf(v.length() / MAX_DRAG, 0.0, 1.0)
	_fly_dir = v.normalized()
	_fly_from = _bubble.position
	_fly_to = _fly_from + _fly_dir * _fly_power * MAX_RANGE
	_fly_dur = 0.28 + 0.4 * _fly_power
	_fly_t = 0.0
	_fx.ring(_fly_from, 34.0, Color(1, 1, 1, 0.6), 0.4)
	state = State.FLY


func _process(delta: float) -> void:
	_time += delta
	match state:
		State.FLY:
			_fly_t += delta
			var u := clampf(_fly_t / _fly_dur, 0.0, 1.0)
			_bubble.position = _fly_from.lerp(_fly_to, u)
			_bubble.height = sin(PI * u) * (0.35 + 0.65 * _fly_power)
			if u >= 1.0:
				_on_landed()
		State.SLIDE:
			_bubble.position += _slide_vel * delta
			var l := _land_at(_bubble.position)
			if l == null:
				_start_fall()
			else:
				var decel := ICE_DECEL if l.kind == Land.Kind.ICE else GRASS_DECEL
				_slide_vel = _slide_vel.move_toward(Vector2.ZERO, decel * delta)
				if _slide_vel.length() < 8.0:
					_settle(l)
		State.FALL:
			_fall_t += delta
			_bubble.sink = clampf(_fall_t / 0.5, 0.0, 1.0)
			if _fall_t >= 1.0:
				_after_fall()

	_bubble.on_land = _land_at(_bubble.position) != null
	_bubble.pull = _drag if _dragging else Vector2.ZERO
	_fx.aiming = SHOW_AIM_LINE and _dragging and _drag.length() >= MIN_DRAG
	if _fx.aiming:
		_fx.aim_from = _bubble.position
		_fx.aim_to = _bubble.position - _drag.normalized() * (_drag.length() / MAX_DRAG) * MAX_RANGE

	_cam.position = _cam_target()
	var view := get_viewport_rect().size
	var top_left := _cam.get_screen_center_position() - view / 2.0
	_water_mat.set_shader_parameter("origin", top_left)
	_water_mat.set_shader_parameter("area", view)
	_water_mat.set_shader_parameter("t", _time)

	var title := ""
	var sub := ""
	if state == State.OVER:
		title = "Splash!"
		sub = "Tap to try again"
	elif state == State.WON:
		title = "All %d jumps!" % TOTAL_JUMPS
		sub = "Tap to play again"
	_hud.set_info(best, lives, title, sub)


func _on_landed() -> void:
	_bubble.height = 0.0
	var l := _land_at(_bubble.position)
	if l == null:
		_start_fall()
	elif l.kind == Land.Kind.ICE and _fly_power > 0.12:
		_slide_vel = _fly_dir * _fly_power * SLIDE_SPEED
		_bubble.land_squash()
		state = State.SLIDE
	else:
		_settle(l)


func _settle(l: Land) -> void:
	cur = l.index
	_bubble.land_squash()
	_fx.ring(_bubble.position, 44.0, Color(1, 1, 1, 0.7), 0.5)
	if cur > best:
		best = cur
	state = State.WON if best >= TOTAL_JUMPS else State.AIM


func _start_fall() -> void:
	lives -= 1
	_fall_t = 0.0
	_fx.splash(_bubble.position)
	state = State.FALL


func _after_fall() -> void:
	if lives <= 0:
		state = State.OVER
		return
	_bubble.reset()
	_bubble.position = lands[cur].position
	_bubble.land_squash()
	state = State.AIM
