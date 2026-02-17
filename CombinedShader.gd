# CombinedShader v1.0.9
class_name CombinedShader

var customdatamanager = null

var universalshader = null
var colorable_hsl_shader = null  # Hybrid shader: DD CustomColors + HSL adjustments

var reference_to_script = null

const DEFAULT_HISTORY_RECORD = {"has_data": false, "previous_node_data": {}, "new_node_data": {}}
var history_record = {"has_data": false, "previous_node_data": {}, "new_node_data": {}}

const TYPE_LOOKUP = {"ObjectTool": "objects","ScatterTool": "objects", "PathTool": "paths", "PatternShapeTool": "pattern_shapes", "WallTool": "walls", "PortalTool": "portals"}

# Logging Functions
const ENABLE_LOGGING = false
var logging_level = 0

#########################################################################################################
##
## UTILITY FUNCTIONS
##
#########################################################################################################

func outputlog(msg,level=0):
	if ENABLE_LOGGING:
		if level <= logging_level:
			printraw("(%d) <CombinedShader>: " % OS.get_ticks_msec())
			print(msg)
	else:
		pass

# Function to see if a structure that looks like a copied dd data entry is the same
func is_the_same(a, b) -> bool:

	if a is Dictionary:
		if not b is Dictionary:
			return false
		if a.keys().size() != b.keys().size():
			return false
		for key in a.keys():
			if not b.has(key):
				return false
			if not is_the_same(a[key], b[key]):
				return false
	elif a is Array:
		if not b is Array:
			return false
		if a.size() != b.size():
			return false
		for _i in a.size():
			if not is_the_same(a[_i], b[_i]):
				return false
	elif a != b:
		return false

	return true


# Function to initialise 
func _init():

	pass

# Build a hybrid shader that combines DD's CustomColors.shader with HSL adjustments.
# This preserves DD's exact colorable rendering while adding our HSL controls on top.
func build_colorable_hsl_shader():

	outputlog("build_colorable_hsl_shader", 0)

	# Load the DD CustomColors shader and read its source code
	var dd_shader = ResourceLoader.load("res://shaders/CustomColors.shader", "Shader", true)
	if dd_shader == null:
		outputlog("ERROR: Could not load CustomColors.shader", 0)
		return

	var dd_code = dd_shader.code
	if dd_code == null or dd_code == "":
		outputlog("ERROR: CustomColors.shader has no code", 0)
		return

	outputlog("DD CustomColors shader code length: " + str(dd_code.length()), 0)

	# Define the HSL uniforms we need to inject
	var hsl_uniforms = """
// --- ColourThings HSL uniforms ---
uniform float saturation = 1.0;
uniform float hue_shift = 0.0;
uniform float lightness = 0.0;
uniform float contrast = 0.0;
uniform bool invert = false;
uniform bool apply_hsl = false;
uniform float sat_blacks = 0.0;
uniform float sat_midtones = 1.0;
uniform float sat_whites = 1.0;
uniform float sat_out_blacks = 0.0;
uniform float sat_out_whites = 1.0;
uniform bool protect_hue = true;
uniform bool protect_sat = true;
uniform bool protect_light = true;
"""

	# Define the HSL processing functions
	var hsl_functions = """
// --- ColourThings HSL functions ---
vec3 ct_rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 ct_hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
"""

	# Define the HSL post-processing code to inject before the final COLOR assignment
	var hsl_postprocess = """
	// --- ColourThings HSL post-processing ---
	if (apply_hsl) {
		vec3 hsl_color = COLOR.rgb;
		float hsl_alpha = COLOR.a;

		// Re-read original texture to detect colorable pixels using DD's exact logic
		vec4 ct_orig = texture(TEXTURE, UV);
		bool ct_is_red = abs(ct_orig.g - ct_orig.b) <= red_tolerance;
		bool ct_is_within_sat = 1.0 - ((ct_orig.g + ct_orig.b) * 0.5) >= min_saturation;
		float ct_redness = ct_orig.r - (ct_orig.g + ct_orig.b) * 0.5;
		bool ct_is_colorable = ct_is_red && ct_is_within_sat && ct_redness > min_redness;

		// Apply saturation adjustment - skip colorable pixels if protected
		if (!(ct_is_colorable && protect_sat) && abs(saturation - 1.0) > 0.001) {
			float gray = dot(hsl_color, vec3(0.299, 0.587, 0.114));
			hsl_color = mix(vec3(gray), hsl_color, saturation);
		}

		// Apply hue shift - skip colorable pixels if protected
		if (!(ct_is_colorable && protect_hue) && abs(hue_shift) > 0.001) {
			vec3 hsv = ct_rgb2hsv(hsl_color);
			hsv.x = fract(hsv.x + hue_shift * 0.5);
			hsl_color = ct_hsv2rgb(hsv);
		}

		// Apply lightness - skip colorable pixels if protected
		if (!(ct_is_colorable && protect_light) && abs(lightness) > 0.001) {
			if (lightness > 0.0) {
				hsl_color = mix(hsl_color, vec3(1.0), lightness);
			} else {
				hsl_color = mix(hsl_color, vec3(0.0), -lightness);
			}
		}

		// Apply contrast
		if (abs(contrast) > 0.001) {
			if (contrast > 0.0) {
				float contrast_factor = 1.0 + contrast * 2.0;
				hsl_color = clamp((hsl_color - vec3(0.5)) * contrast_factor + vec3(0.5), 0.0, 1.0);
			} else {
				hsl_color = mix(hsl_color, vec3(0.5), -contrast);
			}
		}

		// Apply Input Levels
		float ct_range = max(sat_whites - sat_blacks, 0.001);
		hsl_color = clamp((hsl_color - vec3(sat_blacks)) / ct_range, 0.0, 1.0);

		// Apply gamma
		hsl_color = pow(hsl_color, vec3(1.0 / sat_midtones));

		// Apply Output Levels
		hsl_color = mix(vec3(sat_out_blacks), vec3(sat_out_whites), hsl_color);

		// Apply invert
		if (invert) {
			hsl_color = vec3(1.0) - hsl_color;
		}

		COLOR = vec4(hsl_color, hsl_alpha);
	}
"""

	# Now inject our code into the DD shader code
	var new_code = dd_code

	# Step 1: Inject uniforms after the first uniform block or after shader_type
	# Find the position after "shader_type canvas_item;" line
	var shader_type_end = new_code.find(";")
	if shader_type_end >= 0:
		new_code = new_code.insert(shader_type_end + 1, "\n" + hsl_uniforms)

	# Step 2: Inject HSL functions before void fragment()
	var fragment_pos = new_code.find("void fragment()")
	if fragment_pos < 0:
		fragment_pos = new_code.find("void fragment ()")
	if fragment_pos >= 0:
		new_code = new_code.insert(fragment_pos, hsl_functions + "\n")

	# Step 3: Inject HSL post-processing before the closing brace of fragment()
	# Find the last closing brace which should be the end of fragment()
	var last_brace = new_code.rfind("}")
	if last_brace >= 0:
		new_code = new_code.insert(last_brace, "\n" + hsl_postprocess + "\n")

	# Create the hybrid shader
	colorable_hsl_shader = Shader.new()
	colorable_hsl_shader.code = new_code

	outputlog("build_colorable_hsl_shader: complete, code length: " + str(new_code.length()), 0)

