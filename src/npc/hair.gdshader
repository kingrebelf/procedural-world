shader_type spatial;
// Kit hair and eyebrows, recoloured per person: the texture's brightness keeps the strands,
// the colour comes from the instance.
render_mode diffuse_burley, cull_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D nrm : hint_normal, filter_linear_mipmap;
instance uniform vec4 hair_col : source_color = vec4(0.2, 0.14, 0.1, 1.0);

void fragment() {
	vec3 t = texture(tex, UV).rgb;
	float lum = dot(t, vec3(0.299, 0.587, 0.114)) / 0.56;
	ALBEDO = hair_col.rgb * clamp(lum, 0.4, 1.6);
	NORMAL_MAP = texture(nrm, UV).rgb;
	ROUGHNESS = 0.55;
	SPECULAR = 0.4;
}
