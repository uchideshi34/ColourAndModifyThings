shader_type canvas_item; // version 1.0.2

uniform float min_gray = 0.0; // Adjusts the darkest level
uniform float max_gray = 1.0; // Ensures brightest point is white
uniform bool apply_grayscale = false; // Boolean to determine if we should try and apply grayscale or gradient to the asset
uniform float saturation = 1.0; // saturation change
uniform bool apply_saturation = false; // Boolean to determine if we should try and apply a saturation change

uniform sampler2D gradient_tex; // Holds the gradient
uniform bool apply_gradient = false; // Defines whether this is a gradient or not

uniform sampler2D pattern_tex; // Holds the main pattern texture. Needed for patterns only.
uniform float texture_rotation; // For patterns, this is the rotation factor
uniform bool is_pattern = false; // If the shader is being applied to a pattern
varying vec2 world_uv; // required for calculating the uv as the UV is not available

uniform bool is_colourable = false; // If the asset has defined colourable pixels

uniform float min_redness = 0.1; // values from asset packs
uniform float red_tolerance = 0.04; // values from asset packs
uniform float min_saturation = 0.0; // values from asset packs

uniform bool is_path = false; // boolean for whether this applies to a path
uniform float start_point = 0.0; // Adjusts the start_point
uniform bool FadeIn = false; // is fade in enabled
uniform bool FadeOut = false; // is fade out enabled
uniform float path_length_in_uv = 1.0; // path length in uv, ie actual length / texture length
uniform bool path_flip_vertical = false; // boolean whether to flip the texture of the path in the vertical
uniform float fade_distance = 10.0; // path length in uv, ie actual length / texture length

// Pattern vertices variables
uniform sampler2D vectors; // sampler2d containing the vectors of the pattern vertices
uniform int vectorsTextureWidth; // width of the sampler2d containing the vertices
uniform int vectorsCount; // number of vertices contained in the sampler2d
varying vec2 relative_uv; // relative uv value from the world rect position, needed to align to the pattern vertices

// Pattern specific values related to pattern itself
uniform vec2 render_rect_position; // world rect position
uniform vec2 render_rect_size; // world rect size
uniform bool use_texture; // bool value on whether to use the actual pattern texture rather than a flat pattern

uniform int index_first_non_shadow;
uniform int index_last_non_shadow;

// edge blur values
uniform float blur_range; // range of the blur
uniform vec2 shadow_direction = vec2(0.0,0.0); // direction of the shadow
uniform float edge_softness : hint_range(0.0, 0.2) = 0.1;  // Controls smooth corner rounding
uniform bool has_edge_blur = false;
uniform bool reverse_alpha = false;


vec2 offset_start_x_uv(vec2 uv, float start) { // offset the start of the texture for paths
	vec2 offset_uv;

	offset_uv.x = mod(uv.x + start_point,1.0);
	offset_uv.y = uv.y;

	return offset_uv;
}


