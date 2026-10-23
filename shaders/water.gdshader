shader_type canvas_item;

// World-space sea: origin is the world position of the screen's top-left corner,
// area the visible size, so the water stays put in the world while the camera moves.
// Layers: slow depth tint, swell with lit normals, sun glints, caustic web, thin whitecaps.
// Everything that touches world coordinates is highp: Android GPUs default fragment floats to
// mediump (about 3 significant digits, max 65504), which broke the hash into big flat squares.
uniform highp vec2 origin = vec2(0.0);
uniform highp vec2 area = vec2(540.0, 960.0);
uniform highp float t = 0.0;

float hash(highp vec2 p) {
	p = mod(p, 289.0);  // noise repeats every 289 cells, keeps the products small
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(highp vec2 p) {
	highp vec2 i = floor(p);
	highp vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

highp float swell(highp vec2 p) {
	highp float warp = noise(p * 0.012 + t * 0.05) * 3.0;
	return 0.5 * sin(dot(p, vec2(0.020, 0.012)) + t * 0.9 + warp)
		+ 0.3 * sin(dot(p, vec2(-0.011, 0.024)) - t * 0.7 + warp * 1.3)
		+ 0.2 * sin(dot(p, vec2(0.035, -0.020)) + t * 1.3 - warp);
}

void fragment() {
	highp vec2 p = UV * area + origin;

	highp float e = 1.5;
	highp float h0 = swell(p);
	highp float hx = swell(p + vec2(e, 0.0));
	highp float hy = swell(p + vec2(0.0, e));
	vec3 n = normalize(vec3(-(hx - h0) / e * 16.0, -(hy - h0) / e * 16.0, 1.0));
	vec3 light = normalize(vec3(-0.45, -0.55, 0.7));
	float diff = dot(n, light);
	float spec = pow(max(dot(n, normalize(light + vec3(0.0, 0.0, 1.0))), 0.0), 70.0);

	// Patches of deeper and shallower water.
	float depth = noise(p * 0.004 + t * 0.01) * 0.6 + noise(p * 0.011 - t * 0.015) * 0.4;
	vec3 deep = vec3(0.02, 0.18, 0.36);
	vec3 mid = vec3(0.05, 0.38, 0.58);
	vec3 shallow = vec3(0.16, 0.60, 0.72);
	vec3 c = mix(deep, mid, smoothstep(0.25, 0.6, depth));
	c = mix(c, shallow, smoothstep(0.6, 0.85, depth) * 0.75);
	c *= 0.82 + 0.35 * diff;

	// Caustic web: thin bright lines where two drifting noise fields cross.
	float a = noise(p * 0.045 + vec2(t * 0.25, 0.0));
	float b = noise(p * 0.058 - vec2(0.0, t * 0.2) + 7.0);
	float web = pow(1.0 - smoothstep(0.0, 0.07, abs(a - b)), 2.0);
	c += web * 0.05 * (0.4 + depth);

	c += spec * 0.35;

	// Sparse whitecaps on the highest crests.
	float crest = h0 + (noise(p * 0.08 + vec2(t * 0.3, -t * 0.2)) - 0.5) * 0.6;
	c = mix(c, vec3(0.9, 0.97, 1.0), smoothstep(0.92, 1.15, crest) * 0.16);

	COLOR = vec4(c, 1.0);
}
