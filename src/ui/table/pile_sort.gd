class_name PileSort
extends RefCounted

# Returns a new array sorted by card type (Enums.CardType enum order), then
# case-insensitive name, then original index. The trailing index keeps the sort
# stable for equal keys (Godot's Array.sort_custom is not stable on its own).
# Does not mutate the input array.
static func sorted(cards: Array[CardInstance]) -> Array[CardInstance]:
	var indexed: Array = []
	for i in cards.size():
		indexed.append([cards[i], i])
	indexed.sort_custom(_before)
	var out: Array[CardInstance] = []
	for pair in indexed:
		out.append(pair[0])
	return out

static func _before(a: Array, b: Array) -> bool:
	var ca: CardInstance = a[0]
	var cb: CardInstance = b[0]
	if ca.definition.type != cb.definition.type:
		return ca.definition.type < cb.definition.type
	var na := ca.definition.name.to_lower()
	var nb := cb.definition.name.to_lower()
	if na != nb:
		return na < nb
	return a[1] < b[1]
