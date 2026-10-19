extends SceneTree
## Headless level check: prints the worst jumps. Exit code 1 if any jump has no workable power.


func _init() -> void:
	var m: Node2D = load("res://scripts/main.gd").new()
	m._build_level()
	var rows: Array = m.verify_levels()
	var ice := 0
	for l in m.lands:
		if l.kind == Land.Kind.ICE:
			ice += 1
	print("lands=%d ice=%d" % [m.lands.size(), ice])
	for k in mini(8, rows.size()):
		print("jump %d (kind %d): window %d" % [rows[k][1], rows[k][2], rows[k][0]])
	quit(1 if rows[0][0] < 4 else 0)