# Function to get the texture of a node based on tool_type
func get_asset_texture(node, tool_type: String):
	var texture = null

	match tool_type:
		"ObjectTool","ScatterTool","WallTool","PortalTool","objects","portals","walls":
			texture = node.Texture
		"PathTool", "LightTool","paths","lights":
			texture = node.get_texture()
		"PatternShapeTool","pattern_shapes":
			texture = node._Texture
		"RoofTool","roofs":
			texture = node.TilesTexture
		_:
			return null

	return texture


# Function to look at a node and determine what type it is based on its properties
func get_node_type(node):

	if node.get("WallID") != null:
		return "portals"

	# Note this is also true of portals but we caught those with WallID
	elif node.get("Sprite") != null:
		return "objects"
	elif node.get("FadeIn") != null:
		return "paths"
	elif node.get("HasOutline") != null:
		return "pattern_shapes"
	elif node.get("Joint") != null:
		return "walls"

	return null

#########################################################################################################
##
## CORE CUSTOM ATTRIBUTE FUNCTIONS
##
#########################################################################################################

# Merges the provisioned data with any stored data, noting that the new data takes priority
func merge_new_custom_attributes_with_stored_values(node: Node2D, new_config: Dictionary):

	var config = customdatamanager.DEFAULT_COMBINED_DATA.duplicate(true)

	# If this is a placed node
	if node.has_meta("node_id"):
		# Check if there is stored data for this node
		if customdatamanager.has_data(node.get_meta("node_id")):
			# Get that config if so
			config = customdatamanager.get_data(node.get_meta("node_id"))

	# Overwrite any values with the new values
	config = customdatamanager.merge_dict(config,new_config)

	# If there isn't a type defined then define one based on the node
	config["type"] = get_node_type(node)
	
	return config

