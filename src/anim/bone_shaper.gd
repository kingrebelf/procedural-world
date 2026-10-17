class_name BoneShaper
extends SkeletonModifier3D
## Reshapes a rigged animal after it is animated: chosen bones scaled (each scales
## everything below it), so one kit's rig and clips can stand in for another animal: a
## cow's body with a boar's heavy head and stub tail, a fox's with a hare's long ears.
## Runs after the animation and after a ragdoll has placed the bones.

## bone index -> Vector3 scale in that bone's own space.
var scales := {}

func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for b in scales:
		var g := sk.get_bone_global_pose(b)
		g.basis = g.basis * Basis.from_scale(scales[b])
		sk.set_bone_global_pose(b, g)
