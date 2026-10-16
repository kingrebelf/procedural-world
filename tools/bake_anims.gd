extends SceneTree
## Bakes the people animations from the Universal Animation Library glbs (copied to
## assets/models/anim by tools/prepare_kits.py, not kept in the repo) into one
## AnimationLibrary resource the game loads: assets/models/anim/humans.res.
##   godot --headless --path . --script res://tools/bake_anims.gd

## name in game -> [source glb, animation, loop]
const PICK := {
	"idle": ["UAL1", "Idle", true], "talk": ["UAL1", "Idle_Talking", true], "walk": ["UAL1", "Walk", true],
	"walk_formal": ["UAL1", "Walk_Formal", true], "jog": ["UAL1", "Jog_Fwd", true], "sprint": ["UAL1", "Sprint", true],
	"fold_arms": ["UAL2", "Idle_FoldArms", true], "lantern": ["UAL2", "Idle_Lantern", true], "torch": ["UAL1", "Idle_Torch", true],
	"no": ["UAL2", "Idle_No", false], "yes": ["UAL2", "Yes", false], "interact": ["UAL1", "Interact", false],
	"harvest": ["UAL2", "Farm_Harvest", true], "plant": ["UAL2", "Farm_PlantSeed", true], "water": ["UAL2", "Farm_Watering", true],
	"chop": ["UAL2", "TreeChopping", true], "fix": ["UAL1", "Fixing_Kneeling", true], "pickup": ["UAL1", "PickUp_Table", true],
	"spell": ["UAL1", "Spell_Simple_Idle", true], "sit": ["UAL1", "Sitting_Idle", true], "sit_talk": ["UAL1", "Sitting_Talking", true],
	"sword_idle": ["UAL1", "Sword_Idle", true], "sword": ["UAL1", "Sword_Attack", false], "punch": ["UAL1", "Punch_Cross", false],
	"pistol_idle": ["UAL1", "Pistol_Idle", true], "pistol": ["UAL1", "Pistol_Shoot", false],
	"hit": ["UAL1", "Hit_Chest", false], "death": ["UAL1", "Death01", false], "dance": ["UAL1", "Dance", true],
	"carry": ["UAL2", "Walk_Carry", true], "swim": ["UAL1", "Swim_Fwd", true],
}

func _initialize() -> void:
	var players := {}
	var roots := []
	for src in ["UAL1", "UAL2"]:
		var n: Node = (load("res://assets/models/anim/%s.glb" % src) as PackedScene).instantiate()
		roots.append(n)
		players[src] = n.find_children("*", "AnimationPlayer", true, false)[0]
	var lib := AnimationLibrary.new()
	for key in PICK:
		var e: Array = PICK[key]
		var a: Animation = (players[e[0]] as AnimationPlayer).get_animation(e[1]).duplicate(true)
		a.loop_mode = Animation.LOOP_LINEAR if e[2] else Animation.LOOP_NONE
		# Keep people in place: the game moves them, so drop the root bone's travel.
		for t in range(a.get_track_count() - 1, -1, -1):
			var path := String(a.track_get_path(t))
			if path.ends_with(":root") and a.track_get_type(t) == Animation.TYPE_POSITION_3D:
				a.remove_track(t)
		lib.add_animation(key, a)
	var err := ResourceSaver.save(lib, "res://assets/models/anim/humans.res", ResourceSaver.FLAG_COMPRESS)
	print("baked %d animations: %s" % [lib.get_animation_list().size(), error_string(err)])
	for n in roots:
		n.free()
	quit()
