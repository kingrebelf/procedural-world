class_name RagdollWriter
extends SkeletonModifier3D
## Poses a skeleton's bones from its ragdoll's bodies, after whatever else runs.

var rag: Ragdoll

func _process_modification_with_delta(_delta: float) -> void:
	if rag and is_instance_valid(rag) and rag.is_live():
		rag.write_pose()
