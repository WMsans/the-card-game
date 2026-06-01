# tests/test_deck_select_panel.gd
extends GdUnitTestSuite

func _spawn() -> DeckSelectPanel:
	var p: DeckSelectPanel = load("res://src/ui/shell/deck_select_panel.tscn").instantiate()
	add_child(p)
	auto_free(p)
	return p

func test_deck_path_for_color() -> void:
	assert_str(DeckSelectPanel.deck_path("strike")).is_equal("res://src/data/decks/strike.csv")

func test_defaults_to_strike_vs_raccoon() -> void:
	var p := _spawn()
	assert_str(p.my_deck).is_equal("strike")
	assert_str(p.opp_deck).is_equal("raccoon")

func test_selecting_my_deck_updates_state_and_emits_change() -> void:
	var p := _spawn()
	var changed := [false]
	p.deck_changed.connect(func() -> void: changed[0] = true)
	p.select_my_deck("audio")
	assert_str(p.my_deck).is_equal("audio")
	assert_bool(changed[0]).is_true()

func test_showcase_shows_selected_leader_name() -> void:
	var p := _spawn()
	p.select_my_deck("raccoon")
	assert_str(p.get_node("%LeaderName").text).contains("Raccoon")

func test_blank_seed_is_randomized() -> void:
	var p := _spawn()
	p.get_node("%Seed").text = ""
	var v := p.seed_value()
	assert_int(v).is_greater_equal(0)

func test_explicit_seed_is_parsed() -> void:
	var p := _spawn()
	p.get_node("%Seed").text = "1234"
	assert_int(p.seed_value()).is_equal(1234)

func test_embark_emits_choices() -> void:
	var p := _spawn()
	p.select_my_deck("writing")
	p.select_opp_deck("audio")
	p.get_node("%Seed").text = "77"
	var got := [{}]
	p.embark.connect(func(seed: int, mine: String, opp: String) -> void:
		got[0] = {"seed": seed, "mine": mine, "opp": opp})
	p.get_node("%Embark").pressed.emit()
	assert_int(got[0]["seed"]).is_equal(77)
	assert_str(got[0]["mine"]).is_equal("writing")
	assert_str(got[0]["opp"]).is_equal("audio")

func test_back_emits_back_pressed() -> void:
	var p := _spawn()
	var fired := [false]
	p.back_pressed.connect(func() -> void: fired[0] = true)
	p.get_node("%Back").pressed.emit()
	assert_bool(fired[0]).is_true()
