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
		var name_f := FileAccess.open(base.path_join("name"), FileAccess.READ)
		if name_f == null:
			continue
		var dev_name := name_f.get_as_text().strip_edges()
		if not dev_name.contains("(IMU)"):
			continue
		var prod_f := FileAccess.open(base.path_join("id/product"), FileAccess.READ)
		if prod_f == null:
			continue
		if prod_f.get_as_text().strip_edges().to_lower() != want_product:
			continue
		var events := DirAccess.get_directories_at(base)
		for event_name: String in events:
			if event_name.begins_with("event"):
				return "/dev/input/" + event_name
	return ""
