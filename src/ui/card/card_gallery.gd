class_name CardGallery
extends Control

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")
const DECKS := ["strike", "raccoon", "writing", "audio"]

@onready var _grid: GridContainer = $Scroll/Grid

func _ready() -> void:
	populate()

func populate() -> void:
	for color in DECKS:
		var defs := CardDatabase.load_deck("res://src/data/decks/%s.csv" % color, color)
		for def in defs:
			var cv: CardView = CARD_VIEW.instantiate()
			cv.custom_minimum_size = Vector2(350, 490)
			_grid.add_child(cv)
			cv.setup(CardInstance.new(0, def))
