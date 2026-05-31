extends GdUnitTestSuite

const OVERLAY := "res://src/ui/table/pile_overlay.tscn"

func _inst(id: int, type: int, name: String) -> CardInstance:
	var d := CardDefinition.new()
	d.type = type
	d.name = name
	return CardInstance.new(id, d)

func _cards(n: int) -> Array[CardInstance]:
	var arr: Array[CardInstance] = []
	for i in n:
		arr.append(_inst(i + 1, Enums.CardType.MINION, "C%d" % i))
	return arr

func _run(n: int, label: String) -> void:
	var o: PileOverlay = load(OVERLAY).instantiate()
	add_child(o)
	auto_free(o)
	o.size = Vector2(1920, 1080)
	await get_tree().process_frame
	o.open(_cards(n), Vector2(1735, 635), "Pile")
	# sample first card position across several frames
	var grid: GridContainer = o.find_child("Grid") as GridContainer
	for f in 12:
		await get_tree().process_frame
		if grid.get_child_count() > 0:
			var cv = grid.get_child(0)
			prints(label, "frame", f, "pos0=", cv.position, "rest0=", cv._rest_position)
	o.close()
	await get_tree().process_frame

func test_diag() -> void:
	await _run(3, "FEW(3)")
	await _run(40, "MANY(40)")
	assert_bool(true).is_true()
