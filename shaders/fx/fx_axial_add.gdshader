shader_type spatial;
// Glowing axial quads: tracers, sparks, muzzle blasts. See fx_axial.gdshaderinc.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, skip_vertex_transform, shadows_disabled;
#include "res://shaders/fx/fx_axial.gdshaderinc"
