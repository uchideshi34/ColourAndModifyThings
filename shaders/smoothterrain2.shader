shader_type canvas_item;
render_mode blend_mix;

// textures
uniform sampler2D texture_1;
uniform sampler2D texture_2;
uniform sampler2D texture_3;
uniform sampler2D texture_4;
uniform sampler2D texture_5;
uniform sampler2D texture_6;
uniform sampler2D texture_7;
uniform sampler2D texture_8;

// splat maps (first for slots 1-4, second for slots 5-8)
uniform sampler2D splat;
uniform sampler2D splat2;

// tints
uniform vec4 tint_colour_1;
uniform vec4 tint_colour_2;
uniform vec4 tint_colour_3;
uniform vec4 tint_colour_4;
uniform vec4 tint_colour_5;
uniform vec4 tint_colour_6;
uniform vec4 tint_colour_7;
uniform vec4 tint_colour_8;

// gradient controls
uniform bool apply_gradient_1;
uniform bool apply_gradient_2;
uniform bool apply_gradient_3;
uniform bool apply_gradient_4;
uniform bool apply_gradient_5;
uniform bool apply_gradient_6;
uniform bool apply_gradient_7;
uniform bool apply_gradient_8;

uniform sampler2D gradient_atlas;

uniform bool flip_x_1;
uniform bool flip_x_2;
uniform bool flip_x_3;
uniform bool flip_x_4;
uniform bool flip_x_5;
uniform bool flip_x_6;
uniform bool flip_x_7;
uniform bool flip_x_8;

uniform bool flip_y_1;
uniform bool flip_y_2;
uniform bool flip_y_3;
uniform bool flip_y_4;
uniform bool flip_y_5;
uniform bool flip_y_6;
uniform bool flip_y_7;
uniform bool flip_y_8;


// per-texture rotation (radians)
uniform float texture_rotation_1 = 0.0;
uniform float texture_rotation_2 = 0.0;
uniform float texture_rotation_3 = 0.0;
uniform float texture_rotation_4 = 0.0;
uniform float texture_rotation_5 = 0.0;
uniform float texture_rotation_6 = 0.0;
uniform float texture_rotation_7 = 0.0;
uniform float texture_rotation_8 = 0.0;

// misc
uniform float blend_step = 0.04;
uniform vec2 map_size;

// varyings
varying vec2 world_uv;
varying vec2 texture_1_uv;
varying vec2 texture_2_uv;
varying vec2 texture_3_uv;
varying vec2 texture_4_uv;
varying vec2 texture_5_uv;
varying vec2 texture_6_uv;
varying vec2 texture_7_uv;
varying vec2 texture_8_uv;

// Sample the gradient
vec4 sample_gradient(float gray, int index) {
	float rows = 8.0; // total gradients
	float row_height = 1.0 / rows;
	float y = (float(index) + 0.5) * row_height; // sample midline of each row
	return texture(gradient_atlas, vec2(gray, y));
}

// Rotate UV algorithm (kept from your original shader)
vec2 rotate_uv(vec2 uv, float r)
{
	float mid = 0.5;
	return vec2(
		cos(r) * (uv.x - mid) + sin(r) * (uv.y - mid) + mid,
		cos(r) * (uv.y - mid) - sin(r) * (uv.x - mid) + mid
	);
}

// Convert world vertex to texture UVs based on texture size
vec2 texture2uv(sampler2D t, vec2 uv)
{
	ivec2 size = textureSize(t, 0);
	// protect against textures with zero size (shouldn't happen, but safe)
	if (size.x == 0 || size.y == 0) {
		return uv;
	}
	uv.x /= float(size.x);
	uv.y /= float(size.y);
	return uv;
}

void vertex()
{
	world_uv = VERTEX;

	texture_1_uv = rotate_uv(texture2uv(texture_1, world_uv), texture_rotation_1);
	texture_2_uv = rotate_uv(texture2uv(texture_2, world_uv), texture_rotation_2);
	texture_3_uv = rotate_uv(texture2uv(texture_3, world_uv), texture_rotation_3);
	texture_4_uv = rotate_uv(texture2uv(texture_4, world_uv), texture_rotation_4);
	texture_5_uv = rotate_uv(texture2uv(texture_5, world_uv), texture_rotation_5);
	texture_6_uv = rotate_uv(texture2uv(texture_6, world_uv), texture_rotation_6);
	texture_7_uv = rotate_uv(texture2uv(texture_7, world_uv), texture_rotation_7);
	texture_8_uv = rotate_uv(texture2uv(texture_8, world_uv), texture_rotation_8);
}

