extends Node2D
## Game orchestrator: level layout, drag-to-jump input, flight / slide / fall states, lives.
## The jump is a plain arc computed from the drag (no rigid body): direction = opposite of the
## drag, distance = drag length * MAX_RANGE. Landing = the bubble's centre inside a land polygon.

const TOTAL_JUMPS := 99
const START_LIVES := 3
const MAX_RANGE := 418.0  # jump distance at full drag
const MAX_DRAG := 160.0
const MIN_DRAG := 24.0  # shorter drags cancel the jump
const GRAB_RADIUS := 90.0
const NO_AD_FROM := 90  # from this island on, running out of lives means starting over (no ad)
const DOUBLE_TAP := 0.35  # seconds between the taps of a double tap on the water (a fish leaps there)
const SLIDE_SPEED := 560.0
const ICE_DECEL := 650.0
const ICE_SCALE := 1.05
const EDGE_NUDGE := [25, 36, 70]  # islands that sat too close to the screen edge
const GRASS_DECEL := 3200.0
const LEVEL_SEED := 99
const LEVEL_ATTEMPTS := 60
const SOLVE_MIN_WINDOW := 8  # in 1% power steps (~38 px of landing tolerance)
const SOLVE_MIN_WINDOW_OFFSET := 4
const SKIP_MARGIN := 10.0  # islands two apart must be farther than MAX_RANGE by this much
const TREADMILLS := false  # treadmill islands work but made the game too hard; off for now
const LIFE_PICKUPS := 18  # drops in the level; three give a life
const RADAR_PICKUPS := 9
const DROPS_PER_LIFE := 3
const RADAR_TIME := 7.0  # seconds; pulses softly for the last two
const COLLECT_RADIUS := 34.0  # settle this close to a pickup centre to collect it
const RADAR_PING := 1.75  # seconds between the soft sonar pings while the radar runs
const AIM_TAPS := 5  # taps on the lives icons that show the tools buttons
const HIDE_TAPS := 3  # taps that hide them again and reset the tools

enum State { AIM, FLY, SLIDE, FALL, OVER, WON }

# Preloaded by path, not class_name: new global classes would change the OTA build shape.
const LeaderboardApi := preload("res://scripts/leaderboard.gd")
const LeaderboardView := preload("res://scripts/ui/leaderboard_view.gd")
const Congrats := preload("res://scripts/ui/congrats.gd")
const Intro := preload("res://scripts/ui/intro.gd")
const HowTo := preload("res://scripts/ui/how_to.gd")
const WaterView := preload("res://scripts/water_view.gd")
const Fireworks := preload("res://scripts/fireworks.gd")
const GameOver := preload("res://scripts/ui/game_over.gd")
const MockAd := preload("res://scripts/ui/mock_ad.gd")
const Ads := preload("res://scripts/ads.gd")
const ADS_START_DELAY := 6.0  # s after launch: past the intro and the OTA check

var state := State.AIM
var lands: Array[Land] = []
var cur := 0  # land the bubble last settled on
var best := 0  # highest land reached = jumps made
var lives := START_LIVES
var debug_aim := false  # landing line + reticle (tools panel button)
var show_ids := false  # tools panel button: island numbers on the islands
var _slide_land: Land
var keep_lives := false  # tools panel button: falling costs no life
var show_tools := false  # tools panel, toggled by tapping the lives icons

