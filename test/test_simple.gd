extends GutTest

func test_addition_simple():
	# Sanity check to validate that GUT execution pipeline is functional.
	assert_eq(1 + 1, 2, "1 + 1 doit valoir 2")