// Algorithm to determine whether the colour of the pixel is sufficiently red to qualify as a colourable pixel. Lifted from 
bool is_red_enough(vec4 color)
{
	bool is_red = abs(color.g - color.b) <= red_tolerance;
	bool is_within_saturation = 1.0 - ((color.g + color.b) * 0.5) >= min_saturation;
	float redness = color.r - (color.g + color.b) * 0.5;

	// colors
	if (is_red && is_within_saturation && redness > min_redness)
	{
		return true;
	}
	else
	{
		return false;
	}
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

float posmod(float x, float y) { // posmod function
	return mod(mod(x, y) + y, y);
}


// Use the vertex function to calculate the world uv. This is taken from the official DD pattern shader

void vertex() {
	relative_uv = (VERTEX - render_rect_position);

    world_uv = VERTEX;
    ivec2 size = textureSize(pattern_tex, 0);
    world_uv.x /= float(size.x);
    world_uv.y /= float(size.y);
    world_uv = rotate_uv(world_uv, texture_rotation);

}

// EDGE BLUR PATTERNS FUNCTIONS
float smin(float a, float b, float k) { // smoothing function for blurrring
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

float edge_sdf(vec2 p, vec2 a, vec2 b) { // function to find the distance from the edge
    vec2 ab = b - a;
    vec2 ap = p - a;
	if (dot(ab, ab) > 0.0) {
		float t = clamp(dot(ap, ab) / dot(ab, ab), 0.0, 1.0);
    	vec2 closest = a + t * ab;
    	return length(p - closest);
	}
	else {
		return length(p - a);
	}
}

vec2 get_vector_entry(int i) { // function to retrieve the pattern edge value from the sampler2d

	ivec2 coord;

	coord.x = i % vectorsTextureWidth;
	coord.y = i / vectorsTextureWidth;
	vec4 tex = texelFetch(vectors, coord, 0);
	return tex.xy * 10000.0; // note we have multiplied the vector value by 0.0001 to ensure it is within 0-1
}

float polygon_sdf(vec2 p) { // function to find the nearest distance to the edge but smoothed if needed or nulled if it is on an edge
    float min_dist = 1e6;
	vec2 a = vec2(0.0);
	vec2 b = vec2(0.0);

	if (length(shadow_direction) < 0.05) // If there is no shadow direction set
	{
		for(int i=0; i<vectorsCount; ++i) {

			a = get_vector_entry(i);
			b = get_vector_entry((i + 1) % vectorsCount);
			min_dist = smin(min_dist, edge_sdf(p, a, b), edge_softness * min (render_rect_size.x,render_rect_size.y));
		}
	}
	else // Otherwise there is a shadow direction
	{

		// calculate all the min_dist values based on the remaining edges
		for(int i=0; i<vectorsCount; ++i) {

			if (index_first_non_shadow + i > index_last_non_shadow)
			{
				break;
			}

			a = get_vector_entry((index_first_non_shadow + i) % vectorsCount);
			b = get_vector_entry((index_first_non_shadow + i + 1) % vectorsCount);
			min_dist = smin(min_dist, edge_sdf(p, a, b), edge_softness * min (render_rect_size.x,render_rect_size.y));
		}
		
	}

    return min_dist;
}

void fragment()
{

	const float EPSILON = 0.0001; // value to avoid missing "=" value
	vec4 color = vec4(1.0);

	if (is_pattern) // If this is a pattern we need to use the pattern texture and the world_uv value
	{
		color = texture(pattern_tex, world_uv); // get the correct colour

		if (has_edge_blur) // if this shader should apply an edge blur
		{
			float dist = polygon_sdf(relative_uv);
			float scaled_blur = blur_range * 256.0;
			float alpha = 0.0;

			if (dist < 0.0) // error check for negative distances
			{
				alpha = 0.0;
			} 
			else
			{
				if (dist < scaled_blur) // if this is within the blur range
				{
					alpha = dist / scaled_blur; // set the alpha to the distance value
				}
				else // set the alpha to 1.0
				{
					alpha = 1.0;
				}
			}

			if (reverse_alpha) // if we want to reverse the alpha so it blurs from the edge to a transparent centre then
			{
				alpha = clamp(1.0 - alpha, 0.0, 1.0) // reverse the alpha value
			}
			
			if (use_texture) // if we want to use the underlying texture for the blur
			{
				color.a *= alpha; // scale the alpha value according to the alpha derived from the ditance
			}
			else // set the color to white but keep the underlying alpha. Note this means we need to use non-alpha 
			{
				color = vec4(vec3(1.0),color.a * alpha); 
			}	

		}
	}
	else // If this is not a pattern, we can just get the color from the standard TEXTURE and UV
	{
		if (is_path) // if this is a path then look for start point offsets and fade options
		{ 
			vec2 path_uv = UV; // set a specific uv for the path
			if (path_flip_vertical) // if flip vertical is set then
			{
				path_uv.y = clamp(1.0 - path_uv.y,0.0,1.0); // invert the y element of the uv
			}

			color = texture(TEXTURE, offset_start_x_uv(path_uv, start_point)); // get the colour point but offset from the start as per value
			if (path_length_in_uv > 0.0) // if the path length is greater than zero
			{
				float f_dist = 0.01 * fade_distance * path_length_in_uv;
				if (FadeIn && (path_uv.x < f_dist)) // if fade in is enabled then redude the opacity for the first 10% of the path
				{
					color.a *= mix(0.0, 1.0, float(clamp(path_uv.x / (0.01 * fade_distance * path_length_in_uv), 0.0, 1.0)))
				}
				if (FadeOut && (path_uv.x > path_length_in_uv - f_dist)) // if fade out then do it for the last 10% of the path
				{
					color.a *= mix(1.0, 0.0, float(clamp((path_uv.x - (path_length_in_uv - f_dist)) / f_dist, 0.0, 1.0)))
				}
			}
		}
		else // otherwise just get the standard colour position
		{
			color = texture(TEXTURE, UV); // get the standard colour
		}

	}

	if ((!is_colourable || (is_colourable && is_red_enough(color))) && apply_grayscale)  // If this is either not a colourable asset (in which case we recolour the whole thing) or if it is and the pixel qualifies as being colourable
	{

		float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114)); // Convert the color to grayscale

		if (is_colourable && is_red_enough(color)) { // for colourable assets we only have red and we want to use the brightness of that redness
			gray = color.r;
		}

		if(apply_gradient) // If we want a gradient colour applied
		{ 
			
			vec4 gradient_color = texture(gradient_tex, vec2(gray, 0.0)); // Sample the gradient texture using brightness of the texture as x (y must be 0 for a 1D gradient)

			COLOR = vec4(gradient_color.rgb, gradient_color.a * color.a); // Apply the resulting gradient colour noting that we also want to apply the gradient alpha as a multiplier
		}
		else // if this is not a gradient recolour then look at the gray values
		{
			if(min_gray >= max_gray - EPSILON && min_gray <= max_gray + EPSILON) // If the min and max are identical then just change the alpha level, i.e. this is set to white
			{
				COLOR = vec4(vec3(min_gray), color.a); // Ignore the brightness of the texture but use its alpha
			}
			else if(apply_saturation) // if we are applying a saturation factor
			{
				// Normalize grayscale to fit within min_gray and max_gray
				gray = clamp((gray - min_gray) / (max_gray - min_gray), 0.0, 1.0);
				vec3 saturation_color = mix(vec3(gray), color.rgb, saturation);
				COLOR = vec4(saturation_color, color.a);
				
			}
			else // If we have a non-zero range for gray values then normalise the texture brightness to that range
			{
				// Normalize grayscale to fit within min_gray and max_gray
				gray = clamp((gray - min_gray) / (max_gray - min_gray), 0.0, 1.0);
				COLOR = vec4(vec3(gray), color.a);
				
			}
		}
	}
	else
	{
		COLOR = color;
	}

}