var _cam: Camera2D
var _fx: Fx
var _bubble: Bubble
var _hud: Hud
var _sound: Sound
var _settings: SettingsPanel
var _radar_ping := 0.0
var _board: LeaderboardApi
var _ads: Ads
var _modals: CanvasLayer  # windows (settings, leaderboard, congratulations) open in here
var _fireworks: Fireworks
var _run_ms := 0.0  # play time of this run, paused while a window is open
## Tools: place-the-bubble mode. Drag scrolls the whole level, a tap on an island puts the bubble there.
var placing := false
var _free_y := 0.0  # camera y while placing
var _place_down := false
var _place_from := Vector2.ZERO
var _place_cam := 0.0
var _place_moved := false
var _place_near := -1
var _place_target := 0.0  # where the drag wants the camera; _free_y glides after it
var _place_vel := 0.0  # fling speed after letting go, px/s
var _place_last_t := 0.0
var drops := 0  # life drops collected towards the next life
var radar_time := 0.0  # seconds of pickup radar left
var _drops_hold := 0.0  # keeps a full counter on screen for a moment after the life is added
var _spawn_land := Vector2.ZERO  # island position when the spot was saved (swaying islands move it)
var _spawn_pos := Vector2.ZERO  # world spot the bubble last landed on, to respawn there
var _critters: Critters
var _movers: Array[Land] = []
var _aim_taps := 0
var _aim_tap_time := 0.0
var _water_tap_time := -1.0
var _water_tap_at := Vector2.ZERO
var _water: Control
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
	_place_pickups()
	_restart()
	# The welcome animation over the first moments (skipped with `-- --no-intro`, for previews).
	# On the very first launch the "How to play" cards follow it.
	if not "--no-intro" in OS.get_cmdline_user_args():
		var intro := _show_intro()
		if not HowTo.seen():
			intro.finished.connect(_show_how_to)
	# The game is up: a patched launch counts as good, then look for a newer patch (applies next launch).
	# Looked up by path so the headless level check (no autoloads) still compiles this script.
	var ota := get_node_or_null("/root/Ota")
	if ota:
		ota.confirm_boot()
		get_tree().create_timer(3.0).timeout.connect(ota.check_for_update)
	get_tree().create_timer(ADS_START_DELAY).timeout.connect(_ads.start)


func _build_nodes() -> void:
	var bg := CanvasLayer.new()
	bg.layer = -10
	add_child(bg)
	_water = WaterView.new()
	_water_mat = _water.material_ref
	bg.add_child(_water)
	_water.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_cam = Camera2D.new()
	_cam.position_smoothing_enabled = true
	_cam.position_smoothing_speed = 4.0
	add_child(_cam)
	_cam.make_current()

	# Added before the lands so the fish swim under the islands.
	_critters = Critters.new()
	add_child(_critters)
	_fx = Fx.new()
	_critters.fx = _fx
	_critters.water_at = _water_at
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
	_hud.total = TOTAL_JUMPS + 1  # islands, the start one included
	_hud.max_lives = START_LIVES
	ui.add_child(_hud)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var win_h := float(DisplayServer.window_get_size().y)
	if win_h > 0.0:
		var inset := float(DisplayServer.get_display_safe_area().position.y)
		_hud.top_inset = inset * get_viewport_rect().size.y / win_h

	_sound = Sound.new()
	add_child(_sound)
	_settings = SettingsPanel.new()
	_settings.sound = _sound
	ui.add_child(_settings)
	_settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if win_h > 0.0 and OS.has_feature("mobile"):
		var safe := DisplayServer.get_display_safe_area()
		var bottom := float(DisplayServer.screen_get_size().y - safe.end.y)
		_settings.bottom_inset = maxf(bottom, 0.0) * get_viewport_rect().size.y / win_h
		_hud.bottom_inset = _settings.bottom_inset

	_board = LeaderboardApi.new()
	add_child(_board)
	_ads = Ads.new()
	add_child(_ads)
	_settings.ads = _ads
	var show := CanvasLayer.new()
	show.layer = 15
	add_child(show)
	_fireworks = Fireworks.new()
	_fireworks.play_sound = _sound.play
	_fireworks.finished.connect(_show_congrats)
	show.add_child(_fireworks)
	_modals = CanvasLayer.new()
	_modals.layer = 20
	add_child(_modals)
	_settings.modal_parent = _modals
	_settings.on_skin_change = _on_skin_change
	_settings.on_how_to = _show_how_to


