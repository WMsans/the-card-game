extends GdUnitTestSuite

func test_gallery_populates_a_card_for_every_definition() -> void:
	var gallery: CardGallery = load("res://src/ui/card/card_gallery.tscn").instantiate()
	add_child(gallery)
	auto_free(gallery)
	var expected := 0
	for color in ["strike", "raccoon", "writing", "audio"]:
		expected += CardDatabase.load_deck("res://src/data/decks/%s.csv" % color, color).size()
	var grid: GridContainer = gallery.find_child("Grid") as GridContainer
	assert_int(grid.get_child_count()).is_equal(expected)
