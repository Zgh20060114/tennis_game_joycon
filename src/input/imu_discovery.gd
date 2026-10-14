## Locate the Joy-Con IMU evdev node. hid-nintendo registers one input device
## per controller named "<ctlr name> (IMU)"; product id 0x2006 = Joy-Con (L),
## 0x2007 = Joy-Con (R). Scanning lives in sysfs so a fake root can be
## injected for unit tests without hardware.

const LEFT_PRODUCT := "2006"
const RIGHT_PRODUCT := "2007"
const DEFAULT_SYSFS := "/sys/class/input"


## Returns the /dev/input/eventN path for the requested side, or "".
static func discover(side: String, sysfs_root := DEFAULT_SYSFS) -> String:
	var want_product := LEFT_PRODUCT if side == "left" else RIGHT_PRODUCT
	var inputs := DirAccess.get_directories_at(sysfs_root)
	for input_name: String in inputs:
		var base := sysfs_root.path_join(input_name)
		if not _read_file(base.path_join("name")).contains("(IMU)"):
			continue
		if _read_file(base.path_join("id/product")).to_lower() != want_product:
			continue
		var events := DirAccess.get_directories_at(base)
		for event_name: String in events:
			if event_name.begins_with("event"):
				return "/dev/input/" + event_name
	return ""


## sysfs files report size 0, which breaks FileAccess.get_as_text(); read a
## fixed window to EOF instead.
static func _read_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_buffer(4096).get_string_from_utf8().strip_edges()
