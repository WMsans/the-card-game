# src/ui/shell/game_settings.gd
class_name GameSettings
extends RefCounted

const SECTION := "display"
const DEFAULT_PATH := "user://settings.cfg"

var path: String
var fullscreen: bool = false
var vsync: bool = true

func _init(p: String = DEFAULT_PATH) -> void:
	path = p

func load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	fullscreen = cfg.get_value(SECTION, "fullscreen", fullscreen)
	vsync = cfg.get_value(SECTION, "vsync", vsync)

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "fullscreen", fullscreen)
	cfg.set_value(SECTION, "vsync", vsync)
	cfg.save(path)

func apply() -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
	var vmode := DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(vmode)
