class_name AudioTestBase
extends CardTestBase

func audio_def(id: int) -> CardDefinition:
	for d in CardDatabase.load_deck("res://src/data/decks/audio.csv", "audio"):
		if d.id == id:
			return d
	return null
