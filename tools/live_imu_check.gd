extends SceneTree
## Live Joy-Con IMU bring-up check (real hardware, no display needed).
## Run: scripts/run_godot.sh --headless --script tools/live_imu_check.gd
## Phase 1: discover + open + device-rate probe. Phase 2: hold still 2 s
## (gyro bias calibration). Phase 3: 5 s live readout — swing freely.

const Discovery = preload("res://src/input/imu_discovery.gd")
const EvdevImu = preload("res://src/input/evdev_imu.gd")
const JoyconDriver = preload("res://src/input/joycon_driver.gd")


func _init() -> void:
	var side := "left"
	var path := Discovery.discover(side)
	print("发现 %s 手 Joy-Con IMU: %s" % [side, path if path != "" else "（未找到！）"])
	if path.is_empty():
		quit(1)
		return
	var src := EvdevImu.Source.new(path)
	if not src.is_valid():
		print("打开失败——通常是权限问题（需要 input 组或 udev uaccess ACL）")
		quit(1)
		return
	var d := JoyconDriver.new(src)
	d.handedness = side

	print("阶段 0：3 秒后开始校准——请现在握好 Joy-Con 并保持静止")
	var tc := Time.get_ticks_usec()
	var last_shown := 4
	while Time.get_ticks_usec() - tc < 3_000_000:
		src.read_sample()
		var remain: int = 3 - (Time.get_ticks_usec() - tc) / 1_000_000 + 1
		if remain < last_shown:
			last_shown = remain
			if remain > 0:
				print("  %d…" % remain)

	print("阶段 1：静止校准 2 秒（陀螺零偏采样中）……")
	var bias := d.calibrate(2.0, 200.0)
	print("gyro_bias = %s rad/s" % bias)

	print("阶段 2：实时读取 5 秒，随意移动、挥动！")
	var t0 := Time.get_ticks_usec()
	var n := 0
	var last_print := 0
	var peak_speed := 0.0
	while Time.get_ticks_usec() - t0 < 5_000_000:
		if d.pull():
			n += 1
			peak_speed = maxf(peak_speed, d.head_velocity.length())
			if n - last_print >= 40:
				last_print = n
				var e := Basis(d.quat).get_euler(EULER_ORDER_YXZ)
				print("t=%.1fs  pitch=%+6.1f°  yaw=%+6.1f°  roll=%+6.1f°  挥速=%4.2f m/s" % [
						(Time.get_ticks_usec() - t0) / 1e6,
						rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z),
						d.head_velocity.length()])
	var secs := (Time.get_ticks_usec() - t0) / 1e6
	print("处理率 %.0f 样本/s，峰值挥速 %.2f m/s" % [n / secs, peak_speed])
	print("设备时间戳采样率约 %.0f Hz（中位 dt）" % _device_rate(src, 1.5))
	src.close()
	quit(0 if n > 200 else 1)


## Measure the true device sample rate from MSC_TIMESTAMP deltas.
func _device_rate(src, seconds: float) -> float:
	var dts: Array = []
	var last_t := -1
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < seconds * 1e6:
		var s: Dictionary = src.read_sample()
		if s.is_empty():
			continue
		if last_t >= 0 and s.t_us > last_t:
			dts.append(s.t_us - last_t)
		last_t = s.t_us
	if dts.size() < 10:
		return 0.0
	dts.sort()
	return 1e6 / float(dts[dts.size() / 2])
