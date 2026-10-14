extends SceneTree
## Headless smoke test: verifies the engine can boot, load the project, and run a script.
## Run: scripts/run_godot.sh --headless --script tests/smoke_test.gd


func _init() -> void:
	var court_length := 23.77
	var court_width := 8.23
	assert(court_length > 0.0 and court_width > 0.0)
	print("SMOKE_OK godot=%s court=%.2fx%.2f" % [Engine.get_version_info().string, court_length, court_width])
	quit(0)
