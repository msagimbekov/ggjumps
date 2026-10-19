class_name Hud
extends Control
## Jump counter, lives, progress and the end-of-run card. Redraws only when something changed.

const FONT := preload("res://fonts/Fredoka.ttf")
const TOOL_SIZE := 46.0
const DROPS_SLOTS := 3
const INK := Color(0.02, 0.12, 0.22, 0.55)
const GLASS := Color(0.02, 0.14, 0.26, 0.42)

var best := 0
var total := 99
var lives := 3
var max_lives := 3
var title := ""
var subtitle := ""
var top_inset := 0.0  # notch / status bar, in viewport units

var drops := 0
var radar_left := 0.0
var tools := false
var radar := false
var keep := false
var ids := false

var _drop_pulse := 0.0
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


func set_tools(show: bool, radar_on: bool, keep_on: bool, ids_on: bool) -> void:
	if show == tools and radar_on == radar and keep_on == keep and ids_on == ids:
		return
	tools = show
	radar = radar_on
	keep = keep_on
	ids = ids_on
	queue_redraw()


## Small square tool buttons stacked under the lives pill, right-aligned with it.
func radar_rect() -> Rect2:
	return _tool_rect(0)


func keep_rect() -> Rect2:
	return _tool_rect(1)


func ids_rect() -> Rect2:
	return _tool_rect(2)


func _tool_rect(n: int) -> Rect2:
	var lp := lives_rect()
	return Rect2(lp.end.x - TOOL_SIZE, lp.end.y + 10.0 + n * (TOOL_SIZE + 8.0), TOOL_SIZE, TOOL_SIZE)


func set_pickups(d: int, radar: float) -> void:
	if d > drops:
		_drop_pulse = 0.5
	if d == drops and radar <= 0.0 and radar_left <= 0.0:
		return
	drops = d
	radar_left = radar
	queue_redraw()


func _process(delta: float) -> void:
	if _drop_pulse > 0.0 or _life_flash > 0.0:
		_drop_pulse = maxf(_drop_pulse - delta, 0.0)
		_life_flash = maxf(_life_flash - delta, 0.0)
		queue_redraw()


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
	return Rect2(size.x - w - 18.0, top_inset + 18.0, w, 52.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var top := top_inset + 18.0

	# Score pill: big jump count, muted total.
	var num := str(best)
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
	for i in maxi(max_lives, lives):
		var c := Vector2(lp.position.x + 32.0 + i * 36.0, lp.position.y + lp.size.y * 0.5)
		if i < lives:
			draw_circle(c, 13.0, Color(0.30, 0.80, 1.0))
			draw_arc(c, 13.0, 0.0, TAU, 24, Color(0.10, 0.50, 0.80), 2.0)
			draw_circle(c + Vector2(-4, -4), 3.5, Color(1, 1, 1, 0.9))
		else:
			draw_arc(c, 11.0, 0.0, TAU, 24, Color(1, 1, 1, 0.3), 2.5)
	if _life_flash > 0.0 and lives > 0:
		var nc := Vector2(lp.position.x + 32.0 + (lives - 1) * 36.0, lp.position.y + lp.size.y * 0.5)
		draw_arc(nc, 13.0 + 22.0 * (1.0 - _life_flash), 0.0, TAU, 32, Color(1, 1, 1, _life_flash), 3.0)

	# Collected drops: three slots that fill in; radar countdown next to them while it runs.
	var slots := Rect2(18, top + 84.0, 20.0 + DROPS_SLOTS * 32.0, 44.0)
	draw_style_box(_pill, slots)
	for i in DROPS_SLOTS:
		var pulse := 1.0
		if i == drops - 1 and _drop_pulse > 0.0:
			pulse = 1.0 + 0.35 * sin(PI * _drop_pulse / 0.5)
		Pickup.draw_drop(self, Vector2(slots.position.x + 26.0 + i * 32.0, slots.position.y + 28.0), 0.78 * pulse, 1.0 if i < drops else 0.0, 1.0)
	if radar_left > 0.0:
		var rp := Rect2(slots.end.x + 10.0, slots.position.y, 44.0, 44.0)
		draw_style_box(_pill, rp)
		var blink := radar_left > 2.0 or int(radar_left * 5.0) % 2 == 0
		var rc := rp.get_center()
		Pickup.draw_lens(self, rc, 0.7, 1.0 if blink else 0.25, radar_left * 2.5)
		draw_arc(rc, 20.0, -PI / 2.0, -PI / 2.0 + TAU * radar_left / 7.0, 24, Color(Pickup.GOLD.r, Pickup.GOLD.g, Pickup.GOLD.b, 0.9), 3.0)

	if tools:
		_tool_button(radar_rect(), radar, 0)
		_tool_button(keep_rect(), keep, 1)
		_tool_button(ids_rect(), ids, 2)

	# Progress: thin track with a bubble riding the fill.
	var bar := Rect2(18, top + 66.0, size.x - 36.0, 8.0)
	draw_rect(bar, Color(0, 0.1, 0.2, 0.35))
	var fill := bar.size.x * float(best) / total
	if fill > 0.0:
		draw_rect(Rect2(bar.position, Vector2(fill, bar.size.y)), Color(1, 1, 1, 0.9))
	var knob := Vector2(bar.position.x + fill, bar.position.y + bar.size.y * 0.5)
	draw_circle(knob, 8.0, Color(0.30, 0.80, 1.0))
	draw_arc(knob, 8.0, 0.0, TAU, 20, Color.WHITE, 2.0)

	if title != "":
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0.05, 0.1, 0.45))
		var card := Rect2(size.x * 0.5 - 220.0, size.y * 0.5 - 150.0, 440.0, 270.0)
		draw_style_box(_card, card)
		_text_c(_bold, card.position.y + 105.0, title, 64, Color.WHITE)
		_text_c(_medium, card.position.y + 160.0, "%d / %d jumps" % [best, total], 28, Color(0.72, 0.92, 1.0))
		_text_c(_medium, card.position.y + 225.0, subtitle, 24, Color(1, 1, 1, 0.7))


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


func _text(font: Font, pos: Vector2, s: String, fs: int, col: Color) -> void:
	draw_string(font, pos + Vector2(0, 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _text_c(font: Font, y: float, s: String, fs: int, col: Color) -> void:
	draw_string(font, Vector2(0, y + 3), s, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, INK)
	draw_string(font, Vector2(0, y), s, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, col)