## Same layout on every device: one seeded RNG, always drawing the same numbers per attempt.
func _build_level() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = LEVEL_SEED
	_add_land(_make_land(0, Land.Kind.GRASS, Vector2(270, 0), 100.0, 1.0, 0.0, 1.0))
	for i in range(1, TOTAL_JUMPS + 1):
		var t := float(i) / TOTAL_JUMPS
		var prev := lands[i - 1]
		var l: Land = null
		var extra := 0.0  # extra water, added while the island two back is still in jumping range
		# Reroll an island nobody can reach or stop on; after enough tries fall back to grass.
		for attempt in LEVEL_ATTEMPTS:
			var gap := rng.randf_range(lerpf(110.0, 140.0, t), lerpf(160.0, 220.0, t)) + extra
			var ang := -PI / 2.0 + rng.randf_range(-0.7, 0.7)
			var radius := lerpf(85.0, 46.0, t) * rng.randf_range(0.9, 1.1)
			var thin_roll := rng.randf()
			var kind_roll := rng.randf()
			var rot := rng.randf() * PI
			var belt_sign := 1.0 if rng.randf() < 0.5 else -1.0
			var phase := rng.randf() * TAU
			var vertical := rng.randf() < 0.4
			var p_ice := lerpf(0.10, 0.30, t) if i >= 10 else 0.0
			var p_tread := lerpf(0.08, 0.16, t) if TREADMILLS and i >= 14 else 0.0
			var p_move := lerpf(0.20, 0.32, t) if i >= 5 and prev.kind != Land.Kind.MOVING else 0.0
			var kind := Land.Kind.GRASS
			if kind_roll < p_ice:
				kind = Land.Kind.ICE
			elif kind_roll < p_ice + p_tread:
				kind = Land.Kind.TREADMILL
			elif kind_roll < p_ice + p_tread + p_move:
				kind = Land.Kind.MOVING
			var last := i == TOTAL_JUMPS
			if attempt == LEVEL_ATTEMPTS - 1 or last:
				kind = Land.Kind.GRASS
			var thin := kind == Land.Kind.GRASS and not last and i >= 6 and thin_roll < lerpf(0.05, 0.45, t)
			if kind == Land.Kind.MOVING:
				gap += Land.SWAY_AMP  # it sways towards its neighbours, keep the closest approach as wide
			if kind == Land.Kind.ICE:
				radius = maxf(radius, 72.0)  # ice is hard enough to stop on
			if last:
				radius = 80.0  # the goal island: plain, full size, centred
				ang = atan2(-1.0, 0.0)
				var dx := 270.0 - prev.position.x
				var dist := prev.radius_max + radius + gap
				ang = Vector2(dx, -sqrt(maxf(dist * dist - dx * dx, 1.0))).angle() if absf(dx) < dist * 0.8 else Vector2(signf(dx) * 0.8, -0.6).angle()
			if kind == Land.Kind.TREADMILL:
				rot = 0.0  # treadmills always run straight up / down
			if l:
				l.free()
			l = _make_land(i, kind, prev.position, radius, 0.55 if thin else 1.0, rot, belt_sign)
			var dir := Vector2.from_angle(ang)
			var next := prev.position + dir * (prev.radius_max + l.radius_max + gap)
			if next.x < 80.0 or next.x > 460.0:
				dir.x = -dir.x
				next = prev.position + dir * (prev.radius_max + l.radius_max + gap)
			# Place it so the water between the outlines is `gap` wide.
			for k in 3:
				l.position = next
				next += dir * (gap - _poly_gap(prev, l))
			var lo := 80.0
			var hi := 460.0
			if kind == Land.Kind.MOVING and not vertical:
				lo += Land.SWAY_AMP + 4.0
				hi -= Land.SWAY_AMP + 4.0
			next.x = clampf(next.x, lo, hi)
			if last:
				next.x = 270.0
			l.position = next
			if kind == Land.Kind.MOVING:
				l.setup_motion(phase, vertical)
			if i >= 2:
				var far := lands[i - 2]
				if _poly_gap(far, l) - far.amp - l.amp < MAX_RANGE + SKIP_MARGIN:
					extra += 10.0
					continue
			if _is_solvable(prev, l):
				break
		_add_land(l)
	lands[TOTAL_JUMPS].finish = true
	for l in lands:
		if l.kind == Land.Kind.ICE:
			l.grow(ICE_SCALE)
	for i in EDGE_NUDGE:
		var l: Land = lands[i]
		l.position.x += signf(270.0 - l.position.x) * 0.4 * l.radius_max  # 20% of the island's width


func _make_land(i: int, kind: Land.Kind, at: Vector2, radius: float, aspect: float, rot: float, belt_sign: float) -> Land:
	var l := Land.new()
	l.position = at
	l.setup(i, kind, radius, aspect, rot, LEVEL_SEED * 1000 + i, belt_sign)
	return l


func _add_land(l: Land) -> void:
	add_child(l)
	lands.append(l)
	if l.amp > 0.0:
		_movers.append(l)


