extends SceneTree
## Prints what an OTA patch built from this project is made for: the platform-independent
## shape hash (Ota.shape()) and the app version (stored with the patch). Used by .github/workflows/ota.yml:
##   Godot --headless --path . --script res://scripts/dev/ota_shape.gd
## prints two lines, "shape <hash>" and "version <app version>".

func _initialize() -> void:
	var ota := load("res://scripts/ota.gd")
	print("shape ", ota.shape())
	print("version ", ProjectSettings.get_setting("application/config/version", ""))
	quit()