# Function to take a set of custom config values and apply them to a node
func set_custom_attributes_on_node(node: Node2D, new_config: Dictionary):

	outputlog("set_custom_attributes_on_node: " + str(new_config),2)

	# For patterns: save and restore the original DD color
	if new_config.has("type") and new_config["type"] == "pattern_shapes":
		var current_texture_path = ""
		if node._Texture != null:
			current_texture_path = node._Texture.resource_path
		
		# Check if the texture has changed since we saved the original color
		if node.has_meta("original_dd_texture"):
			var saved_texture_path = node.get_meta("original_dd_texture")
			if saved_texture_path != current_texture_path:
				# Texture changed, remove old original_dd_color
				node.remove_meta("original_dd_color")
				node.remove_meta("original_dd_texture")
		
		# Restore original_dd_color: prefer saved config data, then node meta, then current node color
		if not node.has_meta("original_dd_color"):
			# First check if we have it persisted in the config (survives save/load)
			if new_config.has("original_dd_color") and new_config["original_dd_color"] != "" and new_config["original_dd_color"] != "ffffffff":
				node.set_meta("original_dd_color", new_config["original_dd_color"])
				node.set_meta("original_dd_texture", current_texture_path)
			else:
				# Read from the node's current state (first time setup)
				var pattern_save = node.Save(true)
				if pattern_save.has("color"):
					var saved_color = pattern_save["color"]
					# Only save if the color is not white (white means DD already has the mod-modified value)
					if saved_color != "ffffffff":
						node.set_meta("original_dd_color", saved_color)
						node.set_meta("original_dd_texture", current_texture_path)
		
		# Always persist original_dd_color into the config so it survives save/load
		if node.has_meta("original_dd_color"):
			new_config["original_dd_color"] = node.get_meta("original_dd_color")

	# For walls: save the original DD color using node meta
	if new_config.has("type") and new_config["type"] == "walls":
		if not node.has_meta("original_dd_color"):
			var wall_color = node.Color
			if wall_color != null:
				node.set_meta("original_dd_color", wall_color.to_html())
		else:
			pass

	# Make new shader
	var shader_material = ShaderMaterial.new()
	var apply_shader = false

	if new_config["type"] != get_node_type(node):
		outputlog("config type: " + str(new_config["type"]) + " does not match node type: " + str(get_node_type(node)),2)
		return

	# Look at the stored config and merge with any stored versions
	var config = merge_new_custom_attributes_with_stored_values(node, new_config)

	# Set up the boolean type identifiers
	shader_material = update_shader_material_with_bool_types(shader_material, config)

	# Update for colour config values
	if config["shader_type"] != "none":
		# As we are colouring something we should always apply grayscale here as shader_type != "none"
		shader_material.set_shader_param("apply_grayscale", true)
		shader_material = update_shader_material_with_colour_config(node, shader_material, config)
		apply_shader = true
		# Add business logic that removes custom coloured objects that are non-gradient values, noting we have already updated the shader material
		# But now we allow saturation mode for colorable objects too
		if config["type"] == "objects" && config["shader_type"] != "gradient" && config["shader_type"] != "saturation":
			if node.HasCustomColor():
				apply_shader = false
	else:
		# As we are not colouring something we should not apply grayscale here
		shader_material.set_shader_param("apply_grayscale", false)
	
	# If this is a path then look for path specific values for start points
	if config["type"] == "paths":
		shader_material = update_shader_material_with_start_point(node, shader_material, config)
		shader_material = update_shader_material_with_flip_vertical(node, shader_material, config)
		shader_material = apply_fade_ends_to_path(node, shader_material, config)
		# Check start point noting that that fade ends is not required to be checked as it is required by other drivers only
		if config["start_point"] > 0.0005 || config["path_flip_vertical"] || not is_equal_approx(config["fade_distance"],10.0):
			apply_shader = true

	# If this is a pattern with an edge blur
	if config["type"] == "pattern_shapes" && config["has_edge_blur"]:
		# If we have a shadow direction, then update the config with the derived values
		if config["shadow_direction"] != [0,0]:
			config = update_config_with_shadow_direction_values(node, config)
		
		shader_material = update_shader_material_with_blur_edge(node, shader_material, config)
		apply_shader = true

	# Set the shader and material correctly
	# For colorable objects in saturation mode: use the hybrid DD+HSL shader
	# This preserves DD's exact colorable rendering while adding HSL on top
	var use_colorable_hsl = false
	if config["type"] == "objects" and config["shader_type"] == "saturation" and node.HasCustomColor() and colorable_hsl_shader != null:
		use_colorable_hsl = true
		# Create a new shader material based on the hybrid shader
		var colorable_material = ShaderMaterial.new()
		colorable_material.shader = colorable_hsl_shader
		# Set the DD custom color param
		var custom_color = null
		if config.has("colorable_custom_color") and config["colorable_custom_color"] != null:
			custom_color = Color(config["colorable_custom_color"])
		else:
			custom_color = node.GetCustomColor()
		if custom_color != null:
			colorable_material.set_shader_param("tint_r", custom_color)
		# Set the HSL params
		colorable_material.set_shader_param("apply_hsl", true)
		if config.has("saturation"):
			colorable_material.set_shader_param("saturation", config["saturation"])
		if config.has("hue_shift"):
			colorable_material.set_shader_param("hue_shift", config["hue_shift"])
		if config.has("lightness"):
			colorable_material.set_shader_param("lightness", config["lightness"])
		if config.has("contrast"):
			colorable_material.set_shader_param("contrast", config["contrast"])
		if config.has("invert"):
			colorable_material.set_shader_param("invert", config["invert"])
		if config.has("sat_levels"):
			colorable_material.set_shader_param("sat_blacks", config["sat_levels"]["blacks"])
			colorable_material.set_shader_param("sat_midtones", config["sat_levels"]["midtones"])
			colorable_material.set_shader_param("sat_whites", config["sat_levels"]["whites"])
		if config.has("sat_output_levels"):
			colorable_material.set_shader_param("sat_out_blacks", config["sat_output_levels"]["out_blacks"])
			colorable_material.set_shader_param("sat_out_whites", config["sat_output_levels"]["out_whites"])
		# Set colorable protection params (default to true = protected)
		if config.has("colorable_protect"):
			colorable_material.set_shader_param("protect_hue", config["colorable_protect"]["hue"])
			colorable_material.set_shader_param("protect_sat", config["colorable_protect"]["saturation"])
			colorable_material.set_shader_param("protect_light", config["colorable_protect"]["lightness"])
		# Apply directly to node's Sprite
		node.Sprite.material = colorable_material
		# Apply modulate values (no shader pass-through needed)
		set_custom_modulate(node, config, false)
		outputlog("set_custom_attributes_on_node: applied colorable HSL hybrid shader", 2)
		return

	shader_material.shader = universalshader

	# Apply modulate values
	set_custom_modulate(node, config, apply_shader)

	# Apply the shader material to the node
	if apply_shader:
		apply_shader_material_to_node(node, shader_material, config["type"])
	else:
		outputlog("No shader parameters set so universal shader not applied",2)
		# Check if the node is using the universal shader then and reset it
		if is_node_using_universal_shader(node):
			# Reset the node material
			reset_node_material(node)

	outputlog("set_custom_attributes_on_node: complete",2)

# Function to update the shader material with the right booleans for type
func update_shader_material_with_bool_types(shader_material, config):

	outputlog("update_shader_material_with_bool_types",2)

	match config["type"]:
		"paths":
			shader_material.set_shader_param("is_path", true)
		"pattern_shapes":
			shader_material.set_shader_param("is_pattern", true)

	return shader_material

# Function to attach the shader material to the correct part of the node
func apply_shader_material_to_node(node, shader_material: ShaderMaterial, type: String):

	outputlog("apply_shader_material_to_node: " + str(type),2)

	var node_to_shade = get_node_to_shade(node, type)

	# For walls we need to apply the shader to each of the line2d and each of the wall ends
	if type == "walls":
		# Look at each line in the lines property
		for line in node.lines:
			# Set the material appropriately
			line.material = shader_material
			# For each line, look for their children which includes the wall ends as sprites
			for wall_end in line.get_children():
				# Check that this is a Sprite not a LightOccluder
				if wall_end is Sprite:
					# Set the material
					wall_end.material = shader_material
	# Otherwise apply the shader to the node_to_shade
	else:
		if node_to_shade != null:
			node_to_shade.material = shader_material


# Make an array of colours where red is x, green is y and their values are normalised by the bounds of the patternshape
func make_relative_color_array_from_polygon(polygon: Array, position: Vector2):

	var colours = []

	# For each point entry
	for point in polygon:
		# Note we are multiplying the color value by 0.0001 in order to try and keep it in the range 0.0 to 1.0 although this may not be necessary
		colours.append(Color(0.0001 * (point.x - position.x), 0.0001 * (point.y - position.y) ,0.0,1.0))
		
	return colours

# vectors is array of Color objects
func make_vector2_storage_texture(width, colors: Array): 
	var w = width
	var h = max(w, int( floor(colors.size() / w)) + 1)
	var img = Image.new()
	img.create(w, h, false, Image.FORMAT_RGBAF)
		
	# put data into image
	img.lock()
	var x: int
	var y: int
	for i in range(colors.size()):
		y = i / w
		x = i % w
		img.set_pixel(x, y, colors[i])
	img.unlock()
			
	var tex = ImageTexture.new()
	tex.create_from_image(img)
	return tex

