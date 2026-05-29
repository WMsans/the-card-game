class_name CardDatabase
extends RefCounted

const KNOWN_KEYWORDS := [
	"REQUEST", "RUMMAGE", "TRASH", "ORANGE", "HARMONIZE", "CLEF",
	"TAUNT", "BOMB", "DETONATE", "DEFUSE", "CYCLE", "MILL",
	"SCRAPPED", "EMPOWERED", "OVERCHARGE", "RECYCLE", "HARMONIZED", "REMOVED",
]

static func load_deck(path: String, deck_color: String) -> Array[CardDefinition]:
	var defs: Array[CardDefinition] = []
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "Could not open %s" % path)
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 9:
			continue
		if row[1].strip_edges() == "":
			continue
		defs.append(_parse_row(row, deck_color))
	f.close()
	return defs

static func _parse_row(row: PackedStringArray, deck_color: String) -> CardDefinition:
	var d := CardDefinition.new()
	d.deck_color = deck_color
	d.id = int(row[0].strip_edges())
	d.type = _parse_type(row[1])
	d.name = row[2].strip_edges()
	var cost := _parse_cost(row[3])
	d.ticket_cost = cost[0]
	d.alt_discard_cost = cost[1]
	d.base_damage = _parse_leading_int(row[4])
	d.base_health = _parse_leading_int(row[5])
	d.ability_text = row[6].strip_edges()
	d.flavor = row[7].strip_edges()
	d.image = row[8].strip_edges() if row.size() > 8 else ""
	d.keywords = _extract_keywords(d.ability_text)
	return d

static func _parse_type(s: String) -> int:
	match s.strip_edges().to_lower():
		"minion": return Enums.CardType.MINION
		"spell": return Enums.CardType.SPELL
		"trap": return Enums.CardType.TRAP
		"leader": return Enums.CardType.LEADER
		_: return Enums.CardType.MINION

static func _parse_cost(s: String) -> Array:
	var parts := s.split("/")
	var ticket := _parse_leading_int(parts[0])
	var discard := 0
	if parts.size() > 1:
		discard = _parse_leading_int(parts[1])
	return [ticket, discard]

static func _parse_leading_int(s: String) -> int:
	var re := RegEx.new()
	re.compile("-?\\d+")
	var m := re.search(s)
	return int(m.get_string()) if m != null else 0

static func _extract_keywords(text: String) -> Array[String]:
	var found: Array[String] = []
	var upper := text.to_upper()
	for kw in KNOWN_KEYWORDS:
		if upper.contains(kw) and not found.has(kw):
			found.append(kw)
	return found
