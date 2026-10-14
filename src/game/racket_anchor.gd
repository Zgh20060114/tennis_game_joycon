## First-person racket anchoring. Pure transforms so handedness mirroring is
## unit-testable; court_scene applies the result to the racket node.

const READY_OFFSET := Vector3(0.25, -0.15, -0.45)   # camera-space, right hand


## Mirror a rotation through the sagittal (YZ) plane: used to map a swing to
## the opposite hand. Quaternion components: (x, y, z, w) -> (x, -y, -z, w).
static func mirror_quat(q: Quaternion) -> Quaternion:
	return Quaternion(q.x, -q.y, -q.z, q.w)


## Grip transform in world space for the given handedness, camera transform,
## and swing-relative orientation (neutral_quat.inverse() * driver.quat).
static func anchor_transform(handedness: String, cam: Transform3D, rel_quat: Quaternion) -> Transform3D:
	var right := handedness != "left"
	var side := 1.0 if right else -1.0
	var q := rel_quat if right else mirror_quat(rel_quat)
	var local := Transform3D(q, Vector3(side * READY_OFFSET.x, READY_OFFSET.y, READY_OFFSET.z))
	return cam * local
