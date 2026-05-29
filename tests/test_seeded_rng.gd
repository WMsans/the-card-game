extends GdUnitTestSuite

func test_same_seed_shuffles_identically() -> void:
	var a := [1, 2, 3, 4, 5, 6, 7, 8]
	var b := [1, 2, 3, 4, 5, 6, 7, 8]
	SeededRng.new(42).shuffle(a)
	SeededRng.new(42).shuffle(b)
	assert_array(a).is_equal(b)

func test_different_seed_shuffles_differently() -> void:
	var a := [1, 2, 3, 4, 5, 6, 7, 8]
	var b := [1, 2, 3, 4, 5, 6, 7, 8]
	SeededRng.new(1).shuffle(a)
	SeededRng.new(2).shuffle(b)
	assert_array(a).is_not_equal(b)
