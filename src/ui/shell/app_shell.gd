# src/ui/shell/app_shell.gd
class_name AppShell
extends Control

const LANDING := preload("res://src/ui/shell/landing_panel.tscn")
const DECK_SELECT := preload("res://src/ui/shell/deck_select_panel.tscn")
const SETTINGS := preload("res://src/ui/shell/settings_panel.tscn")
const CREDITS := preload("res://src/ui/shell/credits_panel.tscn")
const COMPENDIUM := preload("res://src/ui/card/card_gallery.tscn")
const MATCH := preload("res://src/ui/match/match.tscn")

const DECK_PICK_TRAUMA := 0.8
const FADE_TIME := 0.2

@onready var _bg: BalatroBg = $BalatroBg
@onready var _content: Control = $ContentLayer

var _settings := GameSettings.new()

func _ready() -> void:
	theme = preload("res://src/ui/theme/game_theme.tres")
	_settings.load()
	_settings.apply()
	goto_landing()

# --- navigation -----------------------------------------------------------

func goto_landing() -> void:
	var p: LandingPanel = _mount(LANDING)
	p.play_pressed.connect(goto_deck_select)
	p.compendium_pressed.connect(goto_compendium)
	p.settings_pressed.connect(goto_settings)
	p.credits_pressed.connect(goto_credits)
	p.quit_pressed.connect(func() -> void: get_tree().quit())
	_bg.foreground_offset.connect(p.on_foreground_offset)

func goto_deck_select() -> void:
	var p: DeckSelectPanel = _mount(DECK_SELECT)
	p.back_pressed.connect(goto_landing)
	p.deck_changed.connect(func() -> void: _bg.add_trauma(DECK_PICK_TRAUMA))
	p.embark.connect(start_match)
	_bg.foreground_offset.connect(p.on_foreground_offset)

func goto_settings() -> void:
	var p: SettingsPanel = _mount(SETTINGS)
	p.bind(_settings)
	p.back_pressed.connect(goto_landing)
	_bg.foreground_offset.connect(p.on_foreground_offset)

func goto_credits() -> void:
	var p: CreditsPanel = _mount(CREDITS)
	p.back_pressed.connect(goto_landing)
	_bg.foreground_offset.connect(p.on_foreground_offset)

func goto_compendium() -> void:
	var gallery: CardGallery = _mount(COMPENDIUM)
	# CardGallery has no back button of its own; add one so the user can return.
	var back := Button.new()
	back.text = "Back"
	back.position = Vector2(40, 40)
	back.pressed.connect(goto_landing)
	gallery.add_child(back)
	JuicyButton.apply(back)
	_bg.foreground_offset.connect(gallery.on_foreground_offset)

func start_match(seed_value: int, my_deck: String, opp_deck: String) -> void:
	var m: Node = _mount(MATCH)
	m.attach_background(_bg)
	m.quit_to_menu.connect(goto_landing)
	m.start_game(seed_value, DeckSelectPanel.deck_path(my_deck), DeckSelectPanel.deck_path(opp_deck))

# --- internals ------------------------------------------------------------

# Frees the current panel and fades in the new one. Returns the new instance.
# Detaches synchronously (remove_child) before queue_free so the content layer
# holds exactly one child immediately — safe to call from a panel's own signal,
# since the freed panel is only detached (not destroyed) mid-emit.
func _mount(scene: PackedScene) -> Node:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	var inst: Node = scene.instantiate()
	_content.add_child(inst)
	if inst is CanvasItem:
		inst.modulate.a = 0.0
		create_tween().tween_property(inst, "modulate:a", 1.0, FADE_TIME)
	return inst
