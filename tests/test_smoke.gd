extends GdUnitTestSuite

func test_arithmetic() -> void:
	assert_int(2 + 2).is_equal(4)