func get_node_to_shade(node: Node2D, type: String):

	var node_to_shade

	match type:
		"paths","pattern_shapes":
			node_to_shade = node
		"objects", "portals":
			node_to_shade = node.Sprite
		# Walls is a special case dealt with below
		"walls":
			node_to_shade = null
		_:
			return null
	
	return node_to_shade

#########################################################################################################
##
## SET MODULATE FUNCTIONS
##
#########################################################################################################

# Function to set the modulate value on the node
func set_custom_modulate(node: Node2D, config: Dictionary, apply_shader: bool):

	outputlog("set_custom_modulate: " + str(config),2)

	# Check if it has a type before using it
	if not config.has("type"):
		return
	
	# Get opacity from config (default to colour alpha, then 1.0)
	var opacity = 1.0
	if config.has("opacity"):
		opacity = config["opacity"]
	elif config.has("colour"):
		opacity = Color(config["colour"]).a
	
	# Set the tint colour if we are using the tint colour
	match config["type"]:
		"objects", "paths", "portals":
			# For colorable objects, don't apply tint colour via modulate - DD's shader handles the custom color
			# But always apply opacity via the alpha channel
			if config["type"] == "objects" and node.HasCustomColor():
				node.set_modulate(Color(1, 1, 1, opacity))
			else:
				var mod_color = Color(config["colour"])
				mod_color.a = opacity
				node.set_modulate(mod_color)
		"pattern_shapes":
			var node_id = node.get_meta("node_id")
			
			# Determine which color to use:
			# - If user changed the DD color (not white), use that
			# - Otherwise use the original_dd_color
			var base_color = Color(config["colour"])
			var use_original = false
			
			# If the config color is white or nearly white, use original instead
			if base_color.r > 0.99 and base_color.g > 0.99 and base_color.b > 0.99:
				if node.has_meta("original_dd_color"):
					base_color = Color(node.get_meta("original_dd_color"))
					use_original = true
			
			
			# If we are using the universal shader then we use the modulate value to change the pattern
			if apply_shader:
				# If this is a tile type, strange things are happening with DD resetting the default color values so just set the colour to white and accept that tileset can't have gradients and colours
				if is_tile_pattern(node):
					var mod_color = Color.white
					mod_color.a = opacity
					node.set_modulate(mod_color)
					node.SetOptions(node._Texture, Color.white, node._Rotation)
				else:
					# Use base_color with opacity
					var pattern_color = base_color
					pattern_color.a = opacity
					node.SetOptions(node._Texture, pattern_color, node._Rotation)
					node.set_modulate(pattern_color)
			# If we are relying on the default DD pattern shader then it takes the colour value into that shader so we want the modulate as white but preserve opacity
			else:
				var mod_color = Color.white
				mod_color.a = opacity
				node.set_modulate(mod_color)
				# DD should take care of this but the timing may not work, so force it
				var pattern_color = base_color
				pattern_color.a = opacity
				node.SetOptions(node._Texture, pattern_color, node._Rotation)
		"walls":
			# Determine which color to use for walls
			var wall_base_color = Color(config["colour"])
			
			# If the config color is white or nearly white, use original instead
			if wall_base_color.r > 0.99 and wall_base_color.g > 0.99 and wall_base_color.b > 0.99:
				if node.has_meta("original_dd_color"):
					wall_base_color = Color(node.get_meta("original_dd_color"))
			
			# Apply opacity
			wall_base_color.a = opacity
			node.SetColor(wall_base_color)
			node.set_modulate(Color(1, 1, 1, opacity))

# Is this is a tile pattern
func is_tile_pattern(node: Node2D) -> bool:

	outputlog("is_tile_pattern: " + str(node),2)

	if get_node_type(node) != "pattern_shapes": return false

	var texture = get_asset_texture(node, "pattern_shapes")
	if texture == null: return false

	var texture_path = texture.resource_path
	outputlog("texture_path: " + str(texture_path),2)

	if "/tilesets/" in texture_path:
		return true
	return false

# Is this a colorable pattern (patterns in /textures/patterns/colorable/ or tilesets with custom_color type)
func is_colorable_pattern(node: Node2D) -> bool:

	outputlog("is_colorable_pattern: " + str(node),2)

	if get_node_type(node) != "pattern_shapes": return false

	var texture = get_asset_texture(node, "pattern_shapes")
	if texture == null: return false

	var texture_path = texture.resource_path

	# Check if in colorable patterns folder
	if "/colorable/" in texture_path:
		return true
	
	# Check if the pattern has a method or property indicating it's colorable
	# Try to check if node has HasCustomColor like objects do
	if node.has_method("HasCustomColor"):
		var has_custom = node.HasCustomColor()
		if has_custom:
			return true
	
	# Check the Save() data for type info
	var pattern_save = node.Save(true)
	if pattern_save.has("type"):
		pass
	
	# Check for known colorable tilesets by path
	var colorable_tilesets = [
		"tileset_wood_damaged.png",
		"tileset_ornate.png",
		"tileset_diamond_2.png",
		"tileset_diamond.png"
	]
	for tileset in colorable_tilesets:
		if tileset in texture_path:
			return true
	
	return false

#########################################################################################################
##
## COLOUR NODE SHADER MATERIAL FUNCTIONS
##
#########################################################################################################

