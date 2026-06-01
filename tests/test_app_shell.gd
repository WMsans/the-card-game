# tests/test_app_shell.gd
extends GdUnitTestSuite

func _spawn() -> AppShell:
	# add_child runs _ready synchronously, which mounts the landing panel
	var s: AppShell = load("res://src/ui/shell/app_shell.tscn").instantiate()
	add_child(s)
	auto_free(s)
	return s

func _content_child(s: AppShell) -> Node:
	var content: Node = s.get_node("ContentLayer")
	assert_int(content.get_child_count()).is_equal(1)
	return content.get_child(0)

func test_starts_on_landing_panel() -> void:
	var s := _spawn()
	assert_object(_content_child(s)).is_instanceof(LandingPanel)

func test_play_navigates_to_deck_select() -> void:
	var s := _spawn()
	(_content_child(s) as LandingPanel).play_pressed.emit()
	assert_object(_content_child(s)).is_instanceof(DeckSelectPanel)

func test_settings_navigates_to_settings_panel() -> void:
	var s := _spawn()
	(_content_child(s) as LandingPanel).settings_pressed.emit()
	assert_object(_content_child(s)).is_instanceof(SettingsPanel)

func test_compendium_navigates_to_card_gallery() -> void:
	var s := _spawn()
	(_content_child(s) as LandingPanel).compendium_pressed.emit()
	assert_object(_content_child(s)).is_instanceof(CardGallery)

func test_embark_mounts_match_with_injected_background() -> void:
	var s := _spawn()
	s.start_match(99, "strike", "raccoon")
	var m: Node = _content_child(s)
	assert_str(m.name).is_equal("Match")
	# Background is the shell's single BalatroBg, injected into the match.
	assert_object(m._bg).is_same(s.get_node("BalatroBg"))

func test_deck_change_adds_trauma_to_background() -> void:
	var s := _spawn()
	(_content_child(s) as LandingPanel).play_pressed.emit()
	var ds: DeckSelectPanel = _content_child(s) as DeckSelectPanel
	ds.select_my_deck("audio")
	assert_float((s.get_node("BalatroBg") as BalatroBg).get_trauma()).is_greater(0.0)
