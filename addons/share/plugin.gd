@tool
extends EditorPlugin
## Adds cengiz-pz's Share plugin (v3.0, MIT, built for Godot 4.3) to Android exports: its
## library, its AndroidX dependency and the file provider it shares images through (files
## under the app's files dir, where user:// lives). The iOS half is the legacy plugin in
## res://ios/plugins (v2.0). The game talks to the native singleton itself (scripts/share.gd).

const NAME := "SharePlugin"
const VERSION := "3.0"
const PACKAGE := "org.godotengine.plugin.android.share"

var _export: AndroidExport


func _enter_tree() -> void:
	_export = AndroidExport.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null


class AndroidExport extends EditorExportPlugin:
	func _get_name() -> String:
		return NAME

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		var kind := "debug" if debug else "release"
		return PackedStringArray(["share/bin/%s/%s-%s-%s.aar" % [kind, NAME, VERSION, kind]])

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["androidx.appcompat:appcompat:1.7.0"])

	func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		return """
			<provider
				android:name="%s.ShareFileProvider"
				android:exported="false"
				android:authorities="%s.sharefileprovider"
				android:grantUriPermissions="true">
				<meta-data android:name="android.support.FILE_PROVIDER_PATHS" android:resource="@xml/file_provider_paths" />
			</provider>
			""" % [PACKAGE, get_option("package/unique_name")]
