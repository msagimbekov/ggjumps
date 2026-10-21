extends SceneTree
## CI (testflight.yml): adds Google's SDK (the AdMob plugin's local Swift package) to the exported
## Xcode project. The plugin does this itself with call_deferred at the end of an export, which
## never runs in a one-shot headless export, so the workflow calls the same patch directly:
##   godot --headless --script res://tools/ci/patch_xcodeproj.gd -- build/ios/ggjumps.xcodeproj/project.pbxproj

const PbxprojService := preload("res://addons/admob/internal/services/pbxproj_service.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("patch_xcodeproj: give the project.pbxproj path")
		quit(1)
		return
	PbxprojService.patch(args[0])
	quit()
