class_name Movers
## The render layer of people and animals more than a few metres from the camera. Lamps
## that cast shadows indoors leave it out of their light: a body moving within a lamp's
## reach re-renders all six faces of its shadow cube every frame, and a busy street
## passes dozens of lit rooms. Close by, people are back on layer 1, lit and shadowed by
## every lamp.
const LAYER := 1 << 18
## Further than this (metres) from the camera, a body is on LAYER (nearer by 2 m to come
## back, so one at the edge doesn't flip back and forth).
const FAR := 16.0

## Whether a body `d` metres from the camera belongs on LAYER, given where it is now.
static func is_far(d: float, now_far: bool) -> bool:
	return d > (FAR - 2.0 if now_far else FAR)

## Puts every mesh under `root` on LAYER (far) or back on layer 1.
static func set_far(root: Node, far: bool) -> void:
	var layer := LAYER if far else 1
	for gi in root.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).layers = layer
