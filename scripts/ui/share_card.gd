extends Control
## The picture shared from the congratulations window: a 9:16 story (1080 × 1920, for
## Instagram / TikTok / WhatsApp stories, fine in any chat) of the game's own sea with the
## bubble on the finish island, the run's time (and the player's name, when typed) on a glass
## card, and both stores' badges below (`make_image`). `text` is the message sent with it.
## No class_name, so the OTA shape doesn't change.

const Modal := preload("res://scripts/ui/modal.gd")
const Logo := preload("res://scripts/ui/logo.gd")
const LeaderboardApi := preload("res://scripts/leaderboard.gd")

## Laid out at the game's own 540 × 960, drawn at 2×.
const SIZE := Vector2i(1080, 1920)
const LAYOUT := Vector2(540, 960)
const ISLANDS := 100
## Where to get the game, at the end of the shared message. APP_STORE stays empty until the
## App Store listing has its id (https://apps.apple.com/app/id<number>); empty links are left out.
const APP_STORE := ""
const GOOGLE_PLAY := "https://play.google.com/store/apps/details?id=com.ggjumps.app"
## The stores' own badges (Apple's SVG, Google's PNG cropped to its border), drawn at the same
## height. Badge artwork must not be altered: only scaled.
const APP_STORE_BADGE := preload("res://ui/badges/app_store.svg")
const GOOGLE_PLAY_BADGE := preload("res://ui/badges/google_play.png")
const BADGE_HEIGHT := 40.0
const BADGE_GAP := 14.0
const CARD := Rect2(50, 170, 440, 250)

var ms := 0
var player := ""


## Draws the picture for a run of `run_ms` (by `player_name`, may be "") in a throwaway
## SubViewport under `host` and returns it.
static func make_image(host: Node, run_ms: int, player_name: String) -> Image:
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.size_2d_override = Vector2i(LAYOUT)
	viewport.size_2d_override_stretch = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var water := ColorRect.new()
	water.size = LAYOUT
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	mat.set_shader_parameter("origin", Vector2(140, -380))
	mat.set_shader_parameter("area", LAYOUT)
	mat.set_shader_parameter("t", 12.0)
	water.material = mat
	viewport.add_child(water)

	# The last stretch of the run: a sandbank and a grass island below, the finish above.
	var finish := _island(viewport, 99, Land.Kind.GRASS, 80.0, Vector2(292, 612))
	finish.finish = true
	_island(viewport, 98, Land.Kind.MOVING, 52.0, Vector2(118, 778))
	_island(viewport, 97, Land.Kind.GRASS, 64.0, Vector2(452, 1004))
	var bubble := Bubble.new()
	bubble.position = finish.position + Vector2(-18, 14)
	viewport.add_child(bubble)

	var card = new()
	card.ms = run_ms
	card.player = player_name
	card.size = LAYOUT
	viewport.add_child(card)

	host.add_child(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	return image


static func _island(parent: Node, i: int, kind: Land.Kind, radius: float, at: Vector2) -> Land:
	var l := Land.new()
	l.setup(i, kind, radius, 1.0, 0.0, 99000 + i)
	l.position = at
	parent.add_child(l)
	return l


## The message sent with the picture.
static func text(run_ms: int) -> String:
	var lines := PackedStringArray([
		"I made it across all %d islands of 99 jumps in %s 🫧" % [ISLANDS, LeaderboardApi.format_time(run_ms)],
		"One bubble, one slingshot, a lot of water. Can you beat my time?"])
	if APP_STORE != "":
		lines.append("App Store: " + APP_STORE)
	if GOOGLE_PLAY != "":
		lines.append("Google Play: " + GOOGLE_PLAY)
	return "\n".join(lines)


func _draw() -> void:
	var bold := Modal._weight(650)
	var medium := Modal._weight(500)
	var w := LAYOUT.x
	Logo.draw(self, Vector2(w / 2.0, 88), 0.45)

	# The glass card, as the windows in the game.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Modal.NAVY, 0.86)
	style.set_corner_radius_all(32)
	style.set_border_width_all(2)
	style.border_color = Color(1, 1, 1, 0.18)
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = 18
	style.anti_aliasing = true
	draw_style_box(style, CARD)
	var top := CARD.position.y
	_text(medium, "I made it across all %d islands in" % ISLANDS, top + 58, 24, Color(1, 1, 1, 0.85))
	_text(bold, LeaderboardApi.format_time(ms), top + 150, 76, Modal.MINT)
	if player != "":
		_text(medium, "— %s" % player, top + 210, 26, Color(1, 1, 1, 0.75))
	else:
		_text(medium, "Can you beat it?", top + 210, 24, Color(1, 1, 1, 0.65))

	# Kept above the bottom band that stories cover with their own buttons.
	_draw_badges(Vector2(w / 2.0, 862))


func _text(font: Font, line: String, baseline: float, font_size: int, color: Color, shadow := false) -> void:
	if shadow:
		draw_string(font, Vector2(0, baseline + 3), line, HORIZONTAL_ALIGNMENT_CENTER, LAYOUT.x, font_size, Color(0, 0.06, 0.12, 0.45))
	draw_string(font, Vector2(0, baseline), line, HORIZONTAL_ALIGNMENT_CENTER, LAYOUT.x, font_size, color)


## The official "Download on the App Store" and "Get it on Google Play" badges side by side,
## BADGE_HEIGHT tall around `center`.
func _draw_badges(center: Vector2) -> void:
	var badges: Array[Texture2D] = [APP_STORE_BADGE, GOOGLE_PLAY_BADGE]
	var widths: Array[float] = []
	var total := BADGE_GAP * (badges.size() - 1)
	for badge in badges:
		widths.append(BADGE_HEIGHT * badge.get_width() / badge.get_height())
		total += widths[-1]
	var x := center.x - total / 2.0
	for i in badges.size():
		draw_texture_rect(badges[i], Rect2(x, center.y - BADGE_HEIGHT / 2.0, widths[i], BADGE_HEIGHT), false)
		x += widths[i] + BADGE_GAP
