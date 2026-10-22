extends "res://scripts/ui/modal.gd"
## "How to play": cards with a small live picture (the game's own islands, bubble and pickups on
## a patch of sea) and a few lines each, with Skip and Next. Shown once after the first launch's
## welcome screen (`seen` / `mark_seen`, user://settings.cfg) and again from Settings.
## No class_name, so the OTA shape doesn't change.

const SETTINGS := "user://settings.cfg"
const Skins := preload("res://scripts/skins.gd")
const ART := Vector2(408, 176)
const SEA := Color(0.06, 0.36, 0.56)
const CARDS := [
	["Pull back to jump",
		"Put your finger down anywhere on the water, pull back away from where you want to go and let go. The further you pull, the further the bubble flies."],
	["Stay out of the water",
		"Miss an island and the bubble splashes into the sea: that costs a life. You start with 3, shown top right. Out of lives? Watch a short ad and carry on, up to island 90. The last ten are all yours."],
	["Three kinds of island",
		"Grass stops you where you land. On ice you keep sliding, so aim short. Sandbanks drift from side to side while you aim."],
	["Bubble drops",
		"Small bubbles sit on some islands. Land right next to one to pick it up; land anywhere else on that island and it pops. Each one fills the bubble next to your lives by a third, and three make an extra life."],
	["Spyglass",
		"The gold spyglass shows exactly where your jump will land, for 7 seconds. Soft pings count it down."],
	["Reach the last island",
		"Cross all 100 islands. Your time runs from the first jump; at the end, put your name on the leaderboard (the trophy, bottom left) and share your time."],
	["Settings",
		"The gear, bottom right, sets the music and sound volume and your bubble colour: Lagoon, Seafoam or Coral. These cards are in there too."],
]

var _page := 0
var _art: Control
var _stage: Node2D
var _over: Node2D
var _text: Label
var _dots: Control
var _next: Button
var _t := 0.0


static func seen() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	return cfg.get_value("tutorial", "seen", false)


static func mark_seen() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)  # keep the other settings in the file
	cfg.set_value("tutorial", "seen", true)
	cfg.save(SETTINGS)


func _init() -> void:
	super("How to play", 460.0, false)
	_art = Control.new()
	_art.custom_minimum_size = ART
	_art.clip_contents = true
	_art.draw.connect(func():
		var sea := StyleBoxFlat.new()
		sea.bg_color = SEA
		sea.set_corner_radius_all(20)
		sea.anti_aliasing = true
		_art.draw_style_box(sea, Rect2(Vector2.ZERO, ART)))
	content.add_child(_art)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(ART.x, 140)  # the longest card, so the buttons stay put
	_text.add_theme_font_size_override("font_size", 21)
	content.add_child(_text)
	_dots = Control.new()
	_dots.custom_minimum_size = Vector2(0, 12)
	_dots.draw.connect(_draw_dots)
	content.add_child(_dots)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	content.add_child(buttons)
	var skip := Button.new()
	skip.text = "Skip"
	skip.theme_type_variation = "GhostButton"
	skip.size_flags_horizontal = SIZE_EXPAND_FILL
	skip.pressed.connect(_finish)
	buttons.add_child(skip)
	_next = Button.new()
	_next.size_flags_horizontal = SIZE_EXPAND_FILL
	_next.pressed.connect(func():
		if _page + 1 < CARDS.size():
			_show(_page + 1)
		else:
			_finish())
	buttons.add_child(_next)
	_show(0)


func _process(delta: float) -> void:
	super(delta)
	_t += delta
	if _over:
		_over.queue_redraw()


func _finish() -> void:
	mark_seen()
	close()


func _show(page: int) -> void:
	_page = page
	set_title(CARDS[page][0])
	_text.text = CARDS[page][1]
	_next.text = "Let's go" if page == CARDS.size() - 1 else "Next"
	_dots.queue_redraw()
	if _stage:
		_stage.queue_free()
		_over.queue_free()
	_stage = Node2D.new()
	_art.add_child(_stage)
	_over = Node2D.new()
	_over.draw.connect(_draw_over)
	_art.add_child(_over)
	match page:
		0:
			_island(Land.Kind.GRASS, Vector2(110, 112), 40)
			_island(Land.Kind.GRASS, Vector2(310, 78), 34)
			_bubble(Vector2(110, 108), Vector2(-28, 24))
		1:
			_island(Land.Kind.GRASS, Vector2(120, 92), 44)
			_bubble(Vector2(120, 88))
		2:
			_island(Land.Kind.GRASS, Vector2(78, 80), 36)
			_island(Land.Kind.ICE, Vector2(204, 80), 36)
			_island(Land.Kind.MOVING, Vector2(330, 80), 36)
		3:
			_island(Land.Kind.GRASS, Vector2(130, 92), 50)
			_bubble(Vector2(104, 98))
		4:
			_island(Land.Kind.GRASS, Vector2(90, 120), 38)
			_island(Land.Kind.GRASS, Vector2(310, 70), 36)
			_bubble(Vector2(90, 116))
		5:
			var finish := _island(Land.Kind.GRASS, Vector2(150, 102), 50)
			finish.finish = true
			_bubble(Vector2(132, 112))


func _island(kind: Land.Kind, at: Vector2, r: float) -> Land:
	var l := Land.new()
	l.setup(0, kind, r, 0.9, 0.4, 900 + int(at.x))
	l.position = at
	_stage.add_child(l)
	return l


func _bubble(at: Vector2, pull := Vector2.ZERO) -> void:
	var b := Bubble.new()
	b.position = at
	b.pull = pull
	b.z_index = 1
	_stage.add_child(b)


## What each card draws over its islands: the jump's dotted arc, a splash, labels, pickups...
func _draw_over() -> void:
	var o := _over
	var font := ui_theme().default_font
	match _page:
		0:  # the drag (finger ring and line), then the arc the jump will take
			var finger := Vector2(110, 108) + Vector2(-46, 36)
			o.draw_dashed_line(Vector2(110, 108), finger, Color(1, 1, 1, 0.6), 2.0, 6.0)
			o.draw_arc(finger, 13.0, 0.0, TAU, 28, Color(1, 1, 1, 0.9), 3.0, true)
			_arc_dots(o, Vector2(110, 108), Vector2(310, 74), 10, fmod(_t * 0.7, 1.0))
		1:  # a bubble splashing down in the water, rings spreading; lives top right
			var at := Vector2(300, 104)
			for k in 3:
				var u := fmod(_t * 0.6 + k / 3.0, 1.0)
				o.draw_arc(at, 10.0 + 46.0 * u, 0.0, TAU, 40, Color(1, 1, 1, 0.7 * (1.0 - u)), 2.5, true)
			for i in 3:
				_life(o, Vector2(330 + i * 26, 24), i < 2)
		2:  # names under the islands
			for i in 3:
				o.draw_string(font, Vector2(78 + i * 126 - 60, 160), ["Grass", "Ice", "Sandbank"][i],
					HORIZONTAL_ALIGNMENT_CENTER, 120, 20, Color.WHITE)
		3:  # drops on the island, then the meter filling and the life it makes
			Pickup.draw_bubble(o, Vector2(150, 76), 10.0, 1.0, 1.0, 0.0)
			Pickup.draw_bubble(o, Vector2(166, 108), 10.0, 1.0, 1.0, 1.7)
			var filled := int(_t * 0.8) % 4
			var c := Vector2(282, 90)
			o.draw_circle(c, 20.0, Color(1, 1, 1, 0.08))
			if filled > 0:
				var level := c.y + 20.0 - 40.0 * filled / 3.0
				var circle := PackedVector2Array()
				for n in 32:
					circle.append(c + Vector2.from_angle(TAU * n / 32.0) * 20.0)
				var below := PackedVector2Array([Vector2(c.x - 21, level), Vector2(c.x + 21, level),
					Vector2(c.x + 21, c.y + 21), Vector2(c.x - 21, c.y + 21)])
				for part in Geometry2D.intersect_polygons(circle, below):
					o.draw_colored_polygon(part, Skins.color("body"))
			o.draw_arc(c, 20.0, 0.0, TAU, 40, Color(1, 1, 1, 0.5).lerp(Skins.color("rim"), filled / 3.0), 3.0, true)
			o.draw_string(font, Vector2(c.x - 40, 140), "%d / 3" % filled, HORIZONTAL_ALIGNMENT_CENTER, 80, 20, Color.WHITE)
			o.draw_string(font, Vector2(316, 98), "→", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, 0.8))
			_life(o, Vector2(364, 90), true)
		4:  # the landing line to a ring on the far island, the spyglass in the corner
			var from := Vector2(90, 116)
			var to := Vector2(310, 72)
			o.draw_dashed_line(from, to, Color(1.0, 0.82, 0.25, 0.9), 3.0, 9.0)
			o.draw_arc(to, 14.0, 0.0, TAU, 32, Color(1.0, 0.82, 0.25), 3.0, true)
			o.draw_circle(to, 3.5, Color(1.0, 0.82, 0.25))
			Pickup.draw_lens(o, Vector2(372, 146), 1.0, 1.0, _t * 2.5)
		5:  # the run's time ticking up beside the finish
			var ms := int(_t * 1000.0) + 754000
			var line := "%d:%02d.%d" % [ms / 60000, (ms / 1000) % 60, (ms % 1000) / 100]
			o.draw_string(font, Vector2(236, 106), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(0.55, 0.93, 0.72))
		6:  # the gear and the three bubble colours
			_gear(o, Vector2(64, 88), Color(1, 1, 1, 0.9))
			for i in 3:
				var c := Vector2(170 + i * 84, 76)
				Pickup.draw_bubble(o, c, 24.0, 1.0, 1.0, i * 1.7, i, 0.3, 0.45)
				o.draw_string(font, Vector2(c.x - 50, 138), Skins.SKINS[i]["name"], HORIZONTAL_ALIGNMENT_CENTER, 100, 18,
					Color.WHITE)


