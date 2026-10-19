extends Node
## Autoload, FIRST in the list: over-the-air patches. A patch is a Godot resource pack (.pck)
## of the whole game, exported for this platform, that replaces the built-in scripts, scenes and
## assets; it can change anything except the engine, native plugins, export settings and the
## set of script classes and autoloads (those need a store build).
##
## Versions: the app version (application/config/version) is only a label, bumped with every
## change; it never stops a patch. A patch carries the version it was made from, and a build
## takes it only when that isn't older than the build's own (so a newer store build never runs
## older code). `app_version()` is the version actually running, patch or not.
##
## Launch: `_init` runs before every other autoload and the main scene load, so loading the
## patch here makes everything after it come from the patch. This script itself can't be
## patched, so it is small, and it must never preload or name another game script (that would
## load the built-in copy before the patch).
##
## Updates: after the launch intro, `check_for_update` reads the manifest (GitHub Pages, the
## gh-pages branch, written by .github/workflows/ota.yml), downloads a newer patch made for this
## very build (same engine, same script classes and autoloads: `shape()`, and an app version not
## older than the build's),
## checks its SHA-256 and RSA signature, and keeps it for the NEXT launch. Never mid-game.
##
## Safety net: a patched launch counts as good once `confirm_boot` is called (main.gd, after the
## intro). If two patched launches in a row never get there, the patch is dropped for good and
## the game starts on the built-in version again.

const STORAGE := "https://msagimbekov.github.io/ggjumps/ota/"
const MANIFEST := "manifest.json"
const DIR := "user://ota/"
const STATE_PATH := "user://ota/state.json"
## A patched launch that hasn't reached the game this many times in a row is dropped.
const MAX_FAILED_BOOTS := 2
## Patches must be signed with the private half of this key (kept out of the repo: GitHub
## secret OTA_SIGNING_KEY), so even someone who could write to the Pages branch can't ship code.
const PUBLIC_KEY := """-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyWbikvbgM1A8mGacJxP/
oQhXJOp3QrjkrzlQlSffrD7S+3+fCAvS9dy9rpWE3iK8kciJH2IeA5P20ESkcSP3
+PI65i0r6ZUJcwofSIsIzZIXqB85rx5DnaJ3BYVRrPdDCRAXloxkz979phYyA0S6
PLr81zLxmiK29sgJ0Z+DQqHig7rPjtrAh/+cg4edK6P8JKj+9EYt53lpgWyBeAHZ
C5XMMpuo7Y5NYL0gWq+GDoMKPvYz92RNa98RxOz9VStNfo5F4Fxc8lmPD2FswCt+
HOXH0S3YCrIHQ/lVno2vhZyR1qdh5fMJ++cDfBhlawp1V7neRHHy1/9PgJ+9CnYk
hQIDAQAB
-----END PUBLIC KEY-----"""

## The patch running now (0: the built-in version).
var running := 0
## The app version the running patch was made from ("" without a patch).
var running_app := ""
## What the last update check did, for the debug toast: "", "up to date", "downloaded 12", ...
var last_check := ""
var _state := {}


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_state = _read_state()
	var version: int = _state.get("active", 0)
	if version <= 0:
		return
	var file := DIR + "patch-%d.pck" % version
	if _state.get("shape", "") != shape() or not FileAccess.file_exists(file):
		_drop(version, "made for another build")
		return
	if is_older(str(_state.get("app", "")), built_in_version()):
		_drop(version, "older than this build")
		return
	if _state.get("booting", false):
		# The last patched launch never reached the game.
		_state["failed_boots"] = int(_state.get("failed_boots", 0)) + 1
		if _state["failed_boots"] >= MAX_FAILED_BOOTS:
			_drop(version, "failed to start %d times" % MAX_FAILED_BOOTS)
			return
	if not ProjectSettings.load_resource_pack(file, true):
		_drop(version, "couldn't be loaded")
		return
	running = version
	running_app = str(_state.get("app", ""))
	_state["booting"] = true
	_write_state()


## The app version running now: the patch's, or the store build's without one.
func app_version() -> String:
	return running_app if running > 0 and running_app != "" else built_in_version()


## The store build's own app version (project.godot is read before any patch loads).
static func built_in_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


## Whether version `a` ("1.2.10") comes before `b`, comparing number by number. An empty `a`
## (a patch from before versions were recorded) counts as older than any version.
static func is_older(a: String, b: String) -> bool:
	if a == "":
		return b != ""
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := pa[i].to_int() if i < pa.size() else 0
		var y := pb[i].to_int() if i < pb.size() else 0
		if x != y:
			return x < y
	return false


## The game is up on this patch (or on the built-in version): the patch is good.
func confirm_boot() -> void:
	if running > 0 and _state.get("booting", false):
		_state["booting"] = false
		_state["failed_boots"] = 0
		_write_state()