# Function to convert a node 2d colour to grayscale
func update_shader_material_with_colour_config(node, shader_material: ShaderMaterial, colour_config: Dictionary):

	outputlog("update_shader_material_with_colour_config: " + str(colour_config),2)

	shader_material.set_shader_param("is_pattern", false)
	
	
	if colour_config["type"] == "objects":
		if node.HasCustomColor():
			# Check the existence of the red_config (which should always exist) and default if it doesn't
			if not colour_config.has("red_config"):
				outputlog("no red config found",2)
				colour_config["red_config"] = {"min_redness":0.1, "red_tolerance": 0.04, "min_saturation": 0.0}
			outputlog("red_config: " + str(colour_config["red_config"]),2)
			shader_material.set_shader_param("is_colourable", true)
			shader_material.set_shader_param("min_redness", colour_config["red_config"]["min_redness"])
			shader_material.set_shader_param("red_tolerance", colour_config["red_config"]["red_tolerance"])	
			shader_material.set_shader_param("min_saturation", colour_config["red_config"]["min_saturation"])
			# Pass the custom color as base_color for colorable objects
			# Prefer the color from UI (colorable_custom_color) for real-time preview
			var custom_color = null
			if colour_config.has("colorable_custom_color") and colour_config["colorable_custom_color"] != null:
				custom_color = Color(colour_config["colorable_custom_color"])
			else:
				custom_color = node.GetCustomColor()
			if custom_color != null:
				shader_material.set_shader_param("base_color", custom_color)
				shader_material.set_shader_param("apply_base_color", true)
	
	# Look at the colour config type
	match colour_config["shader_type"]:
		"normalised":
			# If the colour config has custom levels defined
			if colour_config.has("levels"):
				shader_material.set_shader_param("min_gray",  colour_config["levels"][0])
				shader_material.set_shader_param("max_gray",  colour_config["levels"][2])
			
		"white":
			shader_material.set_shader_param("min_gray", 1.0)
			shader_material.set_shader_param("max_gray", 1.0)
		"gradient":
			var gradient_texture: GradientTexture
			gradient_texture = create_gradient_texture(colour_config["gradient"])
			if gradient_texture != null:
				shader_material.set_shader_param("gradient_tex", gradient_texture)
				shader_material.set_shader_param("apply_gradient", true)
			else:
				return null
		"saturation":
			if colour_config.has("saturation"):
				outputlog("saturation applied",2)
				shader_material.set_shader_param("saturation", colour_config["saturation"])
				shader_material.set_shader_param("apply_saturation", true)
			if colour_config.has("hue_shift"):
				outputlog("hue_shift applied: " + str(colour_config["hue_shift"]),2)
				shader_material.set_shader_param("hue_shift", colour_config["hue_shift"])
			if colour_config.has("lightness"):
				outputlog("lightness applied: " + str(colour_config["lightness"]),2)
				shader_material.set_shader_param("lightness", colour_config["lightness"])
			if colour_config.has("contrast"):
				outputlog("contrast applied: " + str(colour_config["contrast"]),2)
				shader_material.set_shader_param("contrast", colour_config["contrast"])
			if colour_config.has("invert"):
				outputlog("invert applied: " + str(colour_config["invert"]),2)
				shader_material.set_shader_param("invert", colour_config["invert"])
			if colour_config.has("sat_levels"):
				outputlog("sat_levels applied: " + str(colour_config["sat_levels"]),2)
				shader_material.set_shader_param("sat_blacks", colour_config["sat_levels"]["blacks"])
				shader_material.set_shader_param("sat_midtones", colour_config["sat_levels"]["midtones"])
				shader_material.set_shader_param("sat_whites", colour_config["sat_levels"]["whites"])
			if colour_config.has("sat_output_levels"):
				outputlog("sat_output_levels applied: " + str(colour_config["sat_output_levels"]),2)
				shader_material.set_shader_param("sat_out_blacks", colour_config["sat_output_levels"]["out_blacks"])
				shader_material.set_shader_param("sat_out_whites", colour_config["sat_output_levels"]["out_whites"])
			# For patterns, pass the base color to shader
			if colour_config["type"] == "pattern_shapes":
				var base_color = Color(colour_config["colour"])
				# If config color is white, use original_dd_color instead
				if base_color.r > 0.99 and base_color.g > 0.99 and base_color.b > 0.99:
					if node.has_meta("original_dd_color"):
						base_color = Color(node.get_meta("original_dd_color"))
				# Only apply base_color if it's not white
				if not (base_color.r > 0.99 and base_color.g > 0.99 and base_color.b > 0.99):
					shader_material.set_shader_param("base_color", base_color)
					shader_material.set_shader_param("apply_base_color", true)
			# For walls, pass the base color to shader
			if colour_config["type"] == "walls":
				var base_color = Color(colour_config["colour"])
				# If config color is white, use original_dd_color instead
				if base_color.r > 0.99 and base_color.g > 0.99 and base_color.b > 0.99:
					if node.has_meta("original_dd_color"):
						base_color = Color(node.get_meta("original_dd_color"))
				# Only apply base_color if it's not white
				if not (base_color.r > 0.99 and base_color.g > 0.99 and base_color.b > 0.99):
					shader_material.set_shader_param("base_color", base_color)
					shader_material.set_shader_param("apply_base_color", true)
	
	# If this is a pattern then set the pattern specific values
	if colour_config["type"] == "pattern_shapes":
		var texture = get_asset_texture(node, colour_config["type"])
		if texture != null:
			shader_material.set_shader_param("is_pattern", true)
			shader_material.set_shader_param("texture_rotation", node._Rotation)
			shader_material.set_shader_param("pattern_tex", texture)
			# Check if this is a colorable pattern
			if is_colorable_pattern(node):
				shader_material.set_shader_param("is_colourable", true)
				# Use default red config values for colorable patterns
				shader_material.set_shader_param("min_redness", 0.1)
				shader_material.set_shader_param("red_tolerance", 0.04)
				shader_material.set_shader_param("min_saturation", 0.0)
				# Pass colorable protection checkbox values (same logic as objects)
				if colour_config.has("colorable_protect"):
					shader_material.set_shader_param("protect_hue", colour_config["colorable_protect"]["hue"])
					shader_material.set_shader_param("protect_sat", colour_config["colorable_protect"]["saturation"])
					shader_material.set_shader_param("protect_light", colour_config["colorable_protect"]["lightness"])
		else:
			# Define some error state
			return null
	
	return shader_material

# Function to take a dictionary of gradient data in readable format and convert it a texture.
func create_gradient_texture(gradient_data: Dictionary):

	outputlog("create_gradient_texture: " + str(gradient_data),2)

	var gradient_texture = GradientTexture.new()
	var gradient = Gradient.new()

	if not gradient_data.has("colours") || not gradient_data.has("offsets"):
		return null
	if gradient_data["colours"].size() != gradient_data["offsets"].size():
		return null
	if gradient_data["colours"].size() < 2:
		return null

	# For each record in the data
	for _i in gradient_data["colours"].size():
		# Replace the first two points as we always have two
		if _i < 2:
			gradient.set_offset(_i, gradient_data["offsets"][_i])
			gradient.set_color(_i, Color(gradient_data["colours"][_i]))
		# Otherwise add points
		else:
			gradient.add_point(gradient_data["offsets"][_i], Color(gradient_data["colours"][_i]))

	gradient_texture.gradient = gradient

	outputlog("gradient_texture: " + str(gradient_texture),2)
	return gradient_texture

