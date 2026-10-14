extends SceneTree
## Unit tests for the evdev IMU parser (Task 4): synthetic byte streams only.

const EvdevImu = preload("res://src/input/evdev_imu.gd")

var checks := 0
var failures := 0


func check(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("PASS  ", label)
	else:
		failures += 1
		print("FAIL  ", label)


func ev(type: int, code: int, value: int) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_64(0)
	b.put_64(0)
	b.put_16(type)
	b.put_16(code)
	b.put_32(value)
	return b.data_array


func sample_bytes(t_us: int, ax: int, ay: int, az: int, gx: int, gy: int, gz: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array(ev(EvdevImu.EV_MSC, EvdevImu.MSC_TIMESTAMP, t_us))
	b.append_array(ev(0x03, 0x00, ax))
	b.append_array(ev(0x03, 0x01, ay))
	b.append_array(ev(0x03, 0x02, az))
	b.append_array(ev(0x03, 0x03, gx))
	b.append_array(ev(0x03, 0x04, gy))
	b.append_array(ev(0x03, 0x05, gz))
	b.append_array(ev(EvdevImu.EV_SYN, EvdevImu.SYN_REPORT, 0))
	return b


func _init() -> void:
	test_parse_complete_sample()
	test_split_chunking()
	test_garbage_events()
	print("----------------------------------------")
	print("%d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures > 0 else 0)


func test_parse_complete_sample() -> void:
	var p := EvdevImu.Parser.new()
	p.feed(sample_bytes(5000, 0, 4096, 0, 14247, 0, 0))
	var s: Dictionary = p.pop_sample()
	check(not s.is_empty(), "one complete sample frame yields a sample")
	if not s.is_empty():
		check(s.accel.is_equal_approx(Vector3(0, 9.81, 0)), "accelerometer scaled to m/s^2 via 4096/G")
		check(absf(s.gyro.x - PI / 180.0) < 1e-9, "gyroscope scaled to rad/s via 14247 per dps")
		check(s.t_us == 5000, "MSC_TIMESTAMP preserved as sample time")
	check(p.pop_sample().is_empty(), "parser drains cleanly after the sample")


func test_split_chunking() -> void:
	var p := EvdevImu.Parser.new()
	var raw := sample_bytes(8333, 4096, 0, 0, 0, 14247, 0)
	for i in range(0, raw.size(), 7):
		p.feed(raw.slice(i, mini(i + 7, raw.size())))
	var s: Dictionary = p.pop_sample()
	check(not s.is_empty(), "bytes split into 7-byte chunks still parse")
	if not s.is_empty():
		check(s.accel.x > 9.5 and s.t_us == 8333, "split stream keeps values and timing intact")


func test_garbage_events() -> void:
	var p := EvdevImu.Parser.new()
	p.feed(ev(0x01, 307, 1))                       # EV_KEY between samples
	p.feed(ev(0x03, 0x00, 12345))                  # stray ABS value, no frame yet
	check(p.pop_sample().is_empty(), "stray events do not fabricate a sample")
	p.feed(sample_bytes(16666, 0, 4096, 0, 0, 0, 0))
	var s: Dictionary = p.pop_sample()
	check(not s.is_empty(), "parser stays in sync after unrelated event types")
	if not s.is_empty():
		check(is_equal_approx(s.accel.y, 9.81), "stray ABS value was overwritten by the real frame")
