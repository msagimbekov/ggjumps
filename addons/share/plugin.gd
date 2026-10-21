@tool
extends EditorPlugin
## Packs the Share plugin (v5.0, MIT, built for Godot 4.5;
## https://github.com/godot-sdk-integrations/godot-share) into the exports:
## - Android: its library, its AndroidX dependency and the file provider it shares images
##   through (files under the app's files dir, where user:// lives);
## - iOS: the frameworks and linker flag its library needs (the library itself is the plugin in
##   res://ios/plugins, enabled in the iOS export preset).
## Only the native parts are used: the game talks to the singleton itself (scripts/share.gd),
## without the upstream Share / SharedData scripts, whose class_names would change the OTA shape.

const NAME := "SharePlugin"
const PACKAGE := "org.godotengine.plugin.android.share"
const IOS_FRAMEWORKS := ["Foundation.framework", "UIKit.framework"]
const IOS_LINKER_FLAGS := ["-ObjC"]

var _android: AndroidExport
var _ios: IosExport


func _enter_tree() -> void:
	_android = AndroidExport.new()
	add_export_plugin(_android)
	_ios = IosExport.new()
	add_export_plugin(_ios)


func _exit_tree() -> void:
	remove_export_plugin(_android)
	remove_export_plugin(_ios)
	_android = null
	_ios = null


class AndroidExport extends EditorExportPlugin:
	func _get_name() -> String:
		return NAME

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		var kind := "debug" if debug else "release"
		return PackedStringArray(["share/bin/%s/%s-%s.aar" % [kind, NAME, kind]])

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["androidx.appcompat:appcompat:1.7.1"])

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


class IosExport extends EditorExportPlugin:
	func _get_name() -> String:
		return NAME

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformIOS

	func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		for framework in IOS_FRAMEWORKS:
			add_ios_framework(framework)
		for flag in IOS_LINKER_FLAGS:
			add_ios_linker_flags(flag)