#########################################################################################################
##
## PATH SHADER MATERIAL FUNCTIONS
##
#########################################################################################################

# Function to update the shader material with the flip vertical state
func update_shader_material_with_flip_vertical(node, shader_material: ShaderMaterial, config: Dictionary):

	outputlog("update_shader_material_with_flip_vertical",2)

	# If there is no entry for flip vertical then return false
	if not config.has("path_flip_vertical"):
		shader_material.set_shader_param("path_flip_vertical", false)
	else:
		shader_material.set_shader_param("path_flip_vertical", config["path_flip_vertical"])
	
	return shader_material

# Function to apply the start point to the shader
func update_shader_material_with_start_point(node, shader_material: ShaderMaterial, start_point_config: Dictionary):

	outputlog("update_shader_material_with_start_point",2)

	# If the start point is near zero, then do nothing.
	if not start_point_config["start_point"] > 0.0005:
		return shader_material
	
	shader_material.set_shader_param("start_point", start_point_config["start_point"])
	return shader_material

# Find the length of the path - use direct legnth for the purposes of this
func find_path_length(path) -> float:
	var length = 0.0
	for _i in range(1,path.points.size(),1):
		length += path.points[_i].distance_to(path.points[_i-1])
	outputlog("find_path_length: " + str(length),2)
	return length

# Function to apply fade ends to a path's shader material
func apply_fade_ends_to_path(node, shader_material: ShaderMaterial, config: Dictionary):

	outputlog("apply_fade_ends_to_path: node.FadeIn: " + str(node.FadeIn) + " node.FadeOut: " + str(node.FadeOut),2)
	var texture = get_asset_texture(node, "paths")
	
	if node.FadeIn || node.FadeOut:
		shader_material.set_shader_param("FadeIn", node.FadeIn)
		shader_material.set_shader_param("FadeOut", node.FadeOut)
		# Find the length of the path in uv based on the actual world length and the texture width
		var path_length_in_uv = find_path_length(node) / texture.get_width()
		# Scale the path length according to the width scale of the path, i.e. take the actual width and divide by the texture width
		path_length_in_uv *= texture.get_height() / node.width
		shader_material.set_shader_param("path_length_in_uv", path_length_in_uv)
		if config.has("fade_distance"):
			shader_material.set_shader_param("fade_distance", config["fade_distance"])
		else:
			# Set the default value which is 10 rather than 0.1
			shader_material.set_shader_param("fade_distance", 10)


	return shader_material
	
#########################################################################################################
##
## EDGE BLUR SHADER MATERIAL FUNCTIONS
##
#########################################################################################################

# Apply the shader to the new polygon
func update_shader_material_with_blur_edge(node, shader_material: ShaderMaterial, edge_blur_config: Dictionary):

	outputlog("update_shader_material_with_blur_edge",2)

	var vectors_as_colours = make_relative_color_array_from_polygon(node.polygon, node.GlobalRect.position)
	var tex = make_vector2_storage_texture(64, vectors_as_colours)

	# If there is an shadow direction defined then
	if edge_blur_config.has("shadow_direction"):
		if edge_blur_config["shadow_direction"] != [0,0]:
			# Update all the various shader parameters to make it work correctly
			if edge_blur_config.has("index_first_non_shadow"):
				shader_material.set_shader_param("index_first_non_shadow", edge_blur_config["index_first_non_shadow"])
			if edge_blur_config.has("index_last_non_shadow"):
				shader_material.set_shader_param("index_last_non_shadow", edge_blur_config["index_last_non_shadow"])
			shader_material.set_shader_param("has_shadow_direction", true)
		else:
			shader_material.set_shader_param("has_shadow_direction", false)
		shader_material.set_shader_param("shadow_direction", Vector2(edge_blur_config["shadow_direction"][0],edge_blur_config["shadow_direction"][1]))
	else:
		shader_material.set_shader_param("has_shadow_direction", false)

	shader_material.set_shader_param("render_rect_position", node.GlobalRect.position)
	shader_material.set_shader_param("render_rect_size", node.GlobalRect.size)
	shader_material.set_shader_param("vectors", tex)
	shader_material.set_shader_param("vectorsTextureWidth", 64)
	shader_material.set_shader_param("vectorsCount", vectors_as_colours.size())
	shader_material.set_shader_param("blur_range", edge_blur_config["blur_range"])
	shader_material.set_shader_param("edge_softness", edge_blur_config["smoothness"] * 0.01)
	shader_material.set_shader_param("use_texture", edge_blur_config["use_texture"])
	shader_material.set_shader_param("reverse_alpha", edge_blur_config["reverse_alpha"])
	shader_material.set_shader_param("texture_rotation", node._Rotation)
	
	shader_material.set_shader_param("pattern_tex", node._Texture)
	outputlog("pattern_tex: " + str(node._Texture),2)
	shader_material.set_shader_param("has_edge_blur", true)
	
	return shader_material


#########################################################################################################
##
## RESET SHADER FUNCTIONS
##
#########################################################################################################

# Function to reset the node to standard behaviour
func reset_node(node):

	node.set_modulate(Color.white)

	if is_node_using_universal_shader(node):
		reset_node_material(node)

