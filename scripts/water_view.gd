extends SubViewportContainer
## The sea (shaders/water.gdshader), drawn at the game's own resolution (540 wide; the layout
## size, not the screen's) and scaled up to fill the screen with linear filtering. The water is
## soft anyway, so it looks the same, but on a 1080 x 2400 phone it shades about 4x fewer pixels
## than drawing it straight to the screen, which made jumps stutter on Android.
## Set the shader parameters on `material_ref`. No class_name, so the OTA shape doesn't change.

var material_ref: ShaderMaterial


func _init() -> void:
	stretch = true  # the SubViewport follows this container's (layout) size
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mouse_filter = MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	rect.mouse_filter = MOUSE_FILTER_IGNORE
	material_ref = ShaderMaterial.new()
	material_ref.shader = load("res://shaders/water.gdshader")
	rect.material = material_ref
	vp.add_child(rect)
