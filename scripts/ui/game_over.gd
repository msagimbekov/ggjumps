extends "res://scripts/ui/modal.gd"
## Out of lives: how far the run got, and a choice between watching an ad for one more life
## (carry on from the same island) and starting over.

signal watch_ad
signal retry


func _init(jumps: int, total: int) -> void:
	super("Splash!", 440.0, false)
	var line := Label.new()
	line.text = "Out of lives"
	content.add_child(line)
	var score := Label.new()
	score.text = "%d / %d jumps" % [jumps, total]
	score.theme_type_variation = "BigLabel"
	content.add_child(score)
	var ad := Button.new()
	ad.text = "Watch an ad for +1 life"
	ad.pressed.connect(func():
		watch_ad.emit()
		queue_free())
	content.add_child(ad)
	var again := Button.new()
	again.text = "Try again"
	again.theme_type_variation = "GhostButton"
	again.pressed.connect(func():
		retry.emit()
		queue_free())
	content.add_child(again)