# Function to reset the shader to the default
func reset_node_material(node):

	outputlog("reset_node_material",2)
	var type

	if node != null:
		match get_node_type(node):
			"paths","portals":
				node.material = null
			"walls":
				# Reset shader on all wall lines and their sprite children
				for line in node.lines:
					line.material = null
					for wall_end in line.get_children():
						if wall_end is Sprite:
							wall_end.material = null
			"pattern_shapes":
				node.material = ResourceLoader.load("res://materials/Pattern.material","ShaderMaterial",true)
				# Try to restore original_color from stored data
				var restore_color = Color.white
				var node_id = node.get_meta("node_id")
				# First try node meta (most reliable)
				if node.has_meta("original_dd_color"):
					restore_color = Color(node.get_meta("original_dd_color"))
					outputlog("Restored from node meta: " + str(restore_color), 2)
					# Remove the meta so next time we capture fresh color
					node.remove_meta("original_dd_color")
					if node.has_meta("original_dd_texture"):
						node.remove_meta("original_dd_texture")
				# Then try customdatamanager
				elif customdatamanager.has_data(node_id):
					var stored = customdatamanager.get_data(node_id)
					if stored.has("original_color") and stored["original_color"] != null:
						restore_color = Color(stored["original_color"])
					else:
						var pattern_save = node.Save(true)
						if pattern_save.has("color"):
							restore_color = Color(pattern_save["color"])
				else:
					var pattern_save = node.Save(true)
					if pattern_save.has("color"):
						restore_color = Color(pattern_save["color"])
				node.set_modulate(Color.white)
				node.SetOptions(node._Texture, restore_color, node._Rotation)
			"objects":
				if node.HasCustomColor():
					reset_colourable_object_node(node)
				else:
					node.Sprite.material = null
			"walls":
				# Restore original color if available
				var restore_color = Color.white
				if node.has_meta("original_dd_color"):
					restore_color = Color(node.get_meta("original_dd_color"))
					# Remove the meta so next time we capture fresh color
					node.remove_meta("original_dd_color")
				node.SetColor(restore_color)
				node.set_modulate(Color.white)
				# Null each line2d in the lines array
				for line in node.lines:
					line.material = ResourceLoader.load("res://materials/Wall.material","ShaderMaterial",true)
					for wall_end in line.get_children():
						if wall_end is Sprite:
							wall_end.material = null

# Function to try and reset a colourable object node
func reset_colourable_object_node(node):

	outputlog("reset_colourable_object_node",2)

	var shader_material = ShaderMaterial.new()

	shader_material.shader = ResourceLoader.load("res://shaders/CustomColors.shader","Shader",true)
	shader_material.set_shader_param("tint_r", node.GetCustomColor())
	node.Sprite.material = shader_material

# Function to check if the node is currently using a universal shader
func is_node_using_universal_shader(node) -> bool:

	outputlog("is_node_using_universal_shader",2)

	var current_shader = null

	if node != null:
		match get_node_type(node):
			"paths","portals","pattern_shapes":
				current_shader = node.material.shader 
			"objects":
				current_shader = node.Sprite.material.shader
			"walls":
				# Check the first line2d in the lines array
				for line in node.lines:
					if line.material != null:
						current_shader = line.material.shader
					break

	# Check if the current shader is the universal shader or the colorable HSL hybrid shader
	if current_shader == universalshader or current_shader == colorable_hsl_shader:
		outputlog("is_node_using_universal_shader: " +str(true),2)
		return true
	else:
		outputlog("is_node_using_universal_shader: " +str(false),2)
		return false 

# Function to reapply the data associated with a node on the map
func refresh_node(node: Node2D):

	outputlog("refresh_node: " + str(node),3)

	# Only take action if the node has data
	if customdatamanager.has_data(node.get_meta("node_id")):
		# Get the node's config data
		var config = customdatamanager.get_data(node.get_meta("node_id"))
		# Run the shader
		self.set_custom_attributes_on_node(node, config)

#########################################################################################################
##
## HISTORY FUNCTIONS
##
#########################################################################################################

# Find the width scale of a path
func find_path_width_scale(path) -> float:

	var path_dictionary: Dictionary
	var path_texture
	var texture_height

	if not customdatamanager.global.World.HasNodeID(path.get_meta("node_id")):
		return -1.0

	# Get the path metadata - surely there is a better way to do this
	path_dictionary = path.Save(true)
	path_texture = ResourceLoader.load(path_dictionary["texture"])
	texture_height = path_texture.get_height()

	return path_dictionary["width"] / texture_height

# Function to take a node id and store their current status so that we can create a before and after data record
func add_update_history_data(node_id: int, tool_type: String, config: Dictionary):

	outputlog("add_update_history_data",2)

	var data = {}

	history_record["has_data"] = true

	# If there is already a colour record then retrieve it
	if customdatamanager.has_data(node_id):
		# Get the current data config of the node
		data = customdatamanager.get_data(node_id)
	# If not make a default record
	else:
		data = customdatamanager.DEFAULT_COMBINED_DATA.duplicate(true)
		data["type"] = TYPE_LOOKUP[tool_type]
	
	# Add the path data as this might change with modify paths
	if data["type"] == "paths":
		var path = customdatamanager.global.World.GetNodeByID(node_id)
		data["path_data"] = {
			"widthscale": find_path_width_scale(path),
			"smoothness": path.Smoothness,
			"FadeIn": path.FadeIn,
			"FadeOut": path.FadeOut,
			"Grow": path.Grow,
			"Shrink": path.Shrink
		}

	# Add the node id reference to the history record
	var node_id_string = "node-id-" + str(node_id)
	# If there is no existing record for that node, then create a record, ie do not update if there is an existing record
	if not history_record["previous_node_data"].has(node_id_string):
		# Also capture the current DD custom color from the node for undo/redo
		if data["type"] == "objects":
			var node = customdatamanager.global.World.GetNodeByID(node_id)
			if node != null and node.has_method("HasCustomColor") and node.HasCustomColor():
				data["colorable_custom_color"] = node.GetCustomColor().to_html()
		history_record["previous_node_data"][node_id_string] = data.duplicate(true)

	config = customdatamanager.merge_dict(data,config)
	# Make the new node data record
	history_record["new_node_data"][node_id_string] = config.duplicate(true)
	history_record["new_node_data"][node_id_string]["type"] = TYPE_LOOKUP[tool_type]

# Function to reset the history data back to default values
func clear_history_data():

	history_record = DEFAULT_HISTORY_RECORD.duplicate(true)

# Finalize any pending history record if one exists. 
# Call this before starting a new type of change to ensure each change is a separate undo point.
func finalize_pending_history():
	if history_record["has_data"]:
		create_update_custom_history(0.0)

