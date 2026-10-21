extends SceneTree
## Renders the Google Play listing art into res://ui/store/:
##   feature_1024x500.png   the feature graphic: the game's sea, two islands with the bubble
##                          hopping between them along a dotted half circle, and the logo
##   icon_512.png           the app icon at Play's listing size (from ui/icons/ios_1024.png)
##   Godot --path . -s res://tools/make_store_art.gd

const Logo := preload("res://scripts/ui/logo.gd")
const OUT := "res://ui/store/"
const SIZE := Vector2i(1024, 500)


func _initialize() -> void:
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var icon := Image.load_from_file(ProjectSettings.globalize_path("res://ui/icons/ios_1024.png"))
	icon.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	icon.save_png(OUT + "icon_512.png")
	var feature: Image = await _feature()
	feature.convert(Image.FORMAT_RGB8)  # Play wants no alpha in the feature graphic
	feature.save_png(OUT + "feature_1024x500.png")
	quit()


func _feature() -> Image:
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var water := ColorRect.new()
	water.size = Vector2(SIZE)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	mat.set_shader_parameter("area", Vector2(SIZE) * 0.9)
	mat.set_shader_parameter("origin", Vector2(-300, 700))
	mat.set_shader_parameter("t", 21.0)
	water.material = mat
	vp.add_child(water)

	var from := Vector2(590, 370)
	var to := Vector2(905, 345)
	for i in 2:
		var l := Land.new()
		l.setup(i, Land.Kind.GRASS, 74.0 if i == 0 else 66.0, 0.85, 0.5 + i, 515 + i)
		l.position = [from, to][i] + Vector2(0, 18)
		vp.add_child(l)
	# The hop: a dotted half circle from one island to the other, the bubble near its top.
	var art := Node2D.new()
	art.draw.connect(func():
		var mid := (from + to) / 2.0
		var r := from.distance_to(to) / 2.0
		for n in 9:
			var u := 0.06 + n * 0.075
			var a := PI * (1.0 - u)
			art.draw_circle(mid + Vector2(cos(a), -sin(a)) * r, 3.5 + n * 0.6, Color.WHITE)
		var a2 := PI * (1.0 - 0.72)
		Logo.bubble(art, mid + Vector2(cos(a2), -sin(a2)) * r, 34.0, Vector2.ONE, 1.0, 2.0)
		Logo.draw(art, Vector2(275, 185), 1.15))
	vp.add_child(art)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := vp.get_texture().get_image()
	vp.queue_free()
	return image
