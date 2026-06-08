extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

func test_annav2_autoload_exists():
	assert_bool(ANNAV2 != null).is_true()
	assert_str(ANNAV2.name).is_equal("ANNAV2")

func test_annav2_player_id():
	var id = ANNAV2._player_id
	assert_str(id).is_not_empty()

func test_annav2_session_id():
	var id = ANNAV2._session_id
	assert_str(id).is_not_empty()
