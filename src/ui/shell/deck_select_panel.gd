# src/ui/shell/deck_select_panel.gd
class_name DeckSelectPanel
extends Control

signal back_pressed
signal embark(seed_value: int, my_deck: String, opp_deck: String)
signal deck_changed  # shell connects this to BalatroBg.add_trauma for the pick shake

const COLORS := ["strike", "raccoon", "writing", "audio"]

var my_deck: String = "strike"
var opp_deck: String = "raccoon"

var _my_buttons := {}
var _opp_buttons := {}

func _ready() -> void:
	theme = preload("res://src/ui/theme/game_theme.tres")
	for c in COLORS:
		_my_buttons[c] = _make_deck_button(%MyDeckRow, c, select_my_deck)
		_opp_buttons[c] = _make_deck_button(%OppRow, c, select_opp_deck)
	%Back.pressed.connect(func() -> void: back_pressed.emit())
	%Embark.pressed.connect(_on_embark)
	JuicyButton.apply(%Back)
	JuicyButton.apply(%Embark)
	_refresh()

static func deck_path(color: String) -> String:
	return "res://src/data/decks/%s.csv" % color

func _make_deck_button(row: VBoxContainer, color: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = color.capitalize()
	b.pressed.connect(cb.bind(color))
	row.add_child(b)
	JuicyButton.apply(b)
	return b

func select_my_deck(color: String) -> void:
	my_deck = color
	deck_changed.emit()
	_refresh()

func select_opp_deck(color: String) -> void:
	opp_deck = color
	deck_changed.emit()
	_refresh()

func _refresh() -> void:
	for c in COLORS:
		_my_buttons[c].modulate = UiPalette.ACCENT if c == my_deck else Color.WHITE
		_opp_buttons[c].modulate = UiPalette.ACCENT if c == opp_deck else Color.WHITE
	_refresh_showcase()

func _refresh_showcase() -> void:
	var art_path := CardArt.leader_art_path(my_deck)
	%LeaderArt.texture = load(art_path) if art_path != "" else null
	var leader := _leader_def(my_deck)
	%LeaderName.text = leader.name if leader != null else my_deck.capitalize()
	%LeaderText.text = leader.ability_text if leader != null else ""

func _leader_def(color: String) -> CardDefinition:
	for d in CardDatabase.load_deck(deck_path(color), color):
		if d.type == Enums.CardType.LEADER:
			return d
	return null

func seed_value() -> int:
	var txt: String = %Seed.text.strip_edges()
	return int(txt) if txt.is_valid_int() else randi()

func on_foreground_offset(offset: Vector2) -> void:
	position = offset

func _on_embark() -> void:
	embark.emit(seed_value(), my_deck, opp_deck)
