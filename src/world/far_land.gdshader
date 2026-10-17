shader_type spatial;
// Distant land (FarLand): the terrain's own look on a coarse grid out to the horizon,
// left out wherever a real chunk of terrain is drawn.
#define FAR_LAND
#include "res://src/world/terrain.gdshaderinc"
