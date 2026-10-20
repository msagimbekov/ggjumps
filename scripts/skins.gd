extends RefCounted
## Bubble colours the player can pick in Settings. The player's bubble, its jump wake, the
## lives icons and the life drops all use the current one. Saved in user://settings.cfg.
## Preloaded by path (no class_name: that would change the OTA build shape).

const SETTINGS := "user://settings.cfg"
## body: the liquid; core: the lighter inside; rim: the outline; glow: wake and reflection.
const SKINS := [
	{"name": "Lagoon", "body": Color(0.30, 0.80, 1.0), "core": Color(0.62, 0.95, 1.0), "rim": Color(0.10, 0.50, 0.80), "glow": Color(0.55, 0.90, 1.0)},
	{"name": "Seafoam", "body": Color(0.38, 0.86, 0.66), "core": Color(0.72, 0.98, 0.86), "rim": Color(0.12, 0.52, 0.40), "glow": Color(0.62, 0.95, 0.80)},
	{"name": "Coral", "body": Color(1.0, 0.60, 0.50), "core": Color(1.0, 0.84, 0.76), "rim": Color(0.76, 0.32, 0.28), "glow": Color(1.0, 0.78, 0.70)},
]

static var current := 0
static var _loaded := false


static func pick(i: int) -> void:
	current = clampi(i, 0, SKINS.size() - 1)
	_loaded = true
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)  # keep the other settings in the file
	cfg.set_value("look", "skin", current)
	cfg.save(SETTINGS)


static func color(part: String, skin := -1) -> Color:
	if not _loaded:
		_loaded = true
		var cfg := ConfigFile.new()
		if cfg.load(SETTINGS) == OK:
			current = clampi(int(cfg.get_value("look", "skin", 0)), 0, SKINS.size() - 1)
	return SKINS[current if skin < 0 else skin][part]