## Closest distance between the outlines of two islands (vertex to vertex; outlines are dense).
func _poly_gap(a: Land, b: Land) -> float:
	var d := b.position - a.position
	var best_sq := INF
	for p in a.poly:
		for q in b.poly:
			best_sq = minf(best_sq, p.distance_squared_to(q + d))
	return sqrt(best_sq)


func _land_radius(l: Land) -> float:
	return l.radius_max


## Open water at `p`: no island within `margin` of it (used to place leaping fish).
func _water_at(p: Vector2, margin: float) -> bool:
	for i in range(maxi(cur - 8, 0), mini(cur + 12, lands.size())):
		var l := lands[i]
		if p.distance_to(l.position) < l.radius_max + margin + l.amp:
			return false
	return true


## Whether a jump from `from` can end up settled on `to`. Tries start spots across the
## previous island (centre and 55% towards / away from the target), aiming at a few points
## of the target, and sweeps the power. Needs a window of powers wide enough to hit by hand.
func _is_solvable(from: Land, to: Land) -> bool:
	var fx0 := from.position
	var tx0 := to.position
	var ok := true
	# A swaying island has to work at both ends and in the middle of its sway.
	for fo: float in ([0.0] if from.amp == 0.0 else [-from.amp, 0.0, from.amp]):
		for to_off: float in ([0.0] if to.amp == 0.0 else [-to.amp, 0.0, to.amp]):
			from.position = fx0 + from.sway_dir * fo
			to.position = tx0 + to.sway_dir * to_off
			if not _is_solvable_at(from, to, from.amp > 0.0 or to.amp > 0.0):
				ok = false
	from.position = fx0
	to.position = tx0
	return ok


func _is_solvable_at(from: Land, to: Land, relaxed: bool) -> bool:
	var axis := (to.position - from.position).normalized()
	var r := _land_radius(from)
	var starts := [from.position, from.position + axis * r * 0.55]
	# A treadmill's far end is too far back to count; the other kinds are small enough.
	if from.kind != Land.Kind.TREADMILL:
		starts.append(from.position - axis * r * 0.55)
	for s: Vector2 in starts:
		if not from.contains_world(s):
			continue
		var need := SOLVE_MIN_WINDOW if s == from.position else SOLVE_MIN_WINDOW_OFFSET
		if relaxed:
			need = maxi(need - 3, 3)
		if to.kind == Land.Kind.ICE:
			need = mini(need, 5 if s == from.position else 3)  # sliding makes the workable powers a narrow band
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
func skip_violations() -> Array:
	var bad := []
	for i in range(2, lands.size()):
		var far := lands[i - 2]
		if _poly_gap(far, lands[i]) - far.amp - lands[i].amp < MAX_RANGE:
			bad.append(i)
	return bad


func verify_levels() -> Array:
	var rows := []
	for i in range(1, lands.size()):
		var s := lands[i - 1].position
		rows.append([_best_window(s, lands[i]), i, lands[i].kind])
	rows.sort()
	return rows


func _restart() -> void:
	lives = START_LIVES
	_run_ms = 0.0
	_set_placing(false)
	cur = 0
	best = 0
	_dragging = false
	_drag = Vector2.ZERO
	_bubble.reset()
	_bubble.position = lands[0].position
	_remember_spot()
	_bubble.land_squash()
	state = State.AIM
	drops = 0
	radar_time = 0.0
	_drops_hold = 0.0
	for l in lands:
		if l.pickup:
			l.pickup.reset()
	_activate()
	_cam.global_position = _cam_target()
	_cam.reset_smoothing()


## Only islands near the bubble animate their shore waves and belts.
## Saves the bubble's current world position as the respawn spot.
func _remember_spot() -> void:
	_spawn_pos = _bubble.position
	_spawn_land = lands[cur].position


func _activate() -> void:
	_activate_around(cur)


func _activate_around(center: int) -> void:
	for l in lands:
		var near := absi(l.index - center) <= 6
		l.set_process(near)
		if l.pickup:
			l.pickup.set_process(near)


func _cam_target() -> Vector2:
	if placing:
		return Vector2(270.0, _free_y)
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


func _modal_open() -> bool:
	return _modals.get_child_count() > 0


