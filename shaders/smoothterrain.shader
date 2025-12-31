shader_type canvas_item;
render_mode blend_mix;

uniform vec4 tint_colour_1;
uniform vec4 tint_colour_2;
uniform vec4 tint_colour_3;
uniform vec4 tint_colour_4;

uniform bool apply_gradient_1;
uniform bool apply_gradient_2;
uniform bool apply_gradient_3;
uniform bool apply_gradient_4;

uniform sampler2D gradient_atlas;

uniform bool flip_x_1;
uniform bool flip_x_2;
uniform bool flip_x_3;
uniform bool flip_x_4;

uniform bool flip_y_1;
uniform bool flip_y_2;
uniform bool flip_y_3;
uniform bool flip_y_4;

uniform float texture_rotation_1 = 0.0;
uniform float texture_rotation_2 = 0.0;
uniform float texture_rotation_3 = 0.0;
uniform float texture_rotation_4 = 0.0;

uniform sampler2D texture_1;
uniform sampler2D texture_2;
uniform sampler2D texture_3;
uniform sampler2D texture_4;
uniform sampler2D splat;
uniform float blend_step = 0.04;
uniform vec2 map_size;
varying vec2 world_uv;
varying vec2 texture_1_uv;
varying vec2 texture_2_uv;
varying vec2 texture_3_uv;
varying vec2 texture_4_uv;

// Sample the gradient
vec4 sample_gradient(float gray, int index) {
    float rows = 8.0; // total gradients
    float row_height = 1.0 / rows;
    float y = (float(index) + 0.5) * row_height; // sample midline of each row
    return texture(gradient_atlas, vec2(gray, y));
}

// Rotate UV algorithm taken from the official DD pattern shader
vec2 rotate_uv(vec2 uv, float r)
{
	float mid = 0.5;
	return vec2(
		cos(r) * (uv.x - mid) + sin(r) * (uv.y - mid) + mid,
		cos(r) * (uv.y - mid) - sin(r) * (uv.x - mid) + mid
	);
}


vec2 texture2uv(sampler2D t, vec2 uv)
{
	ivec2 size = textureSize(t, 0);
	uv.x /= float(size.x);
	uv.y /= float(size.y);
	return uv;
}

void vertex()
{
	world_uv = VERTEX;
	texture_1_uv = rotate_uv(texture2uv(texture_1, world_uv),texture_rotation_1);
	texture_2_uv = rotate_uv(texture2uv(texture_2, world_uv),texture_rotation_2);
	texture_3_uv = rotate_uv(texture2uv(texture_3, world_uv),texture_rotation_3);
	texture_4_uv = rotate_uv(texture2uv(texture_4, world_uv),texture_rotation_4);
}


float max4(float v1, float v2, float v3, float v4)
{
	return max(max(v1, v2), max(v3, v4));
}

vec3 blend(vec3 t1, float h1, vec3 t2, float h2, vec3 t3, float h3, vec3 t4, float h4)
{
	float height_start = max4(h1, h2, h3, h4) - blend_step;
	float s1 = max(h1 - height_start, 0);
	float s2 = max(h2 - height_start, 0);
	float s3 = max(h3 - height_start, 0);
	float s4 = max(h4 - height_start, 0);
	float splat_sum = s1 + s2 + s3 + s4;
	return ((t1 * s1) + (t2 * s2) + (t3 * s3) + (t4 * s4)) / splat_sum;
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
	vec4 s = texture(splat, world_uv / map_size);
	vec4 t1 = get_coloured_texture(texture_1, texture_1_uv, tint_colour_1, apply_gradient_1, 0, flip_x_1, flip_y_1);
	vec4 t2 = get_coloured_texture(texture_2, texture_2_uv, tint_colour_2, apply_gradient_2, 1, flip_x_2, flip_y_2);
	vec4 t3 = get_coloured_texture(texture_3, texture_3_uv, tint_colour_3, apply_gradient_3, 2, flip_x_3, flip_y_3);
	vec4 t4 = get_coloured_texture(texture_4, texture_4_uv, tint_colour_4, apply_gradient_4, 3, flip_x_4, flip_y_4);
	vec3 albedo = t1.rgb * s.r + t2.rgb * s.g + t3.rgb * s.b + t4.rgb * s.a;

	COLOR.rgb = albedo;
}