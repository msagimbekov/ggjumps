extends Control
## Settings: the bubble in each colour, side by side; tap one to wear it.

const Skins := preload("res://scripts/skins.gd")
const FONT := preload("res://fonts/Fredoka.ttf")
const MINT := Color(0.55, 0.93, 0.72)
const R := 26.0

var on_change: Callable  # called after a new colour is picked
var _font: FontVariation


func _init() -> void:
	custom_minimum_size = Vector2(0, 112)
	mouse_filter = MOUSE_FILTER_STOP
	_font = FontVariation.new()
	_font.base_font = FONT
	_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600}


func _centre(i: int) -> Vector2:
	var step := size.x / Skins.SKINS.size()
	return Vector2(step * (i + 0.5), 42.0)


func _process(_delta: float) -> void:
	queue_redraw()  # the bubbles wobble


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		for i in Skins.SKINS.size():
			if event.position.distance_to(_centre(i)) < R + 22.0:
				if i != Skins.current:
					Skins.pick(i)
					if on_change.is_valid():
						on_change.call()
				queue_redraw()
		accept_event()


func _draw() -> void:
	Skins.color("body")  # loads the saved choice
	for i in Skins.SKINS.size():
		var c := _centre(i)
		var chosen := i == Skins.current
		if chosen:
			draw_circle(c, R + 12.0, Color(MINT.r, MINT.g, MINT.b, 0.16))
			draw_arc(c, R + 12.0, 0.0, TAU, 48, MINT, 3.0, true)
		Pickup.draw_bubble(self, c, R, 1.0, 1.0, i * 1.7, i)
		var name: String = Skins.SKINS[i]["name"]
		draw_string(_font, Vector2(c.x - 60.0, 104.0), name, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 20, Color.WHITE if chosen else Color(1, 1, 1, 0.55))
