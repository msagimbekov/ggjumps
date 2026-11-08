class_name SettingsPanel
extends Control
## Gear button in the bottom-right corner; it opens the Settings window: music and effects
## volume (each with an icon that mutes it and brings the old volume back), then the bubble colour,
## a way back to the "How to play" cards, "Rate" (the game's store page) and "Share" (the store links
## through the share sheet), "Send feedback" (an email), a link to the privacy policy (with Privacy
## options where the ads' consent form must be reachable).
## Taps come from main.gd through handle(), before the game sees them.

const Modal := preload("res://scripts/ui/modal.gd")
const SoundRow := preload("res://scripts/ui/sound_row.gd")
const SkinRow := preload("res://scripts/ui/skin_row.gd")
const ExternalLink := preload("res://scripts/ui/external_link.gd")
const Share := preload("res://scripts/share.gd")
const ShareCard := preload("res://scripts/ui/share_card.gd")
const BUTTON := 52.0
const PRIVACY_URL := "https://msagimbekov.github.io/ggjumps/privacy.html"
## Rating: the store app on the phone (the App Store opens straight on "Write a Review").
const RATE_ANDROID := "market://details?id=com.ggcuts.jumps"
const RATE_IOS := "https://apps.apple.com/app/id6824316189?action=write-review"
const FEEDBACK_URL := "mailto:madi.sagimbekov@gmail.com?subject=99%20jumps%20feedback"

var sound: Sound
var modal_parent: Node  # layer the window opens in
var on_skin_change: Callable  # the bubble colour was changed
var on_how_to: Callable  # opens the "How to play" cards
var ads: Node  # scripts/ads.gd: "Privacy options" where the ads' consent form must be reachable
var bottom_inset := 0.0  # home indicator / nav bar, in viewport units
var is_open := false

var _pill := StyleBoxFlat.new()


func _init() -> void:
	_pill.bg_color = Color(0.02, 0.14, 0.26, 0.42)
	_pill.border_color = Color(1, 1, 1, 0.18)
	_pill.set_border_width_all(2)
	_pill.set_corner_radius_all(16)


func button_rect() -> Rect2:
	return Rect2(size.x - BUTTON - 18.0, size.y - BUTTON - 18.0 - bottom_inset, BUTTON, BUTTON)


## Returns true when the event belonged to the settings (the game should ignore it).
func handle(event: InputEvent) -> bool:
	if is_open:
		return true  # the window's own controls take it
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if button_rect().has_point(event.position):
			open()
			return true
	return false


func open() -> void:
	if is_open:
		return
	is_open = true
	var m := Modal.new("Settings")
	var heading := Label.new()
	heading.text = "Sound"
	heading.theme_type_variation = "MutedLabel"
	m.content.add_child(heading)
	m.content.add_child(SoundRow.new(sound, 0))
	m.content.add_child(SoundRow.new(sound, 1))
	var look := Label.new()
	look.text = "Bubble"
	look.theme_type_variation = "MutedLabel"
	m.content.add_child(look)
	var skins := SkinRow.new()
	skins.on_change = on_skin_change
	m.content.add_child(skins)
	var how := Button.new()
	how.text = "How to play"
	how.theme_type_variation = "GhostButton"
	how.pressed.connect(func():
		m.close()
		if on_how_to.is_valid():
			on_how_to.call())
	m.content.add_child(how)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var rate := Button.new()
	rate.text = "Rate"
	rate.theme_type_variation = "GhostButton"
	rate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rate.pressed.connect(open_store_page)
	row.add_child(rate)
	var share := Button.new()
	share.text = "Share"
	share.theme_type_variation = "GhostButton"
	share.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	share.pressed.connect(func():
		if not Share.share("99 jumps", share_text()):
			share.text = "Link copied")
	row.add_child(share)
	m.content.add_child(row)
	m.content.add_child(ExternalLink.new("Send feedback", FEEDBACK_URL))
	m.content.add_child(ExternalLink.new("Privacy policy", PRIVACY_URL))
	if ads and ads.privacy_options_required():
		var privacy := Button.new()
		privacy.text = "Privacy options"
		privacy.theme_type_variation = "GhostButton"
		privacy.pressed.connect(func():
			m.close()
			ads.show_privacy_options())
		m.content.add_child(privacy)
	m.closed.connect(_on_closed)
	modal_parent.add_child(m)
	queue_redraw()


## Opens the game's page in the phone's store app, so the player can rate it.
static func open_store_page() -> void:
	match OS.get_name():
		"iOS":
			OS.shell_open(RATE_IOS)
		"Android":
			if OS.shell_open(RATE_ANDROID) != OK:
				OS.shell_open(ShareCard.GOOGLE_PLAY)
		_:
			OS.shell_open(ShareCard.GOOGLE_PLAY)


## The message for "Share": what the game is, and where to get it.
static func share_text() -> String:
	var lines := PackedStringArray([
		"99 jumps: drag, aim and jump a liquid bubble across 100 islands. Don't fall in! 🫧"])
	if ShareCard.APP_STORE != "":
		lines.append("App Store: " + ShareCard.APP_STORE)
	if ShareCard.GOOGLE_PLAY != "":
		lines.append("Google Play: " + ShareCard.GOOGLE_PLAY)
	return "\n".join(lines)


func _on_closed() -> void:
	is_open = false
	sound.save()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var b := button_rect()
	draw_style_box(_pill, b)
	_gear(b.get_center(), Color(1, 1, 1, 0.85))


func _gear(c: Vector2, col: Color) -> void:
	const TEETH := 8
	for k in TEETH:
		var a := TAU * k / TEETH
		var d := Vector2.from_angle(a)
		var s := d.orthogonal()
		draw_colored_polygon(PackedVector2Array([
			c + d * 10.0 + s * 4.5, c + d * 17.0 + s * 3.2, c + d * 17.0 - s * 3.2, c + d * 10.0 - s * 4.5,
		]), col)
	draw_arc(c, 9.5, 0.0, TAU, 32, col, 6.0, true)
