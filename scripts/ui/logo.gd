extends RefCounted
## The "99 jumps" logo: a chunky mint "99" (Lilita One) with "jumps" in white brush script
## (Pacifico) tucked under it at a slight tilt, both with a navy outline. `number` and `word`
## draw the two parts on their own (the intro animates them separately); `draw` paints it whole
## (share picture). No class_name, so the OTA shape doesn't change.

const NUMBER_FONT := preload("res://fonts/LilitaOne-Regular.ttf")
const WORD_FONT := preload("res://fonts/Pacifico-Regular.ttf")
const MINT := Color(0.55, 0.93, 0.72)
const OUTLINE := Color(0.02, 0.12, 0.24)
const SHADOW := Color(0, 0.05, 0.1, 0.35)
const NUMBER_SIZE := 210
const WORD_SIZE := 78
const WORD_TILT := -0.1  # radians
## Where each part sits relative to the logo's centre, at scale 1.
const NUMBER_AT := Vector2(0, 2)
const WORD_AT := Vector2(22, 108)
## The icon's look, shared with the welcome screen: sea gradient and the flat bubble.
const SEA_TOP := Color(0.13, 0.62, 0.82)
const SEA_BOTTOM := Color(0.03, 0.23, 0.45)
const BUBBLE := Color(0.36, 0.78, 1.0)
const BUBBLE_RIM := Color(0.75, 0.93, 1.0)


static func draw(canvas: CanvasItem, center: Vector2, scale := 1.0) -> void:
	number(canvas, center, scale)
	word(canvas, center, scale)


## The vertical sea gradient over `rect`, with a soft glow up and to the left.
static func backdrop(canvas: CanvasItem, rect: Rect2) -> void:
	var a := rect.position
	var b := rect.end
	canvas.draw_polygon(PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)]),
		PackedColorArray([SEA_TOP, SEA_TOP, SEA_BOTTOM, SEA_BOTTOM]))
	var glow := a + rect.size * Vector2(0.37, 0.16)
	var reach := maxf(rect.size.x, rect.size.y) * 0.6
	for i in 12:
		canvas.draw_circle(glow, lerpf(reach, reach * 0.2, i / 11.0), Color(1, 1, 1, 0.018))


## The flat bubble: soft shadow, navy outline, body, lighter rim, two highlights. Its outline
## is gently uneven like the game's liquid bubble (the settings previews' calm wobble), moving
## with `t` (seconds; keep it fixed for a still picture). `squash` stretches it about its centre.
static func bubble(canvas: CanvasItem, at: Vector2, r: float, squash := Vector2.ONE, alpha := 1.0, t := 0.0) -> void:
	var shape := _blob(r, t)
	canvas.draw_set_transform(at, 0.0, squash)
	canvas.draw_colored_polygon(_scaled(shape, 1.0, Vector2(0, r * 0.15)), Color(OUTLINE, 0.35 * alpha))
	canvas.draw_colored_polygon(_scaled(shape, 1.11), Color(OUTLINE, alpha))
	canvas.draw_colored_polygon(shape, Color(BUBBLE, alpha))
	var rim := _scaled(shape, 0.94)
	rim.append(rim[0])
	canvas.draw_polyline(rim, Color(BUBBLE_RIM, alpha), r * 0.073, true)
	canvas.draw_circle(Vector2(-0.32, -0.32) * r, r * 0.24, Color(1, 1, 1, 0.95 * alpha))
	canvas.draw_circle(Vector2(0.27, 0.37) * r, r * 0.1, Color(1, 1, 1, 0.6 * alpha))
	canvas.draw_set_transform(Vector2.ZERO)


## A softly uneven round outline (as Pickup.draw_bubble with a calm wobble), around the origin.
static func _blob(r: float, t: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for n in 48:
		var a := TAU * n / 48.0
		var k := 0.55 * (0.09 * sin(a * 2.0 + t * 1.4 + 0.6) + 0.06 * sin(a * 3.0 - t * 1.1 + 2.1) + 0.035 * sin(a * 5.0 + t * 1.9))
		pts.append(Vector2(cos(a), sin(a)) * r * (1.0 + k))
	return pts


static func _scaled(pts: PackedVector2Array, k: float, offset := Vector2.ZERO) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in pts:
		out.append(q * k + offset)
	return out


## The "99", centred on its own middle; `squash` stretches it about that point.
static func number(canvas: CanvasItem, center: Vector2, scale := 1.0, alpha := 1.0, squash := Vector2.ONE, angle := 0.0) -> void:
	var size := int(NUMBER_SIZE * scale)
	var w := NUMBER_FONT.get_string_size("99", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var mid := center + NUMBER_AT * scale
	canvas.draw_set_transform(mid, angle, squash)
	# Baseline so the digits' middle (about 0.36 of the size above it) lands on `mid`.
	var at := Vector2(-w / 2.0, size * 0.36)
	_letters(canvas, NUMBER_FONT, "99", at, size, 18.0 * scale, MINT, alpha, 1.0)
	canvas.draw_set_transform(Vector2.ZERO)


## "jumps" in script; `reveal` 0..1 brings the letters in left to right (each fades in and
## settles from a little below).
static func word(canvas: CanvasItem, center: Vector2, scale := 1.0, reveal := 1.0, alpha := 1.0) -> void:
	var size := int(WORD_SIZE * scale)
	var w := WORD_FONT.get_string_size("jumps", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	canvas.draw_set_transform(center + WORD_AT * scale, WORD_TILT)
	_letters(canvas, WORD_FONT, "jumps", Vector2(-w / 2.0, size * 0.3), size, 12.0 * scale, Color.WHITE, alpha, reveal)
	canvas.draw_set_transform(Vector2.ZERO)


## Draws `text` a letter at a time (positions from the shaped prefix, so kerning holds): soft
## shadow, navy outline, fill. Letter i shows once `reveal` passes i / count.
static func _letters(canvas: CanvasItem, font: Font, text: String, at: Vector2, size: int, outline: float, color: Color, alpha: float, reveal: float) -> void:
	var n := text.length()
	for pass_i in 3:
		for i in n:
			var u := clampf(reveal * (n + 1.5) - i, 0.0, 1.0)  # this letter's own 0..1
			if u <= 0.0:
				continue
			var a := alpha * smoothstep(0.0, 1.0, u)
			var x := font.get_string_size(text.substr(0, i), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var p := at + Vector2(x, (1.0 - u) * size * 0.25)
			var ch := text[i]
			match pass_i:
				0:
					canvas.draw_string_outline(font, p + Vector2(0, outline * 0.5), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, int(outline * 2.0), Color(SHADOW, SHADOW.a * a))
				1:
					canvas.draw_string_outline(font, p, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, int(outline * 1.3), Color(OUTLINE, a))
				2:
					canvas.draw_string(font, p, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(color, a))
