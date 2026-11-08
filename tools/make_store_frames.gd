extends SceneTree
## Turns the plain store screenshots (tools/make_store_shots.gd) into captioned ones: the shot,
## scaled down in a rounded phone frame, on the icon's sea gradient with a short caption on top.
##   Godot --path . -s res://tools/make_store_frames.gd            -> res://ui/store/captioned/
##   Godot --path . -s res://tools/make_store_frames.gd -- --ios   -> res://ui/store/ios/captioned/
## Run make_store_shots.gd first; each output has the same size as its input.

const Logo := preload("res://scripts/ui/logo.gd")
const CAPTIONS := {
	"screen_1_welcome": "One bubble.\n100 islands.",
	"screen_2_aim": "Drag back, aim\nand let go!",
	"screen_3_islands": "Islands that drift,\nlives to collect",
	"screen_4_fireworks": "Make it across\nall 100 islands",
	"screen_5_finish": "Beat the best time\non the leaderboard",
}

var _dir := "res://ui/store/"


func _initialize() -> void:
	_run()


func _run() -> void:
	if "--ios" in OS.get_cmdline_user_args():
		_dir += "ios/"
	DirAccess.make_dir_recursive_absolute(_dir + "captioned")
	for name: String in CAPTIONS:
		var shot := Image.load_from_file(ProjectSettings.globalize_path(_dir + name + ".png"))
		if shot == null:
			push_error("missing " + _dir + name + ".png")
			continue
		await _frame(shot, CAPTIONS[name], _dir + "captioned/" + name + ".png")
	quit()


func _frame(shot: Image, caption: String, out: String) -> void:
	var size := shot.get_size()
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(vp)
	var tex := ImageTexture.create_from_image(shot)
	var k := size.x / 1080.0  # layout is for 1080 wide
	var canvas := Node2D.new()
	canvas.draw.connect(func():
		Logo.backdrop(canvas, Rect2(Vector2.ZERO, size))
		# Caption: Lilita One, white with the logo's navy outline, centred in the top 20 %.
		var font := Logo.NUMBER_FONT
		var fs := int(92 * k)
		var lines := caption.split("\n")
		var line_h := fs * 1.12
		var top := size.y * 0.105 - line_h * lines.size() * 0.5
		for i in lines.size():
			var w := font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var at := Vector2((size.x - w) * 0.5, top + line_h * (i + 0.8))
			canvas.draw_string_outline(font, at + Vector2(0, 6 * k), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(14 * k), Logo.SHADOW)
			canvas.draw_string_outline(font, at, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(14 * k), Logo.OUTLINE)
			canvas.draw_string(font, at, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE if i == 0 else Logo.MINT)
		# The shot in a phone frame below.
		var h := size.y * 0.75
		var w := h * size.x / size.y
		var r := Rect2((size.x - w) * 0.5, size.y * 0.215, w, h)
		var bezel := StyleBoxFlat.new()
		bezel.bg_color = Logo.OUTLINE
		bezel.set_corner_radius_all(int(54 * k))
		bezel.shadow_color = Color(0, 0.04, 0.1, 0.4)
		bezel.shadow_size = int(30 * k)
		bezel.shadow_offset = Vector2(0, 14 * k)
		canvas.draw_style_box(bezel, r.grow(16 * k))
		canvas.draw_texture_rect(tex, r, false))
	vp.add_child(canvas)
	await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(out)
	vp.queue_free()