## Looks for a newer patch for this build and, if there is one, downloads, checks and keeps it
## for the next launch. Quiet: any failure just means trying again next launch.
func check_for_update() -> void:
	var platform := OS.get_name()
	var manifest = await _get_json(_base() + MANIFEST + "?t=%d" % int(Time.get_unix_time_from_system()))
	if not manifest is Dictionary:
		last_check = "no manifest"
		return
	var best := {}
	for entry in manifest.get("patches", []):
		if not entry is Dictionary or entry.get("platform") != platform or entry.get("shape") != shape():
			continue
		if is_older(str(entry.get("app", "")), built_in_version()):
			continue
		var v := int(entry.get("version", 0))
		if v > _newest() and not v in _bad() and v > int(best.get("version", 0)):
			best = entry
	if best.is_empty():
		last_check = "up to date (%d)" % _newest()
		return
	var version := int(best["version"])
	DirAccess.make_dir_recursive_absolute(DIR)
	var download := DIR + "download.pck"
	if not await _download(_base() + str(best.get("file", "")), download):
		last_check = "download failed"
		return
	if not _verified(download, str(best.get("sha256", "")), str(best.get("signature", ""))):
		DirAccess.remove_absolute(download)
		_mark_bad(version)
		last_check = "rejected %d (bad checksum or signature)" % version
		return
	var keep := DIR + "patch-%d.pck" % version
	DirAccess.rename_absolute(download, keep)
	# From the next launch on; the patch running now stays until then.
	var old := int(_state.get("active", 0))
	_state["active"] = version
	_state["shape"] = shape()
	_state["app"] = str(best.get("app", ""))
	_state["booting"] = false
	_state["failed_boots"] = 0
	_write_state()
	for name in DirAccess.get_files_at(DIR):
		if name.begins_with("patch-") and name != keep.get_file() and name != "patch-%d.pck" % running:
			DirAccess.remove_absolute(DIR + name)
	last_check = "downloaded %d (was %d), applies on the next launch" % [version, old]


## What a patch must have been made for: this engine, and exactly these script classes and
## autoloads (patches can't add or move them). Not the app version: that only has to be no older
## (`is_older`). The OTA workflow computes the same with scripts/dev/ota_shape.gd.
static func shape() -> String:
	var lines := PackedStringArray()
	lines.append("engine " + Engine.get_version_info()["string"])
	var classes := PackedStringArray()
	for info in ProjectSettings.get_global_class_list():
		classes.append("class %s %s" % [info["class"], info["path"]])
	classes.sort()
	lines.append_array(classes)
	var autoloads := PackedStringArray()
	for property in ProjectSettings.get_property_list():
		var key: String = property["name"]
		if key.begins_with("autoload/"):
			autoloads.append("%s %s" % [key, ProjectSettings.get_setting(key)])
	autoloads.sort()
	lines.append_array(autoloads)
	return "\n".join(lines).sha256_text()


func _verified(path: String, sha256: String, signature_b64: String) -> bool:
	if sha256 == "" or FileAccess.get_sha256(path) != sha256:
		return false
	var key := CryptoKey.new()
	if key.load_from_string(PUBLIC_KEY, true) != OK:
		return false
	return Crypto.new().verify(HashingContext.HASH_SHA256, sha256.hex_decode(), Marshalls.base64_to_raw(signature_b64), key)


## The manifest's address; `-- --ota-url=http://...` points it elsewhere (local tests).
func _base() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ota-url="):
			return arg.trim_prefix("--ota-url=").trim_suffix("/") + "/"
	return STORAGE


func _newest() -> int:
	return maxi(running, int(_state.get("active", 0)))


func _bad() -> Array:
	return _state.get("bad", [])


func _mark_bad(version: int) -> void:
	var bad := _bad()
	if not version in bad:
		bad.append(version)
	_state["bad"] = bad
	_write_state()


## Gives up on `version`: back to the built-in version, and never that patch again.
func _drop(version: int, why: String) -> void:
	push_warning("OTA: dropping patch %d: %s" % [version, why])
	_mark_bad(version)
	DirAccess.remove_absolute(DIR + "patch-%d.pck" % version)
	_state["active"] = 0
	_state["booting"] = false
	_state["failed_boots"] = 0
	_write_state()


func _get_json(url: String) -> Variant:
	var http := HTTPRequest.new()
	http.use_threads = true  # keeps going even if the main thread stalls (a native SDK)
	http.timeout = 15.0
	add_child(http)
	if http.request(url) != OK:
		http.queue_free()
		return null
	var result: Array = await http.request_completed
	http.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		return null
	return JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())


func _download(url: String, path: String) -> bool:
	var http := HTTPRequest.new()
	http.use_threads = true
	http.timeout = 120.0
	http.download_file = path
	add_child(http)
	if http.request(url) != OK:
		http.queue_free()
		return false
	var result: Array = await http.request_completed
	http.queue_free()
	return result[0] == HTTPRequest.RESULT_SUCCESS and result[1] == 200


func _read_state() -> Dictionary:
	if not FileAccess.file_exists(STATE_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(STATE_PATH))
	if not parsed is Dictionary:
		return {}
	for key in parsed:
		if parsed[key] is float:
			parsed[key] = int(parsed[key])
	parsed["bad"] = (parsed.get("bad", []) as Array).map(func(v): return int(v))
	return parsed


func _write_state() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var file := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_state))