func _input(event: InputEvent) -> void:
	if _modal_open() or _settings.handle(event):
		if _dragging:
			_dragging = false  # a jump drag interrupted by a window is cancelled
			_drag = Vector2.ZERO
			_bubble.pull = Vector2.ZERO
		_place_down = false
		return
	if state == State.WON:
		return  # fireworks, then the congratulations window
	if placing and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_place_vel = 0.0
		_place_target = _clamp_free_y(_place_target + (-90.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 90.0))
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _hud.board_rect().has_point(event.position):
				_open_board()
			elif show_tools and _hud.place_rect().has_point(event.position):
				_set_placing(not placing)
			elif show_tools and _hud.radar_rect().has_point(event.position):
				debug_aim = not debug_aim
			elif show_tools and _hud.keep_rect().has_point(event.position):
				keep_lives = not keep_lives
			elif show_tools and _hud.ids_rect().has_point(event.position):
				_set_ids(not show_ids)
			elif show_tools and _hud.intro_rect().has_point(event.position):
				_show_intro()
			elif show_tools and _hud.fps_rect().has_point(event.position):
				_cycle_fps()
			elif show_tools and _hud.cap_rect().has_point(event.position):
				_set_cap60(not _hud.cap60)
			elif _hud.lives_rect().has_point(event.position):
				_tap_lives()
			elif placing:
				_place_down = true
				_place_moved = false
				_place_from = event.position
				_place_cam = _place_target
				_place_vel = 0.0
				_place_last_t = Time.get_ticks_msec() / 1000.0
			elif state == State.AIM and get_global_mouse_position().distance_to(_bubble.position) <= GRAB_RADIUS:
				_dragging = true
				_drag = Vector2.ZERO
			else:
				_tap_water(get_global_mouse_position())
		elif _place_down:
			_place_down = false
			if not _place_moved:
				_place_at(event.position)
			elif Time.get_ticks_msec() / 1000.0 - _place_last_t > 0.08:
				_place_vel = 0.0  # held still before letting go: no fling
		elif _dragging:
			_update_drag()
			_dragging = false
			var v := -_drag
			_drag = Vector2.ZERO
			_bubble.pull = Vector2.ZERO
			if state == State.AIM and v.length() >= MIN_DRAG:
				_jump(v)
	elif event is InputEventMouseMotion and _place_down:
		var dy: float = event.position.y - _place_from.y
		if absf(dy) > 12.0:
			_place_moved = true
		if _place_moved:
			var target := _clamp_free_y(_place_cam - dy)
			var now := Time.get_ticks_msec() / 1000.0
			var dt := maxf(now - _place_last_t, 0.001)
			# Smoothed finger speed, used for the fling when the finger lifts.
			_place_vel = lerpf(_place_vel, (target - _place_target) / dt, 0.4)
			_place_last_t = now
			_place_target = target
	elif event is InputEventMouseMotion and _dragging:
		_update_drag()


## Tools: place-the-bubble mode on / off. On, the camera stops following the bubble.
func _set_placing(on: bool) -> void:
	placing = on
	_place_down = false
	_cam.position_smoothing_enabled = not on  # scrolling follows the finger exactly
	_place_near = -1
	_place_vel = 0.0
	if on:
		_free_y = _cam.get_screen_center_position().y
		_place_target = _free_y
		_dragging = false
		_drag = Vector2.ZERO
	else:
		_activate()


func _clamp_free_y(y: float) -> float:
	var off := get_viewport_rect().size.y * 0.2
	return clampf(y, lands[TOTAL_JUMPS].position.y - off, lands[0].position.y - off)


## Puts the bubble where the island was tapped and carries on from there (that island counts
## as reached). The 100th island starts the finish.
func _place_at(screen: Vector2) -> void:
	var world := get_canvas_transform().affine_inverse() * screen
	for l in lands:
		if l.contains_world(world):
			_set_placing(false)
			_fx.tail_on = false
			_bubble.reset()
			_bubble.position = world
			best = l.index
			state = State.AIM
			_settle(l)
			_cam.reset_smoothing()
			return


## Tools "fps" button: off -> frame rate readout -> readout with the sea hidden (to see what the
## sea costs on this device) -> off.
func _cycle_fps() -> void:
	if not _hud.show_fps:
		_hud.show_fps = true
	elif not _hud.no_water:
		_hud.no_water = true
	else:
		_hud.show_fps = false
		_hud.no_water = false
	_water.visible = not _hud.no_water
	var vp: SubViewport = _water.get_child(0)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED if _hud.no_water else SubViewport.UPDATE_ALWAYS
	_hud.water_viewport = vp.get_viewport_rid()


