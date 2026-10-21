extends "res://scripts/ui/modal.gd"
## Out of lives: how far the run got, and a choice between watching an ad for one more life
## (carry on from the same island) and starting over. Without `offer_ad` (the last islands)
## only starting over, with a word on why.

signal watch_ad
signal retry


func _init(islands: int, total: int, offer_ad := true) -> void:
	super("Splash!", 440.0, false)
	_title.add_theme_font_size_override("font_size", 58)
	var line := Label.new()
	line.text = "Out of lives"
	content.add_child(line)
	var score := Label.new()
	score.text = "%d / %d islands" % [islands, total]
	score.theme_type_variation = "BigLabel"
	content.add_child(score)
	if offer_ad:
		var ad := Button.new()
		ad.text = "Watch an ad for +1 life"
		ad.pressed.connect(func():
			watch_ad.emit()
			queue_free())
		content.add_child(ad)
	else:
		var why := Label.new()
		why.text = "So close! The last islands are all yours: no extra lives from island 90 on."
		why.theme_type_variation = "MutedLabel"
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(why)
	var again := Button.new()
	again.text = "Try again" if offer_ad else "Start over"
	if offer_ad:
		again.theme_type_variation = "GhostButton"
	again.pressed.connect(func():
		retry.emit()
		queue_free())
	content.add_child(again)
