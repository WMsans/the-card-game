# tests/test_trap_reveal_overlay.gd
extends GdUnitTestSuite

func _trap_inst() -> CardInstance:
	var defs := CardDatabase.load_deck("res://src/data/decks/strike.csv", "strike")
	var trap_def: CardDefinition = null
	for d in defs:
		if d.type == Enums.CardType.TRAP:
			trap_def = d
			break
	return CardInstance.new(1, trap_def)

func _spawn() -> Node:
	var p = load("res://src/ui/overlays/trap_reveal_overlay.tscn").instantiate()
	add_child(p)
	auto_free(p)
	return p

func test_interactive_reveal_emits_fire() -> void:
	var p := _spawn()
	var got := {"picked": -1}
	p.picked.connect(func(i): got["picked"] = i)
	p.show_reveal(_trap_inst(), "Your Deck will take 6 damage", ["Fire", "Decline"], true)
	p.press_option(0)
	assert_int(got["picked"]).is_equal(0)

func test_readonly_reveal_hides_buttons() -> void:
	var p := _spawn()
	p.show_reveal(_trap_inst(), "Opponent fired Rest", ["Fire", "Decline"], false)
	assert_bool(p.buttons_visible()).is_false()

func test_show_reveal_pops_panel_in() -> void:
	var o = load("res://src/ui/overlays/trap_reveal_overlay.tscn").instantiate()
	add_child(o)
	auto_free(o)
	var d := CardDefinition.new()
	d.type = Enums.CardType.TRAP
	d.name = "Snare"
	var inst := CardInstance.new(1, d)
	o.show_reveal(inst, "Trap!", [], false)
	var panel: Control = o.get_node("Center/Panel")
	# popup_in sets scale to 0.85 and tweens to 1.0 — verify it ran.
	await get_tree().create_timer(0.4).timeout
	assert_float(panel.scale.x).is_equal_approx(1.0, 0.02)
