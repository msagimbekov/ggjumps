extends SceneTree
## Headless level check: prints the worst jumps. Exit code 1 if any jump has no workable power.


func _init() -> void:
	var m: Node2D = load("res://scripts/main.gd").new()
	m._build_level()
	var rows: Array = m.verify_levels()
	var counts := [0, 0, 0, 0]
	for l in m.lands:
		counts[l.kind] += 1
	print("lands=%d grass/ice/treadmill/moving=%s" % [m.lands.size(), counts])
	var skips: Array = m.skip_violations()
	print("skippable islands: %s" % [skips])
	for k in mini(8, rows.size()):
		print("jump %d (kind %d): window %d" % [rows[k][1], rows[k][2], rows[k][0]])
	quit(1 if rows[0][0] < 3 or not skips.is_empty() else 0)
