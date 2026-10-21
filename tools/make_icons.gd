extends SceneTree
## Renders the app icons into res://ui/icons/: a flat, simple mark, a big mint "99" (the logo's
## Lilita One) on a sea-blue gradient, with the bubble hopping off it along a dotted arc.
##   ios_1024.png                 App Store / iOS (opaque, square; iOS rounds the corners)
##   android_main_192.png         legacy Android launcher icon
##   android_background_432.png   adaptive icon: the gradient
##   android_foreground_432.png   adaptive icon: the "99", arc and bubble (transparent)
## The adaptive layers show only their middle 2/3 inside the launcher's mask, so they are drawn
## with the iOS framing in that middle and the gradient carried on around it.
##   Godot --path . -s res://tools/make_icons.gd

const Logo := preload("res://scripts/ui/logo.gd")
const OUT := "res://ui/icons/"
const S := 1024.0
const NUMBER_SIZE := 2.3  # logo scale of the "99"
const NUMBER_AT := Vector2(500, 640)
const BUBBLE_AT := Vector2(800, 245)
const BUBBLE_R := 82.0
## The arc's dots, from the first "9" up to the bubble (each bigger than the last).
const DOTS := [[Vector2(300, 300), 16.0], [Vector2(405, 195), 19.0], [Vector2(540, 150), 22.0], [Vector2(665, 165), 25.0]]


func _initialize() -> void:
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var full: Image = await _render(1024, 0.0, true, true)
	full.save_png(OUT + "ios_1024.png")
	var small := full.duplicate() as Image
	small.resize(192, 192, Image.INTERPOLATE_LANCZOS)
	small.save_png(OUT + "android_main_192.png")
	# Adaptive layers: 1.5x the iOS area (108 dp layer, 72 dp visible).
	var bg: Image = await _render(432, S * 0.25, true, false)
	bg.save_png(OUT + "android_background_432.png")
	var fg: Image = await _render(432, S * 0.25, false, true)
	fg.save_png(OUT + "android_foreground_432.png")
	quit()


## `margin`: extra layout space on each side of the 1024 iOS framing.
func _render(px: int, margin: float, back: bool, front: bool) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(px, px)
	vp.transparent_bg = not back
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var span := S + margin * 2.0
	var k := px / span
	var canvas := Node2D.new()
	canvas.transform = Transform2D(0.0, Vector2(k, k), 0.0, Vector2(margin, margin) * k)
	canvas.draw.connect(func():
		if back:
			_background(canvas, margin, span)
		if front:
			_mark(canvas))
	vp.add_child(canvas)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := vp.get_texture().get_image()
	vp.queue_free()
	return image


func _background(c: CanvasItem, margin: float, span: float) -> void:
	Logo.backdrop(c, Rect2(Vector2(-margin, -margin), Vector2(span, span)))


func _mark(c: CanvasItem) -> void:
	for d: Array in DOTS:
		c.draw_circle(d[0], d[1], Color.WHITE)
	Logo.number(c, NUMBER_AT, NUMBER_SIZE)
	Logo.bubble(c, BUBBLE_AT, BUBBLE_R)