## White dots along a flattened half circle from `a` to `b`, the leading ones brighter as `u` runs 0..1.
func _arc_dots(o: CanvasItem, a: Vector2, b: Vector2, count: int, u: float) -> void:
	var mid := (a + b) / 2.0
	var r := a.distance_to(b) / 2.0
	var tilt := (b - a).angle()
	for n in count:
		var k := (n + 1.0) / (count + 1.0)
		var p := mid + (Vector2(-cos(PI * k), -sin(PI * k) * 0.55) * r).rotated(tilt)
		var lit := clampf(1.0 - absf(k - u) * 3.0, 0.35, 1.0)
		o.draw_circle(p, 3.0 + k * 2.0, Color(1, 1, 1, lit))


func _life(o: CanvasItem, c: Vector2, full: bool) -> void:
	if full:
		o.draw_circle(c, 11.0, Skins.color("body"))
		o.draw_arc(c, 11.0, 0.0, TAU, 24, Skins.color("rim"), 2.0, true)
		o.draw_circle(c + Vector2(-3.5, -3.5), 3.0, Color(1, 1, 1, 0.9))
	else:
		o.draw_arc(c, 9.5, 0.0, TAU, 24, Color(1, 1, 1, 0.35), 2.5, true)


func _gear(o: CanvasItem, c: Vector2, col: Color) -> void:
	for k in 8:
		var d := Vector2.from_angle(TAU * k / 8)
		var s := d.orthogonal()
		o.draw_colored_polygon(PackedVector2Array([
			c + d * 20.0 + s * 9.0, c + d * 34.0 + s * 6.4, c + d * 34.0 - s * 6.4, c + d * 20.0 - s * 9.0,
		]), col)
	o.draw_arc(c, 19.0, 0.0, TAU, 40, col, 12.0, true)


func _draw_dots() -> void:
	var n := CARDS.size()
	var w := _dots.size.x
	for i in n:
		var c := Vector2(w / 2.0 + (i - (n - 1) / 2.0) * 18.0, 6.0)
		_dots.draw_circle(c, 4.5 if i == _page else 3.5, MINT if i == _page else Color(1, 1, 1, 0.3))
