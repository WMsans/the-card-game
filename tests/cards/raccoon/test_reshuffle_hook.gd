extends RaccoonTestBase

class ReturnerStub extends CardScript:
	func returns_on_reshuffle() -> bool: return true

func test_marked_card_returns_to_hand_on_reshuffle() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	ps.deck.clear()
	# one normal card in discard so reshuffle has something to shuffle
	var normal := eng.state.make_instance(TestFactory.minion(1, 1, 1, 800))
	normal.zone = Enums.Zone.DISCARD
	ps.discard.append(normal)
	var special := eng.state.make_instance(TestFactory.minion(1, 1, 1, 801))
	special.card_script = ReturnerStub.new()
	special.zone = Enums.Zone.DISCARD
	ps.discard.append(special)
	var ok := eng._reshuffle_or_lose(me)
	assert_bool(ok).is_true()
	assert_bool(ps.hand.has(special)).is_true()
	assert_bool(ps.deck.has(special)).is_false()
