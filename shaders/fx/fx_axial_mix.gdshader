shader_type spatial;
// Opaque-ish axial quads: blood drops and sprays. See fx_axial.gdshaderinc.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, skip_vertex_transform, shadows_disabled;
#include "res://shaders/fx/fx_axial.gdshaderinc"
