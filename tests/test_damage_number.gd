extends GdUnitTestSuite

func _host() -> Control:
	var c := Control.new()
	add_child(c)
	auto_free(c)
	return c

func test_spawn_adds_node_with_minus_label() -> void:
	var host := _host()
	var dn := DamageNumber.spawn(host, Vector2(500, 500), 3)
	assert_object(dn).is_not_null()
	assert_bool(host.is_ancestor_of(dn)).is_true()
	var found := ""
	for child in dn.get_children():
		if child is Label:
			found = child.text
	assert_str(found).is_equal("-3")

func test_big_hit_uses_distinct_tint() -> void:
	var host := _host()
	var small := DamageNumber.spawn(host, Vector2(0, 0), 1, false)
	var big := DamageNumber.spawn(host, Vector2(0, 0), 7, true)
	var small_label: Label = _first_label(small)
	var big_label: Label = _first_label(big)
	assert_bool(small_label.modulate.is_equal_approx(big_label.modulate)).is_false()

func test_particle_self_frees_after_lifetime() -> void:
	var host := _host()
	var dn := DamageNumber.spawn(host, Vector2(100, 100), 2)
	await get_tree().create_timer(DamageNumber.LIFETIME + 0.3).timeout
	assert_bool(is_instance_valid(dn)).is_false()

func _first_label(dn: Node) -> Label:
	for child in dn.get_children():
		if child is Label:
			return child
	return null
