extends "res://scripts/ui/modal.gd"
## Shown after the fireworks on the last island: the run time, and an offer to join the
## leaderboard with a name (at most 10 characters). `saved(id)` once the entry is stored,
## `skipped` when the player declines. Share (under the time) sends a picture of the finish
## (share_card.gd) through the system share sheet.

signal saved(id: String)
signal skipped

const LeaderboardApi := preload("res://scripts/leaderboard.gd")
const ShareCard := preload("res://scripts/ui/share_card.gd")
const Share := preload("res://scripts/share.gd")
const SHARE_ICON := preload("res://ui/icons/share.svg")

var _api: LeaderboardApi
var _ms := 0
var _name: LineEdit
var _save: Button
var _skip: Button
var _share: Button
var _status: Label


func _init(api: LeaderboardApi, ms: int) -> void:
	super("Congratulations!", 460.0, false)
	_api = api
	_ms = ms
	var line := Label.new()
	line.text = "You crossed all the islands in"
	content.add_child(line)
	var time := Label.new()
	time.text = LeaderboardApi.format_time(ms)
	time.theme_type_variation = "BigLabel"
	content.add_child(time)
	# The share mark and the label centred together (a Button's own icon sits at its edge).
	_share = Button.new()
	_share.theme_type_variation = "GhostButton"
	_share.custom_minimum_size.y = 52
	_share.pressed.connect(_on_share)
	content.add_child(_share)
	var inside := HBoxContainer.new()
	inside.alignment = BoxContainer.ALIGNMENT_CENTER
	inside.add_theme_constant_override("separation", 10)
	inside.mouse_filter = MOUSE_FILTER_IGNORE
	inside.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_share.add_child(inside)
	var mark := TextureRect.new()
	mark.texture = SHARE_ICON
	mark.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	mark.mouse_filter = MOUSE_FILTER_IGNORE
	inside.add_child(mark)
	var label := Label.new()
	label.text = "Share my time"
	label.add_theme_font_override("font", ui_theme().get_font("font", "Button"))
	label.mouse_filter = MOUSE_FILTER_IGNORE
	inside.add_child(label)
	var ask := Label.new()
	ask.text = "Add your name to the leaderboard?"
	ask.theme_type_variation = "MutedLabel"
	content.add_child(ask)
	_name = LineEdit.new()
	_name.placeholder_text = "Your name"
	_name.max_length = LeaderboardApi.NAME_MAX
	_name.text_changed.connect(func(_t): _refresh())
	_name.text_submitted.connect(func(_t): _on_save())
	content.add_child(_name)
	_status = Label.new()
	_status.theme_type_variation = "MutedLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	content.add_child(_status)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	content.add_child(buttons)
	_skip = Button.new()
	_skip.text = "No thanks"
	_skip.theme_type_variation = "GhostButton"
	_skip.size_flags_horizontal = SIZE_EXPAND_FILL
	_skip.pressed.connect(_on_skip)
	buttons.add_child(_skip)
	_save = Button.new()
	_save.text = "Save"
	_save.size_flags_horizontal = SIZE_EXPAND_FILL
	_save.pressed.connect(_on_save)
	buttons.add_child(_save)
	_refresh()


func _refresh() -> void:
	_save.disabled = LeaderboardApi.clean_name(_name.text) == ""


func _on_save() -> void:
	var player := LeaderboardApi.clean_name(_name.text)
	if player == "" or _save.disabled:
		return
	_save.disabled = true
	_skip.disabled = true
	_name.editable = false
	_status.visible = true
	_status.text = "Saving…"
	var id: String = await _api.submit(player, _ms)
	if not is_inside_tree():
		return
	if id == "":
		_status.text = "Couldn't save. Check your connection and try again."
		_skip.disabled = false
		_name.editable = true
		_refresh()
		return
	saved.emit(id)
	queue_free()


## The share sheet with the finish's picture and message (with the name, when one is typed);
## without one (desktop, or a build without the plugin) the message is copied instead.
func _on_share() -> void:
	_share.disabled = true
	var image: Image = await ShareCard.make_image(self, _ms, LeaderboardApi.clean_name(_name.text))
	if not is_inside_tree():
		return
	if not Share.share("99 jumps", ShareCard.text(_ms), image):
		_status.visible = true
		_status.text = "Message copied. The picture is saved in the game's data folder."
	_share.disabled = false


func _on_skip() -> void:
	skipped.emit()
	queue_free()
