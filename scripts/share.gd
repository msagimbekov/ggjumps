extends RefCounted
## The system share sheet: text plus an image, through the Share plugin's native singleton
## (v5.0; iOS: res://ios/plugins, Android: addons/share). Without it (desktop, or a build without the
## plugin that an OTA patch reached) the text goes to the clipboard and the image is saved to
## user:// instead. No class_name, so the OTA shape doesn't change.

const SINGLETON := "SharePlugin"
## In the app's files dir (user://): the only place the Android file provider shares from.
const IMAGE_FILE := "share_card.png"


static func available() -> bool:
	return Engine.has_singleton(SINGLETON)


## Opens the share sheet; returns false when there was none and the text was copied instead.
static func share(title: String, text: String, image: Image = null) -> bool:
	var data := {"title": title, "subject": title, "content": text, "mime_type": "text/plain"}
	if image != null:
		var path := image_path()
		if image.save_png(path) == OK:
			data["file_path"] = path
			data["mime_type"] = "image/*"
	if available():
		Engine.get_singleton(SINGLETON).share(data)
		return true
	DisplayServer.clipboard_set(text)
	return false


static func image_path() -> String:
	return OS.get_user_data_dir().path_join(IMAGE_FILE)
