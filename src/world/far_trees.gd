class_name FarTrees
extends MeshInstance3D
## The trees on the distant land, from where the streamed chunks end out to TREE_BB_TO
## (forest.gdshaderinc): one camera-facing billboard per tree, standing where the
## distant land paints its shadow. All on the GPU: the mesh is a fixed grid of quads, one
## per forest cell round you, and far_trees.gdshader stands each up or hides it. FarLand
## hands it the forest data and the mask of the chunks drawn near you.

const CELL := 4.5
## Cells out to this far from you (past TREE_BB_TO), none nearer than INNER (always
## streamed in, so never a distant tree).
const REACH := 905.0
const INNER := 150.0

static var _mesh: ArrayMesh

var mat: ShaderMaterial

func _ready() -> void:
	mat = ShaderMaterial.new()
	mat.shader = load("res://src/world/far_trees.gdshader")
	material_override = mat
	mesh = grid_mesh()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The quads move to their trees in the vertex shader, anywhere in the grid's reach.
	extra_cull_margin = 4000.0

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Whole cells round the eye, so a quad keeps its cell's tree as you move.
	var p := cam.global_position
	global_position = Vector3(roundf(p.x / CELL) * CELL, 0.0, roundf(p.z / CELL) * CELL)

## The grid of quads (built once): each quad's four corners on its cell's corner, UV
## the quad's corner (y up).
static func grid_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var n := int(ceil(REACH / CELL))
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in range(-n, n + 1):
		for i in range(-n, n + 1):
			var r := Vector2(i, j).length() * CELL
			if r < INNER or r > REACH:
				continue
			var v := verts.size()
			var at := Vector3(i * CELL, 0.0, j * CELL)
			verts.append_array([at, at, at, at])
			uvs.append_array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)])
			idx.append_array([v, v + 2, v + 1, v + 1, v + 2, v + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return _mesh
