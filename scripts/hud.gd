class_name Hud
extends Control
## Jump counter, lives, progress and the end-of-run card. Redraws only when something changed.

const FONT := preload("res://fonts/Fredoka.ttf")
const Skins := preload("res://scripts/skins.gd")
const TOOL_SIZE := 46.0
const DROPS_SLOTS := 3  # drops per life: each fills the meter by a third
const MAX_ICONS := 4  # more lives than this are shown as a number
const INK := Color(0.02, 0.12, 0.22, 0.55)
const GLASS := Color(0.02, 0.14, 0.26, 0.42)

var best := 0
var total := 100  # islands
var lives := 3
var max_lives := 3
var title := ""
var subtitle := ""
var top_inset := 0.0  # notch / status bar, in viewport units
var bottom_inset := 0.0  # home indicator / nav bar, in viewport units
var placing := false  # tools: place-the-bubble mode is on (shows a hint)

var drops := 0
var radar_left := 0.0
var merge := 0.0  # 0..1 while the full life meter holds before it empties
var tools := false
var radar := false
var keep := false
var ids := false
var place := false
var show_fps := false  # tools: frame rate readout under the score
var cap60 := false  # tools: frame rate capped at 60
var no_water := false  # tools: the sea is hidden (second tap on "fps"), to compare frame times
var water_viewport: RID  # also timed in the readout (the sea renders in its own viewport)

var _fps_frames := 0
var _fps_time := 0.0
var _fps_worst := 0.0
var _fps_script := 0.0
var _fps_cpu := 0.0
var _fps_gpu := 0.0
var _fps_text := ""
var _fps_detail := ""

var _drop_pulse := 0.0
var _fill := 0.0  # the life meter's shown level: drops / DROPS_SLOTS
var _was_moving := false
var _pop := 0.0  # 1..0: the full meter just turned into a life
var _life_flash := 0.0
var _bold: FontVariation
var _medium: FontVariation
var _pill := StyleBoxFlat.new()
var _card := StyleBoxFlat.new()


func _init() -> void:
	_bold = _weight(650)
	_medium = _weight(500)
	for sb: StyleBoxFlat in [_pill, _card]:
		sb.bg_color = GLASS
		sb.set_corner_radius_all(26)
		sb.border_color = Color(1, 1, 1, 0.18)
		sb.set_border_width_all(2)
	_card.bg_color = Color(0.02, 0.14, 0.26, 0.78)
	_card.set_corner_radius_all(36)


func _weight(w: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = FONT
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): w}
	return f


func set_tools(show: bool, radar_on: bool, keep_on: bool, ids_on: bool, place_on: bool) -> void:
	if show == tools and radar_on == radar and keep_on == keep and ids_on == ids and place_on == place:
		return
	tools = show
	radar = radar_on
	keep = keep_on
	ids = ids_on
	place = place_on
	queue_redraw()


## Small square tool buttons stacked under the lives pill, right-aligned with it.
func radar_rect() -> Rect2:
	return _tool_rect(0)


func keep_rect() -> Rect2:
	return _tool_rect(1)


func ids_rect() -> Rect2:
	return _tool_rect(2)


func place_rect() -> Rect2:
	return _tool_rect(3)


func intro_rect() -> Rect2:
	return _tool_rect(4)


func fps_rect() -> Rect2:
	return _tool_rect(5)


func cap_rect() -> Rect2:
	return _tool_rect(6)


## Between the top row (score, lives) and the bottom row (leaderboard, settings): a press here
## grabs the bubble.
func play_rect() -> Rect2:
	var top := top_inset + 18.0 + 52.0 + 12.0
	return Rect2(0.0, top, size.x, size.y - 18.0 - 52.0 - 12.0 - bottom_inset - top)


## Bottom-left: opens the leaderboard.
func board_rect() -> Rect2:
	return Rect2(18.0, size.y - 52.0 - 18.0 - bottom_inset, 52.0, 52.0)


func _tool_rect(n: int) -> Rect2:
	var lp := lives_rect()
	return Rect2(lp.end.x - TOOL_SIZE, lp.end.y + 10.0 + n * (TOOL_SIZE + 8.0), TOOL_SIZE, TOOL_SIZE)


func set_pickups(d: int, radar: float, merging: float) -> void:
	if d > drops:
		_drop_pulse = 0.5
	if d == drops and radar <= 0.0 and radar_left <= 0.0 and merging <= 0.0 and merge <= 0.0:
		return
	drops = d
	radar_left = radar
	merge = merging
	queue_redraw()


