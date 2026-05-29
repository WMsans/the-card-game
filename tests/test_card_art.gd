extends GdUnitTestSuite

func test_frame_path_per_type() -> void:
	assert_str(CardArt.frame_path(Enums.CardType.MINION)).is_equal("res://src/ui/assets/frames/minion.png")
	assert_str(CardArt.frame_path(Enums.CardType.LEADER)).is_equal("res://src/ui/assets/frames/leader.png")
	assert_str(CardArt.frame_path(Enums.CardType.SPELL)).is_equal("res://src/ui/assets/frames/spell.png")
	assert_str(CardArt.frame_path(Enums.CardType.TRAP)).is_equal("res://src/ui/assets/frames/trap.png")

func test_art_path_resolves_existing_file_by_basename() -> void:
	var def := CardDefinition.new()
	def.image = "docs/design_docs/Card List/images/strike_battle-bjorn.png"
	assert_str(CardArt.art_path(def)).is_equal("res://src/ui/assets/art/strike_battle-bjorn.png")

func test_art_path_empty_when_missing() -> void:
	var def := CardDefinition.new()
	def.image = "docs/design_docs/Card List/images/does-not-exist.png"
	assert_str(CardArt.art_path(def)).is_equal("")

func test_art_path_empty_when_no_image() -> void:
	var def := CardDefinition.new()
	def.image = ""
	assert_str(CardArt.art_path(def)).is_equal("")

func test_leader_art_path_resolves_deck_leader() -> void:
	assert_str(CardArt.leader_art_path("raccoon")).is_equal("res://src/ui/assets/art/raccoon_raccoon.png")

func test_leader_art_path_empty_for_unknown_deck() -> void:
	assert_str(CardArt.leader_art_path("")).is_equal("")
	assert_str(CardArt.leader_art_path("nope")).is_equal("")
