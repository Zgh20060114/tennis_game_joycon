## JoyConDriver: orchestrates device discovery, sample reading, attitude
## filtering and swing-velocity estimation, with a worker thread for polling.
## The injectable `source` (anything with read_sample() -> Dictionary) keeps
## the whole pipeline testable without hardware; the real source is
## EvdevImu.Source. Output per sample:
##   quat          body -> world orientation
##   omega_world   angular velocity (rad/s, world frame)
##   head_velocity racket-head velocity estimate (m/s, world frame)
## Swing velocity = omega x lever + leaky-integrated linear acceleration
## (the leak prevents double-integration drift; rotation dominates swings).

const AttitudeFilter = preload("res://src/input/attitude_filter.gd")
const EvdevImu = preload("res://src/input/evdev_imu.gd")
const Discovery = preload("res://src/input/imu_discovery.gd")

const LEVER_DEFAULT := Vector3(0.0, -0.55, 0.0)   # grip -> head in body frame
const V_LIN_DECAY := 2.0                          # 1/s leak factor
const DT_MIN := 0.0005
const DT_MAX := 0.05

var source                         # object with read_sample() -> Dictionary
var filter: AttitudeFilter
var handedness := "right"
var mirror_axes := false           # negate X of accel/gyro (comfort tuning; the kernel already normalizes L/R)
var lever := LEVER_DEFAULT

var quat := Quaternion.IDENTITY
var omega_world := Vector3.ZERO
var head_velocity := Vector3.ZERO

var _last_t_us := -1
var _v_lin := Vector3.ZERO

# Worker thread plumbing
var _thread: Thread
var _mutex: Mutex
var _running := false


func _init(p_source = null) -> void:
	source = p_source
	filter = AttitudeFilter.new()
	_mutex = Mutex.new()


## Discover and open the evdev IMU node for the configured handedness.
func open_device(sysfs_root := Discovery.DEFAULT_SYSFS) -> bool:
	var path := Discovery.discover(handedness, sysfs_root)
	if path.is_empty():
		return false
	source = EvdevImu.Source.new(path)
	return source.is_valid()


## Calibrate by averaging the stream while the controller is held still.
func calibrate(seconds: float, sample_rate := 120.0) -> Vector3:
	if source == null:
		return Vector3.ZERO
	filter.gyro_bias = filter.capture_bias(source, int(seconds * sample_rate))
	return filter.gyro_bias


func pull() -> bool:
	if source == null:
		return false
	var s: Dictionary = source.read_sample()
	if s.is_empty():
		_decay(_default_dt())
		return false
	var t_us: int = s.get("t_us", 0)
	var dt: float = _default_dt()
	if _last_t_us >= 0:
		dt = clampf(float(t_us - _last_t_us) * 1e-6, DT_MIN, DT_MAX)
	_last_t_us = t_us
	if mirror_axes:
		s.accel.x = -s.accel.x
		s.gyro.x = -s.gyro.x
	filter.step(s.gyro, s.accel, dt)
	var omega_body: Vector3 = s.gyro - filter.gyro_bias
	omega_world = filter.quat * omega_body
	var a_lin: Vector3 = filter.quat * s.accel + Vector3(0.0, -AttitudeFilter.GRAVITY, 0.0)
	_v_lin = _v_lin * exp(-V_LIN_DECAY * dt) + a_lin * dt
	# lever is a body-frame offset; rotate it into world before the cross product.
	head_velocity = omega_world.cross(quat * lever) + _v_lin
	quat = filter.quat
	return true


func start() -> void:
	if _running:
		return
	_running = true
	_thread = Thread.new()
	_thread.start(_poll_loop)


func stop() -> void:
	_running = false
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
	if source != null and source.has_method("close"):
		source.close()


func _poll_loop() -> void:
	# The UDP source is non-blocking, so pace the worker thread explicitly.
	while _running:
		_mutex.lock()
		pull()
		_mutex.unlock()
		OS.delay_usec(2000)


func _decay(dt: float) -> void:
	# No data (or dropout): freeze pose, let velocities bleed off smoothly.
	_v_lin = _v_lin * exp(-V_LIN_DECAY * dt)
	head_velocity = head_velocity * exp(-V_LIN_DECAY * dt)


func _default_dt() -> float:
	return 1.0 / 120.0