func _process(delta: float) -> void:
	_drop_pulse = maxf(_drop_pulse - delta, 0.0)
	if show_fps:
		_count_frame(delta)
	_pop = maxf(_pop - delta * 2.0, 0.0)
	var fill := float(drops) / DROPS_SLOTS
	if drops == 0 and _fill > 0.98:
		_pop = 1.0
	if fill != _fill:
		_fill = fill
		queue_redraw()
	_life_flash = maxf(_life_flash - delta, 0.0)
	# Redraw only while something moves (and once more as it stops): the HUD is static otherwise.
	var moving := _drop_pulse > 0.0 or _pop > 0.0 or _life_flash > 0.0 or show_fps or radar_left > 0.0 or merge > 0.0
	if moving or _was_moving:
		queue_redraw()
	_was_moving = moving


func set_info(b: int, l: int, t: String, s: String) -> void:
	if l > lives and lives > 0:
		_life_flash = 1.0
	if b == best and l == lives and t == title and s == subtitle:
		return
	best = b
	lives = l
	title = t
	subtitle = s
	queue_redraw()


## Tap target around the lives icons (the hidden aim-line switch).
func lives_rect() -> Rect2:
	var w := 28.0 + maxi(max_lives, lives) * 36.0
	if lives > MAX_ICONS:  # too many for icons: "6 x" and one bubble
		w = 28.0 + _bold.get_string_size("%d ×" % lives, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x + 34.0
	return Rect2(size.x - w - 18.0, top_inset + 18.0, w, 52.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var top := top_inset + 18.0

	# Score pill: the island the bubble has reached (the start is island 1), muted total.
	var num := str(best + 1)
	var num_w := _bold.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	var tot := " / %d" % total
	var tot_w := _medium.get_string_size(tot, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	var pill := Rect2(18, top, num_w + tot_w + 40.0, 52.0)
	draw_style_box(_pill, pill)
	_text(_bold, Vector2(pill.position.x + 20.0, top + 39.0), num, 40, Color.WHITE)
	_text(_medium, Vector2(pill.position.x + 20.0 + num_w, top + 38.0), tot, 22, Color(1, 1, 1, 0.65))

	# Lives pill: filled bubbles, hollow rings for lost ones.
	var lp := lives_rect()
	draw_style_box(_pill, lp)
	if lives > MAX_ICONS:
		var label := "%d ×" % lives
		var tw := _bold.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		_text(_bold, Vector2(lp.position.x + 16.0, lp.position.y + 35.0), label, 26, Color.WHITE)
		_life_bubble(Vector2(lp.position.x + 16.0 + tw + 18.0, lp.position.y + lp.size.y * 0.5), true)
	else:
		for i in maxi(max_lives, lives):
			_life_bubble(Vector2(lp.position.x + 32.0 + i * 36.0, lp.position.y + lp.size.y * 0.5), i < lives)
	if _life_flash > 0.0 and lives > 0:
		var last := lives - 1 if lives <= MAX_ICONS else 0
		var nc := Vector2(lp.position.x + 32.0 + last * 36.0, lp.position.y + lp.size.y * 0.5)
		if lives > MAX_ICONS:
			nc = Vector2(lp.end.x - 28.0, lp.position.y + lp.size.y * 0.5)
		draw_arc(nc, 13.0 + 22.0 * (1.0 - _life_flash), 0.0, TAU, 32, Color(1, 1, 1, _life_flash), 3.0)

	# Life meter: one life-sized bubble in its own pill left of the lives; each collected drop
	# fills it by a third, full it becomes a life and empties again.
	var meter := meter_rect()
	draw_style_box(_pill, meter)
	_meter_bubble(meter.get_center())

	# Spyglass countdown (the landing line; called radar in the code), right after the score.
	if radar_left > 0.0:
		var rp := Rect2(pill.end.x + 10.0, top + 4.0, 44.0, 44.0)
		draw_style_box(_pill, rp)
		var rc := rp.get_center()
		Pickup.draw_box(self, rc, 0.62, Pickup.Kind.RADAR, 1.0, 0.35 + 0.65 * Pickup.radar_alpha(radar_left), radar_left * 2.5)
		draw_arc(rc, 20.0, -PI / 2.0, -PI / 2.0 + TAU * radar_left / 7.0, 24, Color(Pickup.GOLD.r, Pickup.GOLD.g, Pickup.GOLD.b, 0.9), 2.5)

	if tools:
		_tool_button(radar_rect(), radar, 0)
		_tool_button(keep_rect(), keep, 1)
		_tool_button(ids_rect(), ids, 2)
		_tool_button(place_rect(), place, 3)
		_tool_button(intro_rect(), false, 4)
		_tool_button(fps_rect(), show_fps, 5)
		_tool_button(cap_rect(), cap60, 6)
	if show_fps and _fps_text != "":
		_text(_bold, Vector2(18.0, top + 82.0), _fps_text, 20, Color.WHITE)
		_text(_medium, Vector2(18.0, top + 106.0), _fps_detail, 18, Color(1, 1, 1, 0.85))

	var br := board_rect()
	var bsb := _pill.duplicate() as StyleBoxFlat
	bsb.set_corner_radius_all(16)
	draw_style_box(bsb, br)
	_trophy(br.get_center())
	if place:
		_text_c(_medium, size.y - 100.0 - bottom_inset, "Drag to scroll, tap an island", 22, Color.WHITE)

	if title != "":
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0.05, 0.1, 0.45))
		var card := Rect2(size.x * 0.5 - 220.0, size.y * 0.5 - 150.0, 440.0, 270.0)
		draw_style_box(_card, card)
		_text_c(_bold, card.position.y + 105.0, title, 64, Color.WHITE)
		_text_c(_medium, card.position.y + 160.0, "%d / %d islands" % [best + 1, total], 28, Color(0.72, 0.92, 1.0))
		_text_c(_medium, card.position.y + 225.0, subtitle, 24, Color(1, 1, 1, 0.7))


## Frame rate over the last half second, the slowest frame in it and the screen's refresh
## rate: "58 fps  worst 24 ms  120 Hz". Steady at the refresh rate (or exactly half) is smooth;
## a high worst time means hitches. The second line splits an average frame: game logic,
## the renderer's CPU work and the GPU's (0 where the driver can't time it), in ms.
func _count_frame(delta: float) -> void:
	var rids := [get_viewport().get_viewport_rid(), water_viewport]
	if _fps_frames == 0:
		for rid: RID in rids:
			if rid.is_valid():
				RenderingServer.viewport_set_measure_render_time(rid, true)
	_fps_frames += 1
	_fps_time += delta
	_fps_worst = maxf(_fps_worst, delta)
	_fps_script += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	for rid: RID in rids:
		if rid.is_valid():
			_fps_cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
			_fps_gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	if _fps_time < 0.5:
		return
	var hz := DisplayServer.screen_get_refresh_rate()
	_fps_text = "%d fps  worst %d ms%s%s" % [roundi(_fps_frames / _fps_time), roundi(_fps_worst * 1000.0),
		"  %d Hz" % roundi(hz) if hz > 0.0 else "", ("  no water" if no_water else "") + ("  cap 60" if cap60 else "")]
	var n := float(_fps_frames)
	_fps_detail = "game %.1f  render %.1f  gpu %.1f ms" % [_fps_script / n, _fps_cpu / n, _fps_gpu / n]
	_fps_frames = 0
	_fps_time = 0.0
	_fps_worst = 0.0
	_fps_script = 0.0
	_fps_cpu = 0.0
	_fps_gpu = 0.0


## The life meter's pill, just left of the lives pill and the same height.
func meter_rect() -> Rect2:
	var lp := lives_rect()
	return Rect2(lp.position.x - 10.0 - lp.size.y, lp.position.y, lp.size.y, lp.size.y)


## The meter: an empty life ring filled from the bottom with the bubble's colour, a third per
## drop (a flat, still level); full it shows as a whole life, then bursts (a ring) when it empties.
func _meter_bubble(c: Vector2) -> void:
	var r := 13.0 * (1.0 + 0.25 * sin(PI * _drop_pulse / 0.5) if _drop_pulse > 0.0 else 1.0)
	draw_circle(c, r, Color(1, 1, 1, 0.07))
	if _fill > 0.0:
		var circle := PackedVector2Array()
		for n in 32:
			circle.append(c + Vector2.from_angle(TAU * n / 32.0) * r)
		var level := c.y + r - 2.0 * r * _fill
		var water := PackedVector2Array([Vector2(c.x - r - 1.0, level), Vector2(c.x + r + 1.0, level),
			Vector2(c.x + r + 1.0, c.y + r + 1.0), Vector2(c.x - r - 1.0, c.y + r + 1.0)])
		for part in Geometry2D.intersect_polygons(circle, water):
			draw_colored_polygon(part, Skins.color("body"))
		if _fill > 0.98:
			draw_circle(c + Vector2(-4, -4), 3.5, Color(1, 1, 1, 0.9))
	var rim := Color(1, 1, 1, 0.3).lerp(Skins.color("rim"), _fill)
	draw_arc(c, r, 0.0, TAU, 32, rim, 2.5 if _fill < 0.98 else 2.0, true)
	if _pop > 0.0:
		draw_arc(c, 13.0 + 20.0 * (1.0 - _pop), 0.0, TAU, 32, Color(1, 1, 1, _pop), 3.0)


## One life: the player's bubble in miniature, or a hollow ring for a lost one.
func _life_bubble(c: Vector2, full: bool) -> void:
	if full:
		draw_circle(c, 13.0, Skins.color("body"))
		draw_arc(c, 13.0, 0.0, TAU, 24, Skins.color("rim"), 2.0)
		draw_circle(c + Vector2(-4, -4), 3.5, Color(1, 1, 1, 0.9))
	else:
		draw_arc(c, 11.0, 0.0, TAU, 24, Color(1, 1, 1, 0.3), 2.5)


func _tool_button(r: Rect2, on: bool, icon: int) -> void:
	var sb := _pill.duplicate() as StyleBoxFlat
	sb.set_corner_radius_all(14)
	if on:
		sb.bg_color = Color(0.20, 0.62, 0.32, 0.85)
	draw_style_box(sb, r)
	var c := r.get_center()
	var col := Color.WHITE if on else Color(1, 1, 1, 0.75)
	match icon:
		0:  # radar: ring, cross hairs, centre dot
			draw_arc(c, 11.0, 0.0, TAU, 24, col, 2.5)
			draw_line(c + Vector2(-16, 0), c + Vector2(-6, 0), col, 2.5)
			draw_line(c + Vector2(6, 0), c + Vector2(16, 0), col, 2.5)
			draw_line(c + Vector2(0, -16), c + Vector2(0, -6), col, 2.5)
			draw_line(c + Vector2(0, 6), c + Vector2(0, 16), col, 2.5)
			draw_circle(c, 2.5, col)
		1:  # keep lives: heart
			draw_circle(c + Vector2(-5.5, -3), 6.0, col)
			draw_circle(c + Vector2(5.5, -3), 6.0, col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-11, 0), c + Vector2(11, 0), c + Vector2(0, 13)]), col)
		2:  # island numbers: hash sign
			draw_string(_bold, Vector2(r.position.x, c.y + 9.0), "#", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 28, col)
		3:  # place the bubble: map pin
			draw_colored_polygon(PackedVector2Array([c + Vector2(-8, -4), c + Vector2(8, -4), c + Vector2(0, 14)]), col)
			draw_circle(c + Vector2(0, -5), 9.0, col)
			draw_circle(c + Vector2(0, -5), 3.5, Color(0.02, 0.14, 0.26))
		6:  # frame rate cap: "60"
			draw_string(_bold, Vector2(r.position.x, c.y + 7.0), "60", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 20, col)
		5:  # frame rate: "fps"
			draw_string(_bold, Vector2(r.position.x, c.y + 6.0), "fps", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 17, col)
		4:  # replay the welcome screen: play triangle
			draw_colored_polygon(PackedVector2Array([c + Vector2(-7, -11), c + Vector2(11, 0), c + Vector2(-7, 11)]), col)


## Cup with handles on a little stand, in the same soft white as the settings gear.
func _trophy(c: Vector2) -> void:
	var col := Color(1, 1, 1, 0.85)
	draw_arc(c + Vector2(-10, -6), 6.0, PI * 0.5, PI * 1.5, 12, col, 3.0, true)
	draw_arc(c + Vector2(10, -6), 6.0, -PI * 0.5, PI * 0.5, 12, col, 3.0, true)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-11, -14), c + Vector2(11, -14), c + Vector2(9, -2), c + Vector2(4, 4), c + Vector2(-4, 4), c + Vector2(-9, -2),
	]), col)
	draw_rect(Rect2(c + Vector2(-2.5, 4), Vector2(5, 6)), col)
	draw_rect(Rect2(c + Vector2(-9, 10), Vector2(18, 5)), col)


func _text(font: Font, pos: Vector2, s: String, fs: int, col: Color) -> void:
	draw_string(font, pos + Vector2(0, 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _text_c(font: Font, y: float, s: String, fs: int, col: Color) -> void:
	draw_string(font, Vector2(0, y + 3), s, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, INK)
	draw_string(font, Vector2(0, y), s, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, col)
