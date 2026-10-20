class_name Sound
extends Node
## Background music and sound effects on their own buses, with volumes saved between runs.
## The audio files are made by tools/gen_audio.py.

const SETTINGS := "user://settings.cfg"
const SFX := {
	"splash": preload("res://audio/splash.wav"),
	"land": preload("res://audio/land.wav"),
	"land_ice": preload("res://audio/land_ice.wav"),
	"life": preload("res://audio/life.wav"),
	"drop": preload("res://audio/drop.wav"),
	"radar_on": preload("res://audio/radar_on.wav"),
	"radar_ping": preload("res://audio/radar_ping.wav"),
	"fw_launch": preload("res://audio/fw_launch.wav"),
	"fw_burst": preload("res://audio/fw_burst.wav"),
	"win": preload("res://audio/win.wav"),
}
const VOICES := 10  # effects that can overlap (fireworks need a few)

## Volumes 0..1; muting sets 0 and remembers the level to go back to.
var music_volume := 0.6
var sfx_volume := 0.8
var _music_prev := 0.6
var _sfx_prev := 0.8

var _music: AudioStreamPlayer
var _voices: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for bus in ["Music", "Sfx"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
	_load()
	_music = AudioStreamPlayer.new()
	var stream: AudioStreamOggVorbis = load("res://audio/music.ogg")
	stream.loop = true
	_music.stream = stream
	_music.bus = "Music"
	add_child(_music)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Sfx"
		add_child(p)
		_voices.append(p)
	_apply()
	_music.play()


func play(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	var p := _voices[_next]
	_next = (_next + 1) % VOICES
	p.stream = SFX[name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func set_music(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	if music_volume > 0.0:
		_music_prev = music_volume
	_apply()


func set_sfx(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	if sfx_volume > 0.0:
		_sfx_prev = sfx_volume
	_apply()


## Icon tap: silence, or back to the volume it had before.
func toggle_music() -> void:
	set_music(_music_prev if music_volume == 0.0 else 0.0)


func toggle_sfx() -> void:
	set_sfx(_sfx_prev if sfx_volume == 0.0 else 0.0)


## Writes the volumes to disk (called when the settings panel closes or a slider is let go).
func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "music_prev", _music_prev)
	cfg.set_value("audio", "sfx_prev", _sfx_prev)
	cfg.save(SETTINGS)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) != OK:
		return
	music_volume = cfg.get_value("audio", "music", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	_music_prev = cfg.get_value("audio", "music_prev", _music_prev)
	_sfx_prev = cfg.get_value("audio", "sfx_prev", _sfx_prev)


func _apply() -> void:
	for pair in [["Music", music_volume], ["Sfx", sfx_volume]]:
		var bus := AudioServer.get_bus_index(pair[0])
		var v: float = pair[1]
		AudioServer.set_bus_mute(bus, v <= 0.0)
		# Squared so the slider feels even to the ear.
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(v * v, 0.0001)))
