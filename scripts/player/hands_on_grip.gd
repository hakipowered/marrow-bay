class_name HandsOnGrip
extends SkeletonModifier3D
## Puts a survivor's hands on a handle while a body clip plays: the clip
## gives the effort (the squat and heave of cranking the Undercroft
## generator), this bends each arm so the hand lands on its target, a point
## that moves with the machine (the crank's grip as it turns).
##
## Plain two-bone IK per arm, after the animation: the shoulder stays, the
## elbow keeps bending the way the clip bends it, and the upper arm and
## forearm turn just enough to bring the wrist onto the target; the hand
## turns with the forearm. Works on every outfit (the bones are found by
## name, lengths are measured from the posed skeleton).
##
## CharacterModel.hands_on() adds one under the skeleton; influence fades it
## in and out so the hands don't snap.

var left_target: Node3D
var right_target: Node3D
## The survivor's finger rig, when the body has one: the handle then sits
## in the closed fist instead of running through the wrist.
var rig: HandRig

const ARMS := {"Left": ["LeftArm", "LeftForeArm", "LeftHand"], "Right": ["RightArm", "RightForeArm", "RightHand"]}

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var inv := sk.global_transform.affine_inverse()
	if left_target and is_instance_valid(left_target):
		_reach(sk, "Left", inv * left_target.global_position)
	if right_target and is_instance_valid(right_target):
		_reach(sk, "Right", inv * right_target.global_position)

func _reach(sk: Skeleton3D, side: String, target: Vector3) -> void:
	var bones: Array = ARMS[side]
	var ia := sk.find_bone(bones[0])
	var ib := sk.find_bone(bones[1])
	var ic := sk.find_bone(bones[2])
	if ia < 0 or ib < 0 or ic < 0:
		return
	var ga := sk.get_bone_global_pose(ia)
	var gb := sk.get_bone_global_pose(ib)
	var gc := sk.get_bone_global_pose(ic)
	var a := ga.origin
	var b := gb.origin
	var c := gc.origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	if l1 < 0.001 or l2 < 0.001:
		return
	# The handle goes in the fist: aim the wrist off the target by the
	# wrist-to-fist offset, as the hand will be turned (solved twice: the
	# turn depends on where the wrist ends up).
	var grip := Vector3.ZERO
	if rig and rig.hands.has(side):
		grip = rig.hands[side]["grip"]
	var hand_basis := gc.basis
	var sol: Array = []
	for i in (2 if grip != Vector3.ZERO else 1):
		sol = _solve(a, b, c, l1, l2, target - hand_basis.orthonormalized() * grip)
		hand_basis = Basis(sol[3]) * gc.basis
	var elbow: Vector3 = sol[0]
	var wrist: Vector3 = sol[1]
	var r1: Quaternion = sol[2]
	var r21: Quaternion = sol[3]
	sk.set_bone_global_pose(ia, Transform3D(Basis(r1) * ga.basis, a))
	sk.set_bone_global_pose(ib, Transform3D(Basis(r21) * gb.basis, elbow))
	sk.set_bone_global_pose(ic, Transform3D(Basis(r21) * gc.basis, wrist))

## Two-bone solve: [elbow, wrist, upper arm turn, forearm turn].
func _solve(a: Vector3, b: Vector3, c: Vector3, l1: float, l2: float, target: Vector3) -> Array:
	var to_t := target - a
	var d := clampf(to_t.length(), absf(l1 - l2) + 0.002, l1 + l2 - 0.002)
	var dir := to_t.normalized() if to_t.length() > 0.0001 else (c - a).normalized()
	# The way the elbow points, from the clip, square to the reach.
	var pole := (b - a) - dir * (b - a).dot(dir)
	if pole.length() < 0.0001:
		pole = Vector3.DOWN - dir * Vector3.DOWN.dot(dir)
	pole = pole.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var elbow := a + dir * (l1 * cos_a) + pole * (l1 * sqrt(1.0 - cos_a * cos_a))
	var wrist := a + dir * d
	var r1 := Quaternion((b - a).normalized(), (elbow - a).normalized())
	var fore_now := Basis(r1) * (c - b)
	var r2 := Quaternion(fore_now.normalized(), (wrist - elbow).normalized())
	return [elbow, wrist, r1, r2 * r1]
