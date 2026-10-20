extends Node
## Leaderboard client: everyone who made it across all the islands, with their run time.
##
## Uses the Supabase table `ggjumps_leaderboard` (in the ggcuts project; schema and access
## rules in supabase/leaderboard.sql) through Supabase's REST API with the project's
## publishable key. That key is meant to ship in apps: row-level security lets it only read the
## list and add entries, never change or delete them. Never put a secret key, the service-role
## key or the database password in the app.

const SUPABASE_URL := "https://mrwwnbyctgiauejgshrm.supabase.co"
const SUPABASE_KEY := "sb_publishable_8jNg7go88CAeeQl9UNeQBg_FCNWZHFg"
const TABLE := "ggjumps_leaderboard"
const TIMEOUT := 10.0
const LIST_LIMIT := 200
## Ids of the entries this device submitted, to highlight "you" in the list.
const MINE_PATH := "user://leaderboard_mine.json"
## Same as the database check (supabase/leaderboard.sql).
const NAME_MAX := 10


## Entries fastest first (on a tie, who finished first): [{"id", "name", "ms", "finished"
## (unix time), "mine"}], or null if the list couldn't be loaded.
func fetch() -> Variant:
	var response = await _request(HTTPClient.METHOD_GET,
		"?select=id,name,time_ms,finished_at&order=time_ms.asc,finished_at.asc&limit=%d" % LIST_LIMIT, "")
	if not response is Array:
		return null
	var mine := _mine()
	var out := []
	for entry in response:
		if entry is Dictionary and entry.has("name") and entry.has("time_ms"):
			out.append({
				"id": str(entry.get("id", "")),
				"name": str(entry["name"]),
				"ms": int(entry["time_ms"]),
				"finished": _unix(entry.get("finished_at")),
				"mine": str(entry.get("id", "")) in mine,
			})
	return out


## Adds a finished run. Returns the new entry's id, or "" if it couldn't be saved.
func submit(player_name: String, ms: int) -> String:
	var body := JSON.stringify({"name": clean_name(player_name), "time_ms": ms})
	var response = await _request(HTTPClient.METHOD_POST, "", body)
	if not (response is Array and response.size() == 1 and response[0] is Dictionary):
		return ""
	var id := str(response[0].get("id", ""))
	var mine := _mine()
	mine.append(id)
	var file := FileAccess.open(MINE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(mine))
	return id


## A name as stored: trimmed, inner whitespace collapsed, at most NAME_MAX characters.
static func clean_name(text: String) -> String:
	var words := text.strip_edges().split(" ", false)
	return " ".join(words).substr(0, NAME_MAX).strip_edges()


## "4:07.3" under an hour, "1h 02m" from there.
static func format_time(ms: int) -> String:
	var s := ms / 1000
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s / 60) % 60]
	return "%d:%02d.%d" % [s / 60, s % 60, (ms % 1000) / 100]


## A finish date in the player's own time zone, day first: "21.10.26".
static func format_date(unix: int) -> String:
	if unix <= 0:
		return ""
	var local := Time.get_datetime_dict_from_unix_time(unix + Time.get_time_zone_from_system()["bias"] * 60)
	return "%02d.%02d.%02d" % [local["day"], local["month"], local["year"] % 100]


## The database gives an ISO date in UTC ("2026-10-21T15:23:45.123+00:00").
static func _unix(value: Variant) -> int:
	if value is String and value.length() >= 19:
		return Time.get_unix_time_from_datetime_string(value.substr(0, 19))
	return 0


func _mine() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MINE_PATH)) if FileAccess.file_exists(MINE_PATH) else null
	return parsed if parsed is Array else []


## One REST call to the table; returns the parsed JSON body, or null on any failure.
func _request(method: HTTPClient.Method, query: String, body: String) -> Variant:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	var headers := PackedStringArray([
		"apikey: " + SUPABASE_KEY,
		"Content-Type: application/json",
		"Prefer: return=representation",
	])
	var url := "%s/rest/v1/%s%s" % [SUPABASE_URL, TABLE, query]
	if http.request(url, headers, method, body) != OK:
		http.queue_free()
		return null
	var result: Array = await http.request_completed
	http.queue_free()
	var code: int = result[1]
	if result[0] != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		push_warning("Leaderboard: request failed (result %d, HTTP %d)" % [result[0], code])
		return null
	return JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
