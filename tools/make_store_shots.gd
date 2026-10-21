extends SceneTree
## Renders phone screenshots for the store listing into res://ui/store/ (1080 x 1920): the game
## runs in a SubViewport laid out at its own 540 x 960 and drawn at 2x, staged scene by scene.
##   Godot --path . -s res://tools/make_store_shots.gd -- --no-intro
## (--no-intro so the welcome screen is added here, for its own shot, not over the others).

const OUT := "res://ui/store/"
const Skins := preload("res://scripts/skins.gd")

var _vp: SubViewport
var _m: Node2D


func _initialize() -> void:
	Engine.max_fps = 60
	_run()


func _run() -> void:
	Skins.pick(0)
	_vp = SubViewport.new()
	_vp.size = Vector2i(1080, 1920)
	_vp.size_2d_override = Vector2i(540, 960)
	_vp.size_2d_override_stretch = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	_m = load("res://scenes/main.tscn").instantiate()
	_vp.add_child(_m)
	await _frames(20)

	# 1. Aiming: a real drag back from the bubble; the power arcs and the radar landing line show.
	_m.radar_time = 6.0
	var at: Vector2 = _screen(_m._bubble.position)
	_pointer(at, true)
	for k in 12:
		_pointer(at.lerp(at + Vector2(-30, 165), (k + 1) / 12.0))
		await _frames(2)
	await _seconds(0.4)
	await _shot("screen_2_aim")
	_pointer(at, false, true)  # let go back on the bubble: too short to jump
	_m.radar_time = 0.0
	await _seconds(0.5)

	# 3. Further along: sandbanks and ice, pickups on the way, two drops in the life meter.
	_stand_on(23)
	_m.drops = 2
	await _seconds(2.5)
	await _shot("screen_3_islands")

	# The welcome screen over it all, the bubble hopping across the "99".
	_m._show_intro()
	await _seconds(2.35)
	await _shot("screen_1_welcome")
	await _seconds(1.8)

	# 4. The finish: fireworks, then the congratulations window with the run's time.
	_stand_on(99)
	_m._run_ms = 754300.0
	await _seconds(0.5)
	_m._win()
	await _seconds(1.6)
	await _shot("screen_4_fireworks")
	await _seconds(3.4)
	await _shot("screen_5_finish")
	quit()


## World position to SubViewport pixels (the camera only scrolls vertically).
func _screen(world: Vector2) -> Vector2:
	var top_left: Vector2 = _m._cam.get_screen_center_position() - Vector2(270, 480)
	return (world - top_left) * 2.0


## Feeds the game a mouse event at `at` (SubViewport pixels): a press / release, or a move.
func _pointer(at: Vector2, press := false, release := false) -> void:
	var ev: InputEvent
	if press or release:
		ev = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = press
	else:
		ev = InputEventMouseMotion.new()
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev.position = at
	ev.global_position = at
	_vp.push_input(ev)


## Puts the bubble on island `i` as if it had just landed there.
func _stand_on(i: int) -> void:
	_m.cur = i
	_m.best = i
	_m._activate()
	_m._bubble.position = _m.lands[i].position
	_m._cam.reset_smoothing()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(OUT + name + ".png")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seconds(s: float) -> void:
	await create_timer(s).timeout
