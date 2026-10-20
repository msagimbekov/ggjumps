extends Control
## Stand-in for a rewarded video ad until a real ad network is wired in: a full-screen
## placeholder that "plays" for DURATION seconds, then emits `rewarded` and closes.

signal rewarded

const DURATION := 2.0
const FONT := preload("res://fonts/Fredoka.ttf")

var _t := 0.0
var _font: FontVariation


func _init() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP  # an ad can't be tapped through
	_font = FontVariation.new()
	_font.base_font = FONT
	_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600}


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t >= DURATION:
		set_process(false)
		rewarded.emit()
		queue_free()


func _draw() -> void:
	var s := size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.04, 0.05, 0.08))
	# Placeholder "creative": a slowly turning sunburst.
	var c := s * 0.5 + Vector2(0, -40)
	for k in 12:
		var a := TAU * k / 12 + _t * 0.6
		draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(a - 0.12) * 600.0, c + Vector2.from_angle(a + 0.12) * 600.0]), Color(1, 1, 1, 0.04))
	draw_circle(c, 70.0, Color(0.30, 0.80, 1.0))
	draw_circle(c + Vector2(-22, -24), 16.0, Color(1, 1, 1, 0.85))
	draw_string(_font, Vector2(0, c.y + 140.0), "Your ad here", HORIZONTAL_ALIGNMENT_CENTER, s.x, 40, Color.WHITE)
	draw_string(_font, Vector2(0, c.y + 182.0), "(test ad)", HORIZONTAL_ALIGNMENT_CENTER, s.x, 22, Color(1, 1, 1, 0.5))
	draw_string(_font, Vector2(20, 50), "Ad", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.6))
	var left := ceili(maxf(DURATION - _t, 0.0))
	draw_string(_font, Vector2(0, 50), "Reward in %d " % left, HORIZONTAL_ALIGNMENT_RIGHT, s.x - 20.0, 20, Color(1, 1, 1, 0.6))
	# Progress along the bottom.
	var u := clampf(_t / DURATION, 0.0, 1.0)
	draw_rect(Rect2(0, s.y - 6.0, s.x, 6.0), Color(1, 1, 1, 0.15))
	draw_rect(Rect2(0, s.y - 6.0, s.x * u, 6.0), Color(0.55, 0.93, 0.72))