## Tools "60" button: caps the frame rate at 60 (a steady 60 can look smoother than an uneven
## 45-70 on a 120 Hz screen).
func _set_cap60(on: bool) -> void:
	_hud.cap60 = on
	Engine.max_fps = 60 if on else 0
	_hud.queue_redraw()


## The welcome animation; also replayed from the tools panel for testing.
func _show_intro() -> Control:
	var intro := Intro.new()
	intro.play_sound = _sound.play
	_modals.add_child(intro)
	return intro


## The "How to play" cards (first launch, and from Settings).
func _show_how_to() -> void:
	_modals.add_child(HowTo.new())


## The last island: a fanfare and fireworks, then the congratulations window.
func _win() -> void:
	state = State.WON
	_sound.play("win")
	_fireworks.start()


func _show_congrats() -> void:
	var c := Congrats.new(_board, int(_run_ms))
	c.saved.connect(func(id: String): _open_board(id, true))
	c.skipped.connect(_restart)
	_modals.add_child(c)


## The leaderboard window; `highlight` marks a just-saved entry. After a finish, closing it
## starts a new run.
func _open_board(highlight := "", restart_after := false) -> void:
	var v := LeaderboardView.new(_board, highlight)
	if restart_after:
		v.closed.connect(_restart)
	_modals.add_child(v)


func _set_ids(on: bool) -> void:
	show_ids = on
	for l in lands:
		l.set_show_id(on)


func _update_drag() -> void:
	_drag = (get_global_mouse_position() - _bubble.position).limit_length(MAX_DRAG)


## A hidden treat: a double tap on open water makes a fish leap out right there.
func _tap_water(world: Vector2) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _water_tap_time <= DOUBLE_TAP and world.distance_to(_water_tap_at) < 40.0:
		_water_tap_time = -1.0
		if _water_at(world, 12.0):
			_critters.leap_at(world)
		return
	_water_tap_time = now
	_water_tap_at = world


## Five quick taps on the lives icons show the tools buttons; three hide them and reset the tools.
func _tap_lives() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_aim_taps = _aim_taps + 1 if now - _aim_tap_time < 2.0 else 1
	_aim_tap_time = now
	if show_tools and _aim_taps >= HIDE_TAPS:
		_aim_taps = 0
		show_tools = false
		_set_placing(false)
		debug_aim = false
		keep_lives = false
		_hud.show_fps = true
		_hud.no_water = true
		_cycle_fps()  # back to off, with the sea shown
		_set_cap60(false)
		_set_ids(false)
	elif not show_tools and _aim_taps >= AIM_TAPS:
		_aim_taps = 0
		show_tools = true


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
	if state != State.OVER and state != State.WON and not _modal_open():
		_run_ms += delta * 1000.0
	if placing:
		# Glide after the finger (and coast after a fling) instead of jumping per touch event.
		if not _place_down:
			_place_target = _clamp_free_y(_place_target + _place_vel * delta)
			_place_vel *= exp(-4.0 * delta)
		_free_y = lerpf(_free_y, _place_target, 1.0 - exp(-22.0 * delta))
		# Islands near the view come alive while scrolling.
		var near := 0
		for l in lands:
			if absf(l.position.y - _free_y) < absf(lands[near].position.y - _free_y):
				near = l.index
		if near != _place_near:
			_place_near = near
			_activate_around(near)
	for l in _movers:
		l.set_motion_time(_time)
	match state:
		State.FLY:
			_fly_t += delta
			var u := clampf(_fly_t / _fly_dur, 0.0, 1.0)
			_bubble.position = _fly_from.lerp(_fly_to, u)
			_bubble.height = sin(PI * u) * (0.35 + 0.65 * _fly_power)
			_fx.tail_on = true
			_fx.tail_pos = _bubble.position + Vector2(0, -_bubble.height * 46.0)
			_fx.tail_dir = _fly_dir
			_fx.tail_power = _fly_power
			if u >= 1.0:
				_on_landed()
		State.AIM:
			_ride(delta)
		State.SLIDE:
			var under := _slide_land
			_bubble.position += _slide_vel * delta
			if under:
				_bubble.position += under.carry(delta)
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
	if _dragging:
		_update_drag()
	var pulling := _dragging and _drag.length() >= MIN_DRAG
	_fx.arcs_on = pulling
	if pulling:
		_fx.arcs_from = _bubble.position
		_fx.arcs_angle = (-_drag).angle()
		_fx.arcs_power = _drag.length() / MAX_DRAG
	if radar_time > 0.0:
		radar_time = maxf(radar_time - delta, 0.0)
		_radar_ping -= delta
		if _radar_ping <= 0.0 and radar_time > 0.5:
			_radar_ping = RADAR_PING
			_sound.play("radar_ping", -7.0)
	if _drops_hold > 0.0:
		_drops_hold -= delta
		if _drops_hold <= 0.0:
			drops = 0
	_fx.aiming = (debug_aim or radar_time > 0.0) and pulling
	_fx.aim_alpha = 1.0 if debug_aim else Pickup.radar_alpha(radar_time)
	if _fx.aiming:
		_fx.aim_from = _bubble.position
		_fx.aim_to = _bubble.position - _drag.normalized() * (_drag.length() / MAX_DRAG) * MAX_RANGE

	_cam.position = _cam_target()
	if placing:
		_cam.force_update_scroll()  # water and islands move together in the same frame
	_critters.focus = _bubble.position
	var view := get_viewport_rect().size
	var top_left := _cam.get_screen_center_position() - view / 2.0
	_water_mat.set_shader_parameter("origin", top_left)
	_water_mat.set_shader_parameter("area", view)
	_water_mat.set_shader_parameter("t", _time)

	var title := ""
	var sub := ""
	_hud.set_tools(show_tools, debug_aim, keep_lives, show_ids, placing)
	_hud.set_pickups(drops, radar_time, 1.0 - _drops_hold / 0.8 if _drops_hold > 0.0 else 0.0)
	# The life a full meter gives shows up in the lives once the meter empties (it already counts).
	_hud.set_info(best, lives - (1 if _drops_hold > 0.0 else 0), title, sub)


