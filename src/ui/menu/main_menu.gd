class_name MainMenu
extends Control

const COLORS := ["strike", "raccoon", "writing", "audio"]
const OPPONENT := "raccoon"

var chosen_deck: String = "strike"

@onready var _seed_field: LineEdit = $SeedField
@onready var _play: Button = $PlayButton

func _ready() -> void:
	_play.pressed.connect(_on_play)
	$QuitButton.pressed.connect(func(): get_tree().quit())
	for c in COLORS:
		var btn: Button = $DeckButtons.get_node(c.capitalize())
		btn.pressed.connect(select_deck.bind(c))
	theme = preload("res://src/ui/theme/game_theme.tres")
	JuicyButton.apply(_play)
	JuicyButton.apply($QuitButton)
	for c in COLORS:
		JuicyButton.apply($DeckButtons.get_node(c.capitalize()))
	_refresh_deck_selection()

static func deck_path(color: String) -> String:
	return "res://src/data/decks/%s.csv" % color

func select_deck(color: String) -> void:
	chosen_deck = color
	_refresh_deck_selection()

func _refresh_deck_selection() -> void:
	for c in COLORS:
		var btn: Button = $DeckButtons.get_node(c.capitalize())
		btn.modulate = UiPalette.ACCENT if c == chosen_deck else Color.WHITE

func _seed_value() -> int:
	var txt := _seed_field.text.strip_edges()
	return int(txt) if txt.is_valid_int() else randi()

func _on_play() -> void:
	var match_scene: Node = load("res://src/ui/match/match.tscn").instantiate()
	get_tree().root.add_child(match_scene)
	match_scene.start_game(_seed_value(), deck_path(chosen_deck), deck_path(OPPONENT))
	queue_free()