shader_type canvas_item;

// World-space water: origin is the world position of the screen's top-left corner,
// area the visible size, so the ripples stay put in the world while the camera moves.
uniform vec2 origin = vec2(0.0);
uniform vec2 area = vec2(540.0, 960.0);
uniform float t = 0.0;

void fragment() {
	vec2 p = UV * area + origin;
	float w = sin(p.x * 0.018 + t * 0.8 + sin(p.y * 0.011 + t * 0.5) * 2.0)
		+ sin(p.y * 0.021 - t * 0.6 + sin(p.x * 0.013 + t * 0.4) * 2.0)
		+ sin((p.x + p.y) * 0.012 + t * 0.7);
	w = w / 3.0 * 0.5 + 0.5;
	vec3 deep = vec3(0.04, 0.26, 0.43);
	vec3 shallow = vec3(0.12, 0.52, 0.68);
	vec3 c = mix(deep, shallow, w);
	c += smoothstep(0.82, 1.0, w) * 0.22;
	COLOR = vec4(c, 1.0);
}