## Treadmills and swaying islands carry the bubble; it falls once carried off the edge.
func _ride(delta: float) -> void:
	# The island it stands on, not whatever is under the bubble now: a swaying island has already
	# moved this frame, and a bubble on its edge would otherwise be left behind in the water.
	var l := lands[cur]
	var move := l.carry(delta)
	if move == Vector2.ZERO:
		return
	_bubble.position += move
	if not l.contains_world(_bubble.position):
		_dragging = false
		_drag = Vector2.ZERO
		_start_fall()


func _on_landed() -> void:
	_fx.tail_on = false
	_bubble.height = 0.0
	var l := _land_at(_bubble.position)
	if l == null:
		_start_fall()
	elif l.kind == Land.Kind.ICE and _fly_power > 0.12:
		_sound.play("land_ice", 0.0, randf_range(0.95, 1.05))
		_slide_vel = _fly_dir * _fly_power * SLIDE_SPEED
		_slide_land = l
		_bubble.land_squash()
		state = State.SLIDE
	else:
		_sound.play("land_ice" if l.kind == Land.Kind.ICE else "land", 0.0, randf_range(0.93, 1.07))
		_settle(l)


func _settle(l: Land) -> void:
	cur = l.index
	_remember_spot()
	_activate()
	_resolve_pickup(l)
	_bubble.land_squash()
	_fx.ring(_bubble.position, 44.0, Color(1, 1, 1, 0.7), 0.5)
	if cur > best:
		best = cur
	if best >= TOTAL_JUMPS:
		_win()
	else:
		state = State.AIM


## Landing on a pickup collects it; settling anywhere else on its island makes it vanish.
func _resolve_pickup(l: Land) -> void:
	var p := l.pickup
	if p == null or not p.is_active():
		return
	if p.global_position.distance_to(_bubble.position) > COLLECT_RADIUS:
		p.vanish()
	elif p.kind == Pickup.Kind.RADAR:
		radar_time = RADAR_TIME
		_radar_ping = RADAR_PING + 0.6
		_sound.play("radar_on")
		p.collect("Spyglass %ds" % int(RADAR_TIME))
	else:
		if _drops_hold > 0.0:
			drops = 0
			_drops_hold = 0.0
		drops += 1
		if drops >= DROPS_PER_LIFE:
			lives += 1
			_sound.play("life")
			_drops_hold = 0.8
			p.collect("+1 life!")
		else:
			p.collect("%d/%d" % [drops, DROPS_PER_LIFE])
			_sound.play("drop", 0.0, 1.0 + 0.12 * (drops - 1))


