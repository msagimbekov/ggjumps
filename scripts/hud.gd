class_name Hud
extends Control
## Jump counter, lives and the end-of-run overlay. Redraws only when something changed.

var best := 0
var total := 99
var lives := 3
var max_lives := 3
var title := ""
var subtitle := ""
var top_inset := 0.0  # notch / status bar, in viewport units


func set_info(b: int, l: int, t: String, s: String) -> void:
	if b == best and l == lives and t == title and s == subtitle:
		return
	best = b
	lives = l
	title = t
	subtitle = s
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var top := top_inset + 24.0
	_text(font, Vector2(24, top + 28), "%d / %d" % [best, total], 36, HORIZONTAL_ALIGNMENT_LEFT, size.x)
	for i in max_lives:
		var c := Vector2(size.x - 30.0 - i * 34.0, top + 14.0)
		if i < lives:
			draw_circle(c, 11.0, Color(0.30, 0.80, 1.0))
			draw_circle(c + Vector2(-3, -3), 3.0, Color(1, 1, 1, 0.85))
		else:
			draw_arc(c, 10.0, 0.0, TAU, 24, Color(1, 1, 1, 0.3), 2.0)
	var bar := Rect2(24, top + 46, size.x - 48, 6)
	draw_rect(bar, Color(1, 1, 1, 0.25))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(best) / total, bar.size.y)), Color(1, 1, 1, 0.9))
	if title != "":
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0.05, 0.1, 0.55))
		_text(font, Vector2(0, size.y * 0.42), title, 54, HORIZONTAL_ALIGNMENT_CENTER, size.x)
		_text(font, Vector2(0, size.y * 0.42 + 56), subtitle, 28, HORIZONTAL_ALIGNMENT_CENTER, size.x)


func _text(font: Font, pos: Vector2, s: String, fs: int, align: HorizontalAlignment, width: float) -> void:
	draw_string(font, pos + Vector2(2, 3), s, align, width, fs, Color(0, 0.1, 0.2, 0.5))
	draw_string(font, pos, s, align, width, fs, Color.WHITE)
