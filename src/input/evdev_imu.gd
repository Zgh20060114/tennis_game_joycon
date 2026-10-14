## Evdev IMU reader for hid-nintendo (kernel >= 5.16).
## The driver exposes the IMU as a plain input device named e.g.
## "Joy-Con (L) (IMU)": ABS_X/Y/Z = accelerometer, ABS_RX/RY/RZ = gyroscope,
## MSC_TIMESTAMP per sample, ~200 Hz (3 samples per 15 ms report).
## Axis convention after in-kernel normalization (both Joy-Cons identical):
## +X toward the triggers, +Y to the left, +Z up out of the buttons face.
## Scales: accel resolution 4096 digits per G, gyro 14247 digits per deg/s.

const G_REF := 9.81
const ACCEL_RES_PER_G := 4096.0
const GYRO_RES_PER_DPS := 14247.0

const EV_SYN := 0x00
const EV_MSC := 0x04
const SYN_REPORT := 0x00
const MSC_TIMESTAMP := 0x05       # verified from a live hid-nintendo stream
const EVENT_SIZE := 24            # sizeof(struct input_event) on 64-bit


## Stateful event parser: feed raw bytes (any chunking), pop complete samples.
class Parser:
	var _buf := PackedByteArray()

	func feed(bytes: PackedByteArray) -> void:
		_buf.append_array(bytes)

	func pop_sample() -> Dictionary:
		while _buf.size() >= EVENT_SIZE:
			var sb := StreamPeerBuffer.new()
			sb.data_array = _buf.slice(0, EVENT_SIZE)
			@warning_ignore("integer_division")
			var tv_sec := sb.get_64()
			var tv_usec := sb.get_64()
			var type := sb.get_16()
			var code := sb.get_16()
			var value := sb.get_32()
			_buf = _buf.slice(EVENT_SIZE)
			# tv_sec/tv_usec are unused for deltas; MSC_TIMESTAMP carries sample time.
			if type == EV_SYN and code == SYN_REPORT:
				if _pending.has_all(["ax", "ay", "az", "gx", "gy", "gz"]):
					var s: Dictionary = _pending
					_pending = {}
					s.accel = Vector3(s.ax / ACCEL_RES_PER_G * G_REF,
							s.ay / ACCEL_RES_PER_G * G_REF,
							s.az / ACCEL_RES_PER_G * G_REF)
					s.gyro = Vector3(s.gx / GYRO_RES_PER_DPS,
							s.gy / GYRO_RES_PER_DPS,
							s.gz / GYRO_RES_PER_DPS) * PI / 180.0
					s.erase("ax"); s.erase("ay"); s.erase("az")
					s.erase("gx"); s.erase("gy"); s.erase("gz")
					return s
				_pending = {}
			elif type == EV_MSC and code == MSC_TIMESTAMP:
				_pending = {"t_us": value}   # a new sample begins
			elif type == 0x03:             # EV_ABS
				match code:
					0x00: _pending["ax"] = value
					0x01: _pending["ay"] = value
					0x02: _pending["az"] = value
					0x03: _pending["gx"] = value
					0x04: _pending["gy"] = value
					0x05: _pending["gz"] = value
			# Other event types (keys, etc.) are ignored; streams stay in sync.
		return {}

	var _pending: Dictionary = {}


## Live device source. Godot 4.7's FileAccess refuses to open character
## devices outright, and OS.execute_with_pipe proved unreliable for a
## long-lived blocking byte pump (dead pipes, exit hangs), so the device is
## read by a stdlib-only Python bridge that forwards raw evdev bytes over
## localhost UDP. Decoding stays in Parser (unit-tested); reads here are
## non-blocking: no data simply returns {}.
const BRIDGE_SCRIPT := "res://tools/evdev_udp_bridge.py"
const BRIDGE_TIMEOUT_S := 3.0

class Source:
	var parser := Parser.new()
	var udp := PacketPeerUDP.new()
	var pid := -1
	var _bridge_ready := false

	func _init(path: String) -> void:
		if udp.bind(0) != OK:
			push_error("EvdevImu.Source: cannot bind UDP port")
			return
		var bridge_path := ProjectSettings.globalize_path(BRIDGE_SCRIPT)
		pid = OS.create_process("python3", PackedStringArray([bridge_path, path, str(udp.get_local_port())]))
		if pid == -1:
			push_error("EvdevImu.Source: cannot spawn python3 bridge for %s" % path)
			return
		var t0 := Time.get_ticks_usec()
		while Time.get_ticks_usec() - t0 < BRIDGE_TIMEOUT_S * 1e6:
			if udp.get_available_packet_count() > 0:
				udp.get_packet()
				_bridge_ready = true
				return
			OS.delay_msec(10)
		push_error("EvdevImu.Source: bridge did not report ready for %s" % path)

	func is_valid() -> bool:
		return _bridge_ready

	## Stop the bridge process and release the socket. Call before quitting.
	func close() -> void:
		if pid > 0:
			OS.kill(pid)
			pid = -1
		udp.close()
		_bridge_ready = false

	func read_sample() -> Dictionary:
		while true:
			var s: Dictionary = parser.pop_sample()
			if not s.is_empty():
				return s
			if udp.get_available_packet_count() == 0:
				return {}
			parser.feed(udp.get_packet())
		return {}