## Scatters the pickups over the level: LIFE_PICKUPS drops and RADAR_PICKUPS lenses, one island
## each, evenly spread, never on the start, the goal or ice (you slide off it). Own seeded RNG so
## the level above is untouched.
func _place_pickups() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = LEVEL_SEED + 7
	var used := {}
	var first := 2
	var last := TOTAL_JUMPS - 1
	for spec: Array in [[Pickup.Kind.LIFE, LIFE_PICKUPS], [Pickup.Kind.RADAR, RADAR_PICKUPS]]:
		var n: int = spec[1]
		var span := float(last - first + 1) / n
		for k in n:
			var lo := first + int(k * span)
			var hi := maxi(first + int((k + 1) * span) - 1, lo)
			var idx := -1
			for t in 12:
				var c := rng.randi_range(lo, hi)
				if not used.has(c) and lands[c].kind != Land.Kind.ICE:
					idx = c
					break
			if idx < 0:  # the segment is full: take any free island
				for c in range(first, last + 1):
					if not used.has(c) and lands[c].kind != Land.Kind.ICE:
						idx = c
						break
			if idx < 0:
				continue
			used[idx] = true
			_attach_pickup(lands[idx], spec[0], rng)


func _attach_pickup(l: Land, kind: Pickup.Kind, rng: RandomNumberGenerator) -> void:
	var p := Pickup.new()
	p.kind = kind
	var core := Transform2D(0.0, Vector2(0.6, 0.6), 0.0, Vector2.ZERO) * l.poly
	for t in 40:
		var c := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * l.radius_max * 0.6
		if Geometry2D.is_point_in_polygon(c, core):
			p.position = c
			break
	l.add_child(p)
	l.pickup = p


func _start_fall() -> void:
	if not keep_lives:
		lives -= 1
	_fall_t = 0.0
	_fx.splash(_bubble.position, 1.0, 0.45)
	_sound.play("splash", 0.0, randf_range(0.94, 1.06))
	state = State.FALL


func _after_fall() -> void:
	if lives <= 0:
		state = State.OVER
		_show_game_over()
		return
	_respawn()


## A new bubble colour: redraw the drops on islands that are not animating right now.
func _on_skin_change() -> void:
	_hud.queue_redraw()
	for l in lands:
		if l.pickup:
			l.pickup.queue_redraw()


## Out of lives: watch an ad for one more life, or start over. From island NO_AD_FROM on there
## is no ad: the last stretch is the player's own.
func _show_game_over() -> void:
	var g := GameOver.new(best + 1, TOTAL_JUMPS + 1, best + 1 < NO_AD_FROM)
	g.watch_ad.connect(_show_ad)
	g.retry.connect(_restart)
	_modals.add_child(g)


## A rewarded ad (AdMob on phones, a 2 s stand-in on desktop); when it has played, one more life
## and the run carries on from the island it stopped on. With no ad to show (no network, no
## fill) the life is given anyway: a missing ad never blocks the game. Closed early: back to
## the game over window. The game is silent while the ad plays.
func _show_ad() -> void:
	AudioServer.set_bus_mute(0, true)
	if not Ads.supported():
		var mock := MockAd.new()
		mock.rewarded.connect(_ad_watched)
		_modals.add_child(mock)
		return
	var result: Ads.Result = await _ads.show_rewarded()
	if result == Ads.Result.SKIPPED:
		AudioServer.set_bus_mute(0, false)
		_show_game_over()
	else:
		_ad_watched()


func _ad_watched() -> void:
	AudioServer.set_bus_mute(0, false)
	lives += 1
	_respawn()


## Back on the spot it last landed on.
func _respawn() -> void:
	_bubble.reset()
	_bubble.position = _spawn_pos
	var home := lands[cur]
	# Too close to the end of a treadmill: it would fall within 2 s, so start from mid-belt (same x).
	if home.kind == Land.Kind.TREADMILL and not home.contains_world(_spawn_pos + home.belt_dir() * Land.BELT_SPEED * 2.0):
		_bubble.position.y = home.position.y
	if lands[cur].amp > 0.0:  # a swaying island took its spot along
		_bubble.position += lands[cur].position - _spawn_land
	_bubble.land_squash()
	state = State.AIM