# Create custom history record, called when a colour preset is selected, the color picker is closed, or a slider timer finishes
func create_update_custom_history(delay_secs: float = 0.0):

	var record_script
	outputlog("create_update_custom_history",2)

	# If we need a short delay then implement it
	if delay_secs > 0.0:
		var timer = Timer.new()
		customdatamanager.global.Editor.get_node("Windows").add_child(timer)
		timer.autostart = false
		timer.one_shot = true
		# Wait a couple of seconds to ensure the palette presets list is updated.
		timer.start(delay_secs)
		yield(timer,"timeout")
		# Remove it
		customdatamanager.global.Editor.get_node("Windows").remove_child(timer)
		timer.queue_free()

	# If there is no data in the record dictionary, then do nothing. This might fired from the "main" location
	if not history_record["has_data"]:
		outputlog("no history data available",2)
		return

	# Check if the data record for new and old is the same in which case do nothing
	if is_the_same(history_record["previous_node_data"],history_record["new_node_data"]):
		outputlog("No history record created as no difference between old and new status",2)
		# As the data is invalid, clear the data
		clear_history_data()
		return
	
	# Check if there are the same number of records and that the node ids of those records match
	if not is_the_same(history_record["previous_node_data"].keys().sort(),history_record["new_node_data"].keys().sort()):
		outputlog("history record keys don't match",2)
		# As the data is invalid, clear the data
		clear_history_data()
		return

	# Create a new record if one is needed or simply update the existing one
	record_script = reference_to_script.InstanceReference("library/custom_history_record.gd")

	# If this is null for any reason then return to avoid a crash
	if record_script == null:
		outputlog("record_script is null",2)
		# As the data is invalid, clear the data
		clear_history_data()
		return

	record_script.combinedshader = self
	record_script.customdatamanager = customdatamanager
	record_script.previous_node_data = history_record["previous_node_data"].duplicate(true)
	record_script.new_node_data = history_record["new_node_data"].duplicate(true)

	outputlog("previous_node_data\n" + JSON.print(record_script.previous_node_data,"\t"),2)
	outputlog("new_node_data\n" + JSON.print(record_script.new_node_data,"\t"),2)

	# If this is a new action then create a new custom record
	var record = customdatamanager.global.Editor.History.CreateCustomRecord(record_script)

	# Reset the history record
	clear_history_data()

#########################################################################################################
##
## DIRECTIONAL SHADOW FUNCTIONS (NOT ACTIVE)
##
#########################################################################################################

# Function to add additional derived values for config
func update_config_with_shadow_direction_values(node: Node2D, config: Dictionary) -> Dictionary:

	outputlog("update_config_with_shadow_direction_values(): " + str(node),2)

	if get_node_type(node) != "pattern_shapes":
		return config

	# If we have a shadow direction then calculate the indexes of the first and last shadow points
	if config["shadow_direction"] != [0,0]:

		var indices = find_shadow_side_vertices(node.polygon, Vector2(config["shadow_direction"][0],config["shadow_direction"][1]))

		# Update all the various shader parameters to make it work correctly
		config["index_first_non_shadow"] = indices["index_first_non_shadow"]
		config["index_last_non_shadow"] = indices["index_last_non_shadow"]
	
	return config

# Find the edge furthest in the shadow direction
func find_furthest_shadow_edge(points: Array, shadow_direction: Vector2):

	outputlog("find_furthest_shadow_edge")

	var index = -1
	var projection
	var max_projection = 0.0
	var next
	var current

	for _i in points.size():
		current = points[ _i]
		next = points[( _i + 1) % points.size()]
		projection = (next - current).normalized().dot(shadow_direction)
		if projection > max_projection: 
			max_projection = projection
			index = _i
	outputlog("index: " + str(index),2)
	return index

# Find the index of the next point that is either type shadow_dir or not shadow_dir
func find_next_shadow_non_shadow_index(points: Array, shadow_direction: Vector2, start_index: int, dir: int):

	outputlog("find_next_shadow_non_shadow_index: dir: " + str(dir),2)

	var index = -1
	var next
	var current

	# Find the first non-shadow point
	for _i in points.size():
			
		index = (start_index + _i) % points.size()
		current = points[index]
		next = points[(index + 1) % points.size()]
		# If dir is negative this looks for the next shadow side edge otherwise it looks for the next non-shadow side
		if (next - current).normalized().dot(shadow_direction) < dir * 0.05:
			# If this is the first one or the right type, then return this one
			if index < 0:
				return index
	
	return index

# Find the shadow side vertices which are the furthers shadow direction edge and any shadow direction edges connected to it
func find_shadow_side_vertices(points: Array, shadow_direction: Vector2):

	outputlog("find_shadow_side_vertices",2)

	# Go through the list and find all the edges in the shadow direction that are directly connected to that edge
	var index_first_non_shadow = -1
	var index_last_non_shadow = -1
	var index 
	var max_edge_index

	outputlog("shadow_direction: " + str(shadow_direction),2)

	max_edge_index = find_furthest_shadow_edge(points, shadow_direction)
	index_first_non_shadow = find_next_shadow_non_shadow_index(points, shadow_direction, max_edge_index, 1)
	index = find_next_shadow_non_shadow_index(points, shadow_direction, index_first_non_shadow, -1)
	index_last_non_shadow = (index - 1) % points.size()
	# We want the last non shadow to be a value greater than index_first_non_shadow so the shader has a simpler calculation
	if index_last_non_shadow < index_first_non_shadow:
		index_last_non_shadow += points.size()
	
	outputlog("values: " + str({"index_first_non_shadow": index_first_non_shadow, "index_last_non_shadow": index_last_non_shadow}),2)

	# Some debug code for working out why this isn't working as expected
	if logging_level > 3:
		var debug_points = []
		for _i in points.size():
			if _i + index_first_non_shadow > index_last_non_shadow + 1:
				break
			debug_points.append(points[(index_first_non_shadow + _i) % points.size()])
		# Draw a path of the debug points
		draw_path(debug_points,"res://textures/paths/cliff.png", 200, 1.0,false)

	return {"index_first_non_shadow": index_first_non_shadow, "index_last_non_shadow": index_last_non_shadow}