// helper: max of 4 floats
float max4(float v1, float v2, float v3, float v4)
{
	return max(max(v1, v2), max(v3, v4));
}

// blend for eight textures
vec3 blend8(
	vec3 t1, float h1, vec3 t2, float h2, vec3 t3, float h3, vec3 t4, float h4,
	vec3 t5, float h5, vec3 t6, float h6, vec3 t7, float h7, vec3 t8, float h8)
{
	float height_start = max(max4(h1,h2,h3,h4), max4(h5,h6,h7,h8)) - blend_step;

	float s1 = max(h1 - height_start, 0.0);
	float s2 = max(h2 - height_start, 0.0);
	float s3 = max(h3 - height_start, 0.0);
	float s4 = max(h4 - height_start, 0.0);
	float s5 = max(h5 - height_start, 0.0);
	float s6 = max(h6 - height_start, 0.0);
	float s7 = max(h7 - height_start, 0.0);
	float s8 = max(h8 - height_start, 0.0);

	float splat_sum = s1 + s2 + s3 + s4 + s5 + s6 + s7 + s8;

	// avoid division by zero: if nothing contributes, fallback to the highest channel
	if (splat_sum <= 0.00001) {
		// determine the index of the max height and return that texture color
		float m = max(max4(h1,h2,h3,h4), max4(h5,h6,h7,h8));
		if (m == h1) return t1;
		if (m == h2) return t2;
		if (m == h3) return t3;
		if (m == h4) return t4;
		if (m == h5) return t5;
		if (m == h6) return t6;
		if (m == h7) return t7;
		return t8;
	}

	return ((t1 * s1) + (t2 * s2) + (t3 * s3) + (t4 * s4) + (t5 * s5) + (t6 * s6) + (t7 * s7) + (t8 * s8)) / splat_sum;
}

// apply tint and optional gradient to the sampled texture color
vec4 get_coloured_texture(sampler2D tex, vec2 uv, vec4 tint_colour, bool apply_gradient, int gradient_index, bool flip_x, bool flip_y)
{

	if (flip_x) {
		uv.x = -uv.x;
	}
	if (flip_y) {
		uv.y = -uv.y;
	}

	vec4 color = texture(tex, uv); // get standard colour from texture

	if (apply_gradient) // If we want a gradient colour applied
	{ 
		float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114)); // Convert the color to grayscale
		gray = clamp(gray, 0.0, 1.0);
		vec4 gradient_color = sample_gradient(gray, gradient_index); // calculate the gradient color
		color = vec4(gradient_color.rgb,color.a); // update the color with the new gradient color
	}

	return color * vec4(tint_colour.rgb,1.0); // multiply by the modulate
}

void fragment()
{
	// sample splat maps using world_uv scaled by map_size
	vec4 s = texture(splat, world_uv / map_size);
	vec4 s2 = texture(splat2, world_uv / map_size);

	// sample & tint each texture (apply gradient if requested)
	vec4 t1 = get_coloured_texture(texture_1, texture_1_uv, tint_colour_1, apply_gradient_1, 0, flip_x_1, flip_y_1);
	vec4 t2 = get_coloured_texture(texture_2, texture_2_uv, tint_colour_2, apply_gradient_2, 1, flip_x_2, flip_y_2);
	vec4 t3 = get_coloured_texture(texture_3, texture_3_uv, tint_colour_3, apply_gradient_3, 2, flip_x_3, flip_y_3);
	vec4 t4 = get_coloured_texture(texture_4, texture_4_uv, tint_colour_4, apply_gradient_4, 3, flip_x_4, flip_y_4);
	vec4 t5 = get_coloured_texture(texture_5, texture_5_uv, tint_colour_5, apply_gradient_5, 4, flip_x_5, flip_y_5);
	vec4 t6 = get_coloured_texture(texture_6, texture_6_uv, tint_colour_6, apply_gradient_6, 5, flip_x_6, flip_y_6);
	vec4 t7 = get_coloured_texture(texture_7, texture_7_uv, tint_colour_7, apply_gradient_7, 6, flip_x_7, flip_y_7);
	vec4 t8 = get_coloured_texture(texture_8, texture_8_uv, tint_colour_8, apply_gradient_8, 7, flip_x_8, flip_y_8);

	float splatSum = s.r + s.g + s.b + s.a + s2.r +s2.g + s2.b + s2.a;
	vec3 albedo =
		t1.rgb * s.r + t2.rgb * s.g + t3.rgb * s.b + t4.rgb * s.a +
		t5.rgb * s2.r + t6.rgb * s2.g + t7.rgb * s2.b + t8.rgb * s2.a;
	albedo /= splatSum;

	COLOR.rgb = albedo;
}
