extends GdUnitTestSuite

const CARD_VIEW := "res://src/ui/card/card_view.tscn"

func _strike_defs() -> Array:
	return CardDatabase.load_deck("res://src/data/decks/strike.csv", "Strike")

func _make(def: CardDefinition) -> CardInstance:
	return CardInstance.new(1, def)

func _spawn() -> CardView:
	var cv: CardView = load(CARD_VIEW).instantiate()
	add_child(cv)
	auto_free(cv)
	return cv

func test_minion_renders_name_stats_and_frame() -> void:
	var def: CardDefinition = _strike_defs().filter(func(d): return d.type == Enums.CardType.MINION)[0]
	var cv := _spawn()
	cv.setup(_make(def))
	assert_str(cv.find_child("NameLabel").text).is_equal(def.name)
	assert_str(cv.find_child("DamageLabel").text).is_equal(str(def.base_damage))
	assert_str(cv.find_child("HealthLabel").text).is_equal(str(def.base_health))
	assert_str(cv.find_child("TicketLabel").text).is_equal(str(def.ticket_cost))
	assert_str((cv.find_child("Frame") as TextureRect).texture.resource_path).is_equal(CardArt.frame_path(Enums.CardType.MINION))

func test_spell_hides_unit_stats_and_discard() -> void:
	var def: CardDefinition = _strike_defs().filter(func(d): return d.type == Enums.CardType.SPELL)[0]
	var cv := _spawn()
	cv.setup(_make(def))
	assert_bool(cv.find_child("DamageLabel").visible).is_false()
	assert_bool(cv.find_child("HealthLabel").visible).is_false()
	assert_bool(cv.find_child("DiscardLabel").visible).is_false()

func test_leader_shows_discard_cost() -> void:
	var def: CardDefinition = _strike_defs().filter(func(d): return d.type == Enums.CardType.LEADER)[0]
	var cv := _spawn()
	cv.setup(_make(def))
	assert_bool(cv.find_child("DiscardLabel").visible).is_true()
	assert_str(cv.find_child("DiscardLabel").text).is_equal(str(def.alt_discard_cost))

func test_face_down_shows_back_and_hides_text() -> void:
	var def: CardDefinition = _strike_defs()[0]
	var cv := _spawn()
	cv.setup(_make(def))
	cv.set_face_down(true)
	assert_str((cv.find_child("Frame") as TextureRect).texture.resource_path).is_equal(CardArt.BACK)
	assert_bool(cv.find_child("NameLabel").visible).is_false()

func test_non_leader_shows_deck_leader_emblem() -> void:
	var defs := CardDatabase.load_deck("res://src/data/decks/raccoon.csv", "raccoon")
	var def: CardDefinition = defs.filter(func(d): return d.type == Enums.CardType.MINION)[0]
	var cv := _spawn()
	cv.setup(_make(def))
	var emblem := cv.find_child("LeaderEmblem") as TextureRect
	assert_bool(emblem.visible).is_true()
	assert_str(emblem.texture.resource_path).is_equal(CardArt.leader_art_path("raccoon"))

func test_leader_card_hides_emblem() -> void:
	var defs := CardDatabase.load_deck("res://src/data/decks/raccoon.csv", "raccoon")
	var def: CardDefinition = defs.filter(func(d): return d.type == Enums.CardType.LEADER)[0]
	var cv := _spawn()
	cv.setup(_make(def))
	assert_bool((cv.find_child("LeaderEmblem") as TextureRect).visible).is_false()

func test_damaged_health_tints_red() -> void:
	var def: CardDefinition = _strike_defs().filter(func(d): return d.type == Enums.CardType.MINION)[0]
	var inst := _make(def)
	inst.current_health = def.base_health - 1
	var cv := _spawn()
	cv.setup(inst)
	assert_object(cv.find_child("HealthLabel").modulate).is_equal(CardView.STAT_DAMAGED)
