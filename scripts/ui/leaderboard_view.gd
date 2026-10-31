extends "res://scripts/ui/modal.gd"
## The leaderboard window: everyone who made it across all the islands, fastest first, with their
## time and date. Entries from this device have a mint name and a tint; `highlight` (a just-saved entry) is
## scrolled into view. Every other entry has a "…" button to report its name: the entry disappears
## from this device at once and from everyone's list after a few reports (supabase/leaderboard.sql).

const LeaderboardApi := preload("res://scripts/leaderboard.gd")

var _api: LeaderboardApi
var _highlight := ""
var _status: Label
var _note: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _retry: Button


func _init(api: LeaderboardApi, highlight := "") -> void:
	super("Leaderboard", 500.0)
	_api = api
	_highlight = highlight
	var sub := Label.new()
	sub.text = "Everyone who made it across all the islands"
	sub.theme_type_variation = "MutedLabel"
	content.add_child(sub)
	_note = Label.new()
	_note.theme_type_variation = "MutedLabel"
	_note.add_theme_color_override("font_color", MINT)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(380, 0)
	_note.visible = false
	content.add_child(_note)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 470)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(380, 0)
	_status.theme_type_variation = "MutedLabel"
	_list.add_child(_status)
	_retry = Button.new()
	_retry.text = "Try again"
	_retry.theme_type_variation = "GhostButton"
	_retry.size_flags_horizontal = SIZE_SHRINK_CENTER
	_retry.pressed.connect(_load)
	_retry.visible = false
	_list.add_child(_retry)


func _ready() -> void:
	_load()


func _load() -> void:
	_retry.visible = false
	_status.visible = true
	_status.text = "Loading…"
	for c in _list.get_children():
		if c != _status and c != _retry:
			c.queue_free()
	var entries = await _api.fetch()
	if not is_inside_tree():
		return
	if entries == null:
		_status.text = "Couldn't load the leaderboard.\nCheck your connection."
		_retry.visible = true
		return
	if entries.is_empty():
		_status.text = "Nobody has made it across yet.\nBe the first!"
		return
	_status.visible = false
	var target: Control
	for i in entries.size():
		var row := _row(i + 1, entries[i])
		_list.add_child(row)
		if entries[i]["id"] == _highlight:
			target = row
	if target:
		await get_tree().process_frame
		_scroll.ensure_control_visible(target)


func _row(rank: int, e: Dictionary) -> Control:
	var box := PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.set_corner_radius_all(14)
	bg.content_margin_left = 14
	bg.content_margin_right = 14
	bg.content_margin_top = 8
	bg.content_margin_bottom = 8
	if e["id"] == _highlight:
		bg.bg_color = Color(MINT.r, MINT.g, MINT.b, 0.30)
	elif e["mine"]:
		bg.bg_color = Color(MINT.r, MINT.g, MINT.b, 0.14)
	else:
		bg.bg_color = Color(1, 1, 1, 0.05 if rank % 2 else 0.0)
	box.add_theme_stylebox_override("panel", bg)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	box.add_child(h)
	var medal := [Color(1.0, 0.82, 0.25), Color(0.80, 0.85, 0.90), Color(0.85, 0.55, 0.30)]
	h.add_child(_cell(str(rank), 38, HORIZONTAL_ALIGNMENT_LEFT, medal[rank - 1] if rank <= 3 else Color(1, 1, 1, 0.6)))
	var who := _cell(e["name"], 0, HORIZONTAL_ALIGNMENT_LEFT, MINT if e["mine"] else Color.WHITE)
	who.size_flags_horizontal = SIZE_EXPAND_FILL
	who.clip_text = true
	h.add_child(who)
	h.add_child(_cell(LeaderboardApi.format_time(e["ms"]), 104, HORIZONTAL_ALIGNMENT_RIGHT, MINT))
	var date := _cell(LeaderboardApi.format_date(e["finished"]), 84, HORIZONTAL_ALIGNMENT_RIGHT, Color(1, 1, 1, 0.55))
	date.add_theme_font_size_override("font_size", 18)
	h.add_child(date)
	if e["mine"]:
		var gap := Control.new()
		gap.custom_minimum_size.x = 34
		h.add_child(gap)
	else:
		var more := Button.new()
		more.text = "…"
		more.theme_type_variation = "CloseButton"
		more.custom_minimum_size = Vector2(34, 34)
		more.add_theme_font_size_override("font_size", 22)
		more.size_flags_vertical = SIZE_SHRINK_CENTER
		more.pressed.connect(_ask_report.bind(box, h, e))
		h.add_child(more)
	return box


## Swaps a row's cells for "Report <name>?" with Cancel and Report.
func _ask_report(box: PanelContainer, cells: HBoxContainer, e: Dictionary) -> void:
	cells.visible = false
	var ask := HBoxContainer.new()
	ask.add_theme_constant_override("separation", 8)
	box.add_child(ask)
	var q := _cell("Report “%s”?" % e["name"], 0, HORIZONTAL_ALIGNMENT_LEFT, Color.WHITE)
	q.size_flags_horizontal = SIZE_EXPAND_FILL
	q.clip_text = true
	ask.add_child(q)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.theme_type_variation = "GhostButton"
	cancel.add_theme_font_size_override("font_size", 20)
	cancel.pressed.connect(func():
		ask.queue_free()
		cells.visible = true)
	ask.add_child(cancel)
	var report := Button.new()
	report.text = "Report"
	report.add_theme_font_size_override("font_size", 20)
	report.pressed.connect(func():
		cancel.disabled = true
		report.disabled = true
		var sent: bool = await _api.report(e["id"])
		if not is_inside_tree():
			return
		box.queue_free()
		_note.text = ("Thanks. That name is hidden now, and we will review it." if sent
			else "That name is hidden on this device.")
		_note.visible = true)
	ask.add_child(report)


func _cell(text: String, width: float, align: HorizontalAlignment, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = width
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", 22)
	return l
