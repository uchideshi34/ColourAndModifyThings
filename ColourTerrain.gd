#########################################################################################################
##
## Select New Object Texture FUNCTIONS
##
#########################################################################################################

var script_class = "tool"

# Variables
var ui_config = {}

var terrain_tool = null
var terrain_shader = null
var store_last_valid_selection = []
var initialised_ui = false
var active_terrain_index = -1
var NewHSlider
var store_terrain_custom_data = {}
var reference_to_script = null
var global = null
var store_level_list = []

var _infobar = null
var _begun_save = false

const DEFAULT_HISTORY_RECORD = {"level_node": null, "previous_terrain_data": [], "new_terrain_data": []}
var history_record = DEFAULT_HISTORY_RECORD.duplicate(true)
const DEFAULT_COLOUR_PRESETS = ["ff6b3834", "ffac584c", "ff885848", "ffc0866c", "ff8d6d58", "fff3a768", "ff685848", "ff9c8868", "ffae9254", "ffd8c888", "ff888868", "ffaab478", "ff92aa58", "ff87a868", "ff679865", "ff789868", "ff546d56", "ff68887c", "ff667878", "ff809dab", "ff61788d", "ff535869", "ff786878", "ff886878", "ff905868", "ff994858", "ffffffff", "bfffffff", "7fffffff", "40ffffff"]

const COMBINED_DATA_STORE = "UchideshiNodeData"
const DEFAULT_TERRAIN_DATA = {
	"shader_type": "none",
	"colour": "ffffffff",
	"rotation": 0.0,
	"flip_x": false,
	"flip_y": false,
	"is_transparent": false,
	"transparency_threshold": 1.0
}
const DEFAULT_COLOUR_DATA = {
	"shader_type": "none",
	"colour": "ffffffff"
}

# Logging Functions
const ENABLE_LOGGING = true
var logging_level = 0
var newhslider_log_level = 0

#########################################################################################################
##
## UTILITY FUNCTIONS
##
#########################################################################################################

func outputlog(msg,level=0):
	if ENABLE_LOGGING:
		if level <= logging_level:
			printraw("(%d) <ColourTerrain>: " % OS.get_ticks_msec())
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

# Function to merge dictionaries, dictionary b overwrites duplicate key values in the result
func merge_dict(dict_a: Dictionary, dict_b: Dictionary, merge_arrays: bool = false) -> Dictionary:

	var new_dict = dict_a.duplicate(true)
	for key in dict_b:
		if key in new_dict:
			if dict_a[key] is Dictionary and dict_b[key] is Dictionary:
				new_dict[key] = merge_dict(dict_a[key], dict_b[key])
			elif dict_a[key] is Array and dict_b[key] is Array and merge_arrays:
				new_dict[key] = merge_array(dict_a[key], dict_b[key])
			else:
				new_dict[key] = dict_b[key]
		else:
			new_dict[key] = dict_b[key]
	return new_dict

# Function to merge arrays
func merge_array(array_1: Array, array_2: Array) -> Array:
	var new_array = array_1.duplicate(true)
	var compare_array = new_array
	var item_exists

	compare_array = []
	for item in new_array:
		if item is Dictionary or item is Array:
			compare_array.append(JSON.print(item))
		else:
			compare_array.append(item)

	for item in array_2:
		item_exists = item
		if item is Dictionary or item is Array:
			item = item.duplicate(true)
			item_exists = JSON.print(item)

		if not item_exists in compare_array:
			new_array.append(item)
	
	return new_array


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

# Function to find the grid menu category so we can put UI around it and modify it. Note that category_label here is the singular version, eg "Wall" not "Walls"
func find_select_vbox(tool_name: String):

	match tool_name:
		"ObjectTool":
			return global.Editor.Toolset.GetToolPanel("SelectTool").objectOptions
		"PathTool":
			return global.Editor.Toolset.GetToolPanel("SelectTool").pathOptions
		"PatternShapeTool":
			return global.Editor.Toolset.GetToolPanel("SelectTool").patternShapeOptions
		"WallTool":
			return global.Editor.Toolset.GetToolPanel("SelectTool").wallOptions
		"PortalTool":
			return global.Editor.Toolset.GetToolPanel("SelectTool").portalOptions
		_:
			outputlog("Error in find_select_grid_menu: vbox section not found. " + str(tool_name),4)
			return null

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

# Function to look at resource string and return the texture
func load_image_texture(texture_path: String):

	var image = Image.new()
	var texture = ImageTexture.new()

	# If it isn't an internal resource
	if not "res://" in texture_path:
		image.load(global.Root + texture_path)
		texture.create_from_image(image)
	# If it is an internal resource then just use the ResourceLoader
	else:
		texture = ResourceLoader.load(texture_path)
	
	return texture

# Make a button and return it
func make_button(parent_node, icon_path: String, hint_tooltip: String, toggle_mode: bool) -> Button:

	var button = Button.new()
	button.toggle_mode = toggle_mode
	button.icon = load_image_texture(icon_path)
	button.hint_tooltip = hint_tooltip
	parent_node.add_child(button)
	return button

# A simplefunction to create a label and return its reference
func make_label(section,text,index):
	var mylabel = Label.new()
	mylabel.text = text
	section.add_child(mylabel)
	section.move_child(mylabel,index)
	return mylabel

# Function to look with a control's children and look for matching text in their buttons/labels
func find_control_with_text(parent: Control, find_text: Array, default: int = 0) -> int:

	var index = -1
	# Look through all the children and when we find a label or button with the right text then store that index
	for thing in parent.get_children():
		if thing is Label || thing is Button:
			if thing.text.to_upper() in find_text:
				index = thing.get_index()
		if thing is HBoxContainer:
			if thing.get_children().size() > 0:
				if thing.get_child(0) is Label || thing.get_child(0) is Button:
					if thing.get_child(0).text.to_upper() in find_text:
						index = thing.get_index()

	if index < 0:
		return default
	return index

# Function to set a property on an object but block any signals for it
func set_property_but_block_signals(obj: Object, property: String, value):

	outputlog("set_property_but_block_signals: " + str(obj) + " property: " + str(property) + " value: " + str(value),3)

	obj.set_block_signals(true)
	if obj.get(property) != null:
		obj.set(property,value)
	obj.set_block_signals(false)

#########################################################################################################
##
## DATA FUNCTIONS
##
#########################################################################################################

func set_terrain_data(level_id: int, index: int, config: Dictionary):

	# Copy the Dropshadow data into a separate record so we don't iterate over newly created records
	if not global.ModMapData.has(COMBINED_DATA_STORE):
		global.ModMapData[COMBINED_DATA_STORE] = {}
	if not global.ModMapData[COMBINED_DATA_STORE].has("terrain_data"):
		global.ModMapData[COMBINED_DATA_STORE]["terrain_data"] = {}
	if not global.ModMapData[COMBINED_DATA_STORE]["terrain_data"].has("level-"+str(level_id)):
		global.ModMapData[COMBINED_DATA_STORE]["terrain_data"]["level-"+str(level_id)] = []
	
	if not index < global.ModMapData[COMBINED_DATA_STORE]["terrain_data"]["level-"+str(level_id)].size():
		return false

	global.ModMapData[COMBINED_DATA_STORE]["terrain_data"]["level-"+str(level_id)][index] = config.duplicate(true)
	return true

func get_terrain_data(level_id: int, index: int):

	# Copy the Dropshadow data into a separate record so we don't iterate over newly created records
	if not global.ModMapData.has(COMBINED_DATA_STORE):
		return DEFAULT_TERRAIN_DATA.duplicate(true)
	if not global.ModMapData[COMBINED_DATA_STORE].has("terrain_data"):
		return DEFAULT_TERRAIN_DATA.duplicate(true)
	
	if not global.ModMapData[COMBINED_DATA_STORE]["terrain_data"].has("level-"+str(level_id)):
		return DEFAULT_TERRAIN_DATA.duplicate(true)

	if not index < global.ModMapData[COMBINED_DATA_STORE]["terrain_data"]["level-"+str(level_id)].size():
		return DEFAULT_TERRAIN_DATA.duplicate(true)
	
	while global.ModMapData[COMBINED_DATA_STORE]["terrain_data"]["level-"+str(level_id)].size() > 8:
		global.ModMapData[COMBINED_DATA_STORE]["terrain_data"]["level-"+str(level_id)].remove(global.ModMapData[COMBINED_DATA_STORE]["terrain_data"]["level-"+str(level_id)].size()-1)

	return global.ModMapData[COMBINED_DATA_STORE]["terrain_data"]["level-"+str(level_id)][index].duplicate(true)

func init_terrain_data(level_id: int):

	if not global.ModMapData.has(COMBINED_DATA_STORE):
		global.ModMapData[COMBINED_DATA_STORE] = {}
	if not global.ModMapData[COMBINED_DATA_STORE].has("terrain_data"):
		global.ModMapData[COMBINED_DATA_STORE]["terrain_data"] = {}
	if not global.ModMapData[COMBINED_DATA_STORE]["terrain_data"].has("level-"+str(level_id)):
		global.ModMapData[COMBINED_DATA_STORE]["terrain_data"]["level-"+str(level_id)] = []

	for _i in range(global.ModMapData[COMBINED_DATA_STORE]["terrain_data"].size(),8,1):
		global.ModMapData[COMBINED_DATA_STORE]["terrain_data"]["level-"+str(level_id)].append(DEFAULT_TERRAIN_DATA.duplicate(true))

# Function to load the terrain data from the modmap entry into the store data object so that we can keep a reference to the level node
func load_terrain_data():

	outputlog("load_terrain_data",2)

	# For each level
	for _i in global.World.levels.size():
		# Create an entry with the level as the key
		store_terrain_custom_data[global.World.levels[_i]] = []
		# Pull the terrain data for each entry of that level
		for _j in 8:
			store_terrain_custom_data[global.World.levels[_i]].append(get_terrain_data(_i,_j))

# Function to save the terrain data to the map file. Noting we do this as level IDs can be changed within the session so we want to hold the node instead of its ID
func save_terrain_data():

	outputlog("save_terrain_data",2)

	# For each level
	for _i in global.World.levels.size():
		# Create an entry with the level as the key
		if store_terrain_custom_data.has(global.World.levels[_i]):

			# Pull the terrain data for each entry of that level
			for _j in 8:
				if not set_terrain_data(_i, _j, store_terrain_custom_data[global.World.levels[_i]][_j]):
					init_terrain_data(_i)
					set_terrain_data(_i, _j, store_terrain_custom_data[global.World.levels[_i]][_j])
			
			outputlog("store_terrain_custom_data: " + str(_i) + " : " + str(store_terrain_custom_data[global.World.levels[_i]]),2)

# Function to look for any missing levels in the store_terrain_custom_data and create an entry if they are missing
func validate_and_create_terrain_data():

	outputlog("validate_and_create_terrain_data",2)

	# For each level
	for _i in global.World.levels.size():
		# Create an entry with the level as the key
		if not store_terrain_custom_data.has(global.World.levels[_i]):
			# Create an entry with the level as the key
			store_terrain_custom_data[global.World.levels[_i]] = []
			# Pull the terrain data for each entry of that level
			for _j in 8:
				store_terrain_custom_data[global.World.levels[_i]].append(get_terrain_data(_i,_j))

# Update the store data with the default terrain data
func create_set_store_terrain_data_to_default(level):

	store_terrain_custom_data[level] = []

	for _i in 8:
		store_terrain_custom_data[level].append(DEFAULT_TERRAIN_DATA.duplicate(true))


#########################################################################################################
##
## CORE FUNCTION
##
#########################################################################################################

# Called when a new level might have been created
func on_possible_new_level():

	outputlog("on_possible_new_level",2)

	update_all_levels_terrain_shaders()
	validate_and_create_terrain_data()
	for level in global.World.levels:
		use_new_shaders(level)
		set_terrain_material_values(level)

# Function to update all terrain shaders on all levels. Called on load or when a new level is created.
func update_all_levels_terrain_shaders():

	outputlog("update_all_levels_terrain_shaders",2)

	# For each level
	for level in global.World.levels:
		set_terrain_shaders(level.Terrain)

# Function to set all shaders
func set_terrain_shaders(terrain):

	outputlog("set_terrain_shaders: " + str(terrain),2)

	terrain.normalShader = ResourceLoader.load(global.Root + "shaders/terrain.shader","Shader",true)
	terrain.expandedShader = ResourceLoader.load(global.Root + "shaders/terrain2.shader","Shader",true)
	terrain.smoothShader = ResourceLoader.load(global.Root + "shaders/smoothterrain.shader","Shader",true)
	terrain.expandedSmoothShader = ResourceLoader.load(global.Root + "shaders/smoothterrain2.shader","Shader",true)

# On launch of the terrain tool. Noting that the terrainButtonBox does not exist until this point, so we need to wait to create the ui
func on_launch_terrain_tool():

	outputlog("on_launch_terrain_tool",2)

	if initialised_ui:
		use_new_shaders()
		refresh_terrain_ui_from_stored_values()
		return

	# Make a timer to
	var timer = Timer.new()
	timer.autostart = false
	timer.one_shot = true
	global.Editor.get_node("Windows").add_child(timer)

	# Wait a couple of seconds to ensure everything has been drawn, the delay value has been set.
	timer.start(0.2)	
	yield(timer,"timeout")

	if terrain_tool.terrainButtonBox != null:
		
		make_terrain_colour_ui()
		initialised_ui = true
		use_new_shaders()
		refresh_terrain_ui_from_stored_values()
		on_expand_slots_button_toggled(terrain_tool.Controls["ExpandSlotsButton"].pressed)

	global.Editor.get_node("Windows").remove_child(timer)
	timer.queue_free()

# Function that tells DD to refresh which shaders are being used in the terrain tool
func use_new_shaders(level = null):

	outputlog("use_new_shaders",2)

	if level == null:
		level = global.World.GetCurrentLevel()

	set_terrain_material_values(level)
	level.Terrain.material.shader = get_new_shader(level.Terrain)

# Function to return the right shader for this terrain
func get_new_shader(terrain):

	if terrain.ExpandedSlots:
		if terrain.SmoothBlending:
			return terrain.expandedSmoothShader
		else:
			return terrain.expandedShader
	else:
		if terrain.SmoothBlending:
			return terrain.smoothShader
		else:
			return terrain.normalShader


#########################################################################################################
##
## UI CREATION FUNCTION
##
#########################################################################################################

func make_modulable_texture_32(color: Color = Color(1, 1, 1, 1)) -> ImageTexture:
	var img = Image.new()
	img.create(32, 32, false, Image.FORMAT_RGBA8)
	img.lock()
	img.fill(color)   # color can include alpha
	img.unlock()

	var tex = ImageTexture.new()
	tex.create_from_image(img)
	return tex

# Make the terrain colour ui. Noting that we have to wait until the first launch for the terrainbuttonbox to exist
func make_terrain_colour_ui():

	if terrain_tool.terrainButtonBox == null: return

	if not ui_config.has("TerrainBrush"):
		ui_config["TerrainBrush"] = {}
	
	if ui_config["TerrainBrush"].has("hbox"): return

	var hbox = terrain_tool.terrainButtonBox.get_parent()
	# Make a vbox that is the same as the terrainbutton box
	var vbox = terrain_tool.terrainButtonBox.duplicate(0)
	# Remove any children as we don't want them
	for child in vbox.get_children():
		vbox.remove_child(child)
		child.queue_free()

	hbox.add_child(vbox)

	# Make 8 buttons for the colours
	for _i in 8:
		make_individual_terrain_colour_ui(vbox, _i, terrain_tool.terrainButtonBox.get_child(0).rect_size)

	ui_config["TerrainBrush"]["hbox"] = hbox
	ui_config["TerrainBrush"]["button_vbox"] = vbox
	ui_config["gradient_map"].move_location("TerrainBrush","main",false)

	on_expand_slots_button_toggled(terrain_tool.Controls["ExpandSlotsButton"].pressed)

	vbox.minimum_size_changed()

# Make an entry for each terrain
func make_individual_terrain_colour_ui(vbox: VBoxContainer, index: int, min_size: Vector2):

	var hbox = HBoxContainer.new()
	vbox.add_child(hbox)

	var button = Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.icon = load("res://ui/icons/misc/colorable.png")
	button.toggle_mode = true
	button.connect("toggled", self, "on_terrain_button_pressed", [index])
	button.rect_min_size = min_size
	
	var tex_rect = TextureRect.new()
	tex_rect.rect_min_size = Vector2(32, 32)
	tex_rect.expand = true
	tex_rect.texture = make_modulable_texture_32()
	tex_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	hbox.add_child(tex_rect)
	hbox.add_child(button)
	hbox.set_meta("tex_rect",tex_rect)
	hbox.set_meta("button",button)


#########################################################################################################
##
## COMMON UI CREATION FUNCTION
##
#########################################################################################################

# Function to make the UI for the colour buttons
func make_overridecolour_ui(tool_type: String, location: String):

	outputlog("make_overridecolour_ui: " + str(tool_type) + " location: " + str(location),0)

	var vbox
	var find_text = ["FILL"]
	var hint_tooltips = {
		"gradient_button": "When enabled, a gradient map will be applied to the asset.",
		"reset_button": "Reset to non-coloured state."
	}
	var tool_panel
	var color_presets
	var colour_palette = null
	var hbox = HBoxContainer.new()
	var ui_element
	
	# Load in the colour palette data from the ModMapData entry
	match tool_type:
		"TerrainBrush":
			color_presets = global.ModMapData["ColourObjects"]["palettes"][tool_type].duplicate()
		_:
			return
	
	# Set up the tool panel and vbox values
	if location == "main":
		tool_panel = global.Editor.Toolset.GetToolPanel(tool_type)
		vbox = tool_panel.Align
	else:
		return
	
	# Create the ui_config dictionary records
	if not ui_config.has(tool_type):
		ui_config[tool_type] = {}
	if not ui_config[tool_type].has(location):
		ui_config[tool_type][location] = {}
	ui_element = ui_config[tool_type][location]

	# Find the fund_text item
	var index = find_control_with_text(vbox, find_text)

	# Make the colour palette
	# If we are in the main scatter tool, then we want to be able to select multiple colour preset
	colour_palette = tool_panel.CreateColorPalette("new_palette"+str(tool_type)+str(location),false,"ffffffff", color_presets, false, true)

	# Connect to signal to check if a preset has been removed
	colour_palette.colorList.connect("item_selected",self,"_on_new_colour_palette_item_selected",[null,tool_type,location])
	colour_palette.popup.connect("modal_closed",self,"create_update_custom_history")
	colour_palette.colorPicker.connect("color_changed",self,"_on_tintcolour_changed",[tool_type,location])
	colour_palette.paletteButton.hint_tooltip = "This colour (when not white) will tint the underlying asset similar to the lighting effect. If one of the grayscale options are enabled, this selected colour will work in a similar way to the Colorable feature."

	# Connect to signals to determine whether a history event should be recorded, ie when colour palette is closed
	colour_palette.colorPickerPopup.connect("popup_hide",self,"create_update_custom_history")
	vbox.move_child(colour_palette,index)
	ui_element["palette"] = colour_palette

	# Make the tint option control buttons
	vbox.add_child(hbox)
	vbox.move_child(hbox,index)
	var label = make_label(hbox,"Tint Color",0)
	label.size_flags_horizontal = 3
	ui_element["tint_hbox"] = hbox

	ui_element["gradient_button"] = make_button(hbox, "icons/settings-icon.png", hint_tooltips["gradient_button"], true)
	ui_element["gradient_button"].connect("toggled", self, "_on_colour_option_button_pressed",["gradient",tool_type,location, true])

	# Create reset button
	ui_element["reset_button"] = make_button(hbox, "icons/trash-icon.png", hint_tooltips["reset_button"], false)
	ui_element["reset_button"].connect("pressed", self, "_on_reset_button_pressed",[tool_type,location])


#########################################################################################################
##
## SET TERRAIN COLOUR FUNCTIONS
##
#########################################################################################################

func set_terrain_tex_rect_texture(index: int, config: Dictionary):

	var tex_rect = ui_config["TerrainBrush"]["button_vbox"].get_child(index).get_meta("tex_rect")
	match config["shader_type"]:
		"gradient":
			if tex_rect.texture is GradientTexture:
				tex_rect.texture.gradient = create_gradient(config["gradient"])
			else:
				var gradient_texture = create_gradient_texture(config["gradient"])
				gradient_texture.width = 32
				tex_rect.texture = gradient_texture
		_:
			if tex_rect.texture is GradientTexture:
				tex_rect.texture = make_modulable_texture_32()
	
	tex_rect.set_modulate(config["colour"])
	

# Se the terrain colour on the defined terrain index. Don't use make_history when calling from the a history record script
func set_terrain_colour(index: int, config: Dictionary, make_history: bool = true):

	outputlog("set_terrain_colour: " + str(config),2)

	var level = global.World.GetCurrentLevel()

	if make_history:
		# Store the current history status, ie setting the before change state. Noting that this is duplication if multiple changes happen before a create history event
		add_update_history_data(level, index, store_terrain_custom_data[level][index].duplicate(true))
		# Store the new history status
		add_update_history_data(level, index, config.duplicate(true))

	set_terrain_tex_rect_texture(index, config)
	store_terrain_custom_data[level][index] = config.duplicate(true)
	set_terrain_material_values(level)
	level.Terrain.UpdateSplat()

# Update the level's terrain all material values
func set_terrain_material_values(level):

	outputlog("set_terrain_material_values: " + str(level),2)

	# For each possible terrain entry
	for index in 8:
		set_terrain_non_gradient_material_values_by_index(level.Terrain, index, store_terrain_custom_data[level][index])
		level.Terrain.material.set_shader_param("apply_gradient_" + str(index+1), false)

	if is_apply_gradients_required(level):
		set_terrain_gradient_material_values(level)
			

# Function to determine if we need to apply any gradients in the 
func is_apply_gradients_required(level) -> bool:

	for _i in 8:
		if store_terrain_custom_data[level][_i]["shader_type"] == "gradient":
			return true
	return false

# Function to update the material for gradients
func set_terrain_gradient_material_values(level):

	outputlog("set_terrain_gradient_material_values",2)

	var gradient_array = []

	for index in 8:
		# If this is a gradient value then take its value
		if store_terrain_custom_data[level][index]["shader_type"] == "gradient":
			gradient_array.append(create_gradient_texture(store_terrain_custom_data[level][index]["gradient"]))
			level.Terrain.material.set_shader_param("apply_gradient_" + str(index+1), true)
		# Add a default gradient noting that this is never called in the shader
		else:
			gradient_array.append(create_gradient_texture({"colours": ["ff000000", "ffffffff"], "offsets": [0.0,1.0]}))
			level.Terrain.material.set_shader_param("apply_gradient_" + str(index+1), false)

	# Set the gradient_atlas
	var gradient_atlas = make_gradient_atlas(gradient_array)
	
	level.Terrain.material.set_shader_param("gradient_atlas", gradient_atlas)

# Function to set the terrain material values based on a config
func set_terrain_non_gradient_material_values_by_index(terrain, index: int, config: Dictionary):

	outputlog("set_terrain_material_values: " +  str(config),3)

	terrain.material.set_shader_param("tint_colour_" + str(index+1), Color(config["colour"]))
	terrain.material.set_shader_param("texture_rotation_" + str(index+1), deg2rad(config["rotation"]))
	terrain.material.set_shader_param("flip_x_" + str(index+1), config["flip_x"])
	terrain.material.set_shader_param("flip_y_" + str(index+1), config["flip_y"])

	if config.has("is_transparent"):
		terrain.material.set_shader_param("is_hole_" + str(index+1), config["is_transparent"])
		terrain.material.set_shader_param("transparent_threshold_" + str(index+1), config["transparent_threshold"])

# Function to take a dictionary of gradient data in readable format and convert it a texture.
func create_gradient_texture(gradient_data: Dictionary):

	outputlog("create_gradient_texture: " + str(gradient_data),2)

	var gradient_texture = GradientTexture.new()
	var gradient = create_gradient(gradient_data)

	if gradient == null: return null

	gradient_texture.gradient = gradient

	return gradient_texture

# Function to create and return a gradient based on gradient_data
func create_gradient(gradient_data: Dictionary):

	outputlog("create_gradient: " + str(gradient_data),2)

	var gradient = Gradient.new()
	var color

	if not gradient_data.has("colours") || not gradient_data.has("offsets"):
		return null
	if gradient_data["colours"].size() != gradient_data["offsets"].size():
		return null
	if gradient_data["colours"].size() < 2:
		return null

	# For each record in the data
	for _i in gradient_data["colours"].size():
		# Replace the first two points as we always have two
		color = Color(gradient_data["colours"][_i])
		if _i < 2:
			gradient.set_offset(_i, gradient_data["offsets"][_i])
			gradient.set_color(_i, color)
		# Otherwise add points
		else:
			gradient.add_point(gradient_data["offsets"][_i], color)
	
	return gradient


# Function to take an array of gradients and build an image that contains them
func make_gradient_atlas(gradients: Array, width := 256) -> ImageTexture:
	var count = gradients.size()
	var row_height = 3  # 3 pixels per gradient row
	var img = Image.new()
	img.create(width, count * row_height, false, Image.FORMAT_RGBA8)
	img.lock()

	for i in range(count):
		var gradient = gradients[i].gradient
		for y in range(row_height):
			for x in range(width):
				var t = float(x) / float(width - 1)
				var color = gradient.interpolate(t)
				color.a = 1.0  # fully opaque
				img.set_pixel(x, i * row_height + y, color)
	img.unlock()

	var tex = ImageTexture.new()
	tex.create_from_image(img)
	tex.flags = 0  # nearest, no mipmaps
	return tex


#########################################################################################################
##
## TERRAIN SPECIFIC UI CHANGE FUNCTIONS
##
#########################################################################################################

# When the colour reset button is pressed
func _on_reset_button_pressed(tool_type: String, location: String):

	if tool_type == "TerrainBrush" && not active_terrain_index < 0:
		var reset_colour_config = merge_dict(get_colour_config_from_terrain_ui(),DEFAULT_COLOUR_DATA.duplicate(true))
		set_terrain_colour(active_terrain_index,reset_colour_config)
		update_terrain_colour_ui_to_terrain(active_terrain_index,reset_colour_config)
		create_update_custom_history()

# On rotation reset button pressed
func on_reset_rotation_button_pressed():

	if not active_terrain_index < 0:
		var reset_colour_config = merge_dict(get_colour_config_from_terrain_ui(),{"rotation":0.0})
		set_terrain_colour(active_terrain_index,reset_colour_config)
		update_terrain_colour_ui_to_terrain(active_terrain_index,reset_colour_config)
		create_update_custom_history()

# On rotation reset button pressed
func on_reset_transparency_threshold_slider_button_pressed():

	if not active_terrain_index < 0:
		var reset_colour_config = merge_dict(get_colour_config_from_terrain_ui(),{"transparent_threshold":1.0})
		set_terrain_colour(active_terrain_index,reset_colour_config)
		update_terrain_colour_ui_to_terrain(active_terrain_index,reset_colour_config)
		create_update_custom_history()


# Function to flip the terrain and drive an update
func on_flip_terrain_button_toggled(button_pressed: bool):

	if not active_terrain_index < 0:
		set_terrain_colour(active_terrain_index,get_colour_config_from_terrain_ui())
		create_update_custom_history()

# Make Rotation UI
func make_flip_buttons_for_terrain(tool_type: String, location: String):

	outputlog("make_flip_buttons_for_terrain",0)

	# Create the ui_config dictionary records
	if not ui_config.has(tool_type):
		ui_config[tool_type] = {}
	if not ui_config[tool_type].has(location):
		ui_config[tool_type][location] = {}
	var ui_element = ui_config[tool_type][location]

	var hbox = HBoxContainer.new()
	global.Editor.Toolset.GetToolPanel(tool_type).Align.add_child(hbox)
	global.Editor.Toolset.GetToolPanel(tool_type).Align.move_child(hbox,global.Editor.Tools[tool_type].Controls["FILL"].get_index())

	var flip_x_button = make_button(hbox,"icons/flip-horizontal-icon.png","Enable to flip the terrain in the horizontal direction.",true)
	flip_x_button.text = "Flip X"
	flip_x_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flip_x_button.connect("toggled", self, "on_flip_terrain_button_toggled")

	var flip_y_button = make_button(hbox,"icons/flip-vertical-icon.png","Enable to flip the terrain in the vertical direction.",true)
	flip_y_button.text = "Flip Y"
	flip_y_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flip_y_button.connect("toggled", self, "on_flip_terrain_button_toggled")

	ui_config[tool_type][location]["flip_x_button"] = flip_x_button
	ui_config[tool_type][location]["flip_y_button"] = flip_y_button
	ui_config[tool_type][location]["flip_hbox"] = hbox

# Make Rotation UI
func make_rotation_slider_for_terrain(tool_type: String, location: String):

	outputlog("make_rotation_slider_for_terrain",0)

	# Create the ui_config dictionary records
	if not ui_config.has(tool_type):
		ui_config[tool_type] = {}
	if not ui_config[tool_type].has(location):
		ui_config[tool_type][location] = {}
	var ui_element = ui_config[tool_type][location]

	# Make the terrain slider for rotation
	ui_element["rotation_slider"] = NewHSlider.new(global.Editor.Toolset.GetToolPanel(tool_type).Align, 0.0, -180.0, 180.0, 0.1)
	ui_element["rotation_slider"].connect("value_changed", self, "on_terrain_rotation_slider_changed")
	ui_element["rotation_slider"].connect("emit_history_event_signal", self, "create_update_custom_history")
	global.Editor.Toolset.GetToolPanel(tool_type).Align.move_child(ui_element["rotation_slider"].hbox,global.Editor.Tools[tool_type].Controls["FILL"].get_index())

	var texturerect = TextureRect.new()
	texturerect.texture = load_image_texture("icons/rotate-32.png")
	texturerect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	texturerect.hint_tooltip = "Terrain Rotation"
	ui_element["rotation_slider"].hbox.add_child(texturerect)
	ui_element["rotation_slider"].hbox.move_child(texturerect,0)

	var reset_rotation_button = make_button(ui_element["rotation_slider"].hbox, "icons/centre-icon.png","Reset rotation to 0.0", false)
	reset_rotation_button.connect("pressed", self, "on_reset_rotation_button_pressed")

# Function when the transparency slider changes
func on_transparency_threshold_slider_changed(value: float):

	outputlog("on_transparency_threshold_slider_changed",2)

	# Error check that we have not set the active terrain incorrectly.
	if not active_terrain_index < 0:
		set_terrain_colour(active_terrain_index,get_colour_config_from_terrain_ui())

# Function to respond when a slider is changed
func on_terrain_rotation_slider_changed(value: float):

	outputlog("on_terrain_rotation_slider_changed",2)

	# Error check that we have not set the active terrain incorrectly.
	if not active_terrain_index < 0:
		set_terrain_colour(active_terrain_index,get_colour_config_from_terrain_ui())

# Make Transparent Terrain UI
func make_transparency_ui_for_terrain(tool_type: String, location: String):

	outputlog("make_transparency_ui_for_terrain",0)

	# Create the ui_config dictionary records
	if not ui_config.has(tool_type):
		ui_config[tool_type] = {}
	if not ui_config[tool_type].has(location):
		ui_config[tool_type][location] = {}
	var ui_element = ui_config[tool_type][location]

	# Make the toggle button for transparency
	ui_element["transparency_button"] = make_button(global.Editor.Toolset.GetToolPanel(tool_type).Align, "res://ui/icons/buttons/circle.png","Enable this terrain slot to paint transparency.", true)
	ui_element["transparency_button"].text = "Make Transparent"
	ui_element["transparency_button"].connect("toggled", self, "on_transparency_button_toggled",[tool_type,location])
	global.Editor.Toolset.GetToolPanel(tool_type).Align.move_child(ui_element["transparency_button"],global.Editor.Tools[tool_type].Controls["FILL"].get_index())

	# Make the threshold slider for rotation
	ui_element["transparency_threshold_slider"] = NewHSlider.new(global.Editor.Toolset.GetToolPanel(tool_type).Align, 1.0, 0.0, 1.0, 0.01)
	ui_element["transparency_threshold_slider"].connect("value_changed", self, "on_transparency_threshold_slider_changed")
	ui_element["transparency_threshold_slider"].connect("emit_history_event_signal", self, "create_update_custom_history")
	global.Editor.Toolset.GetToolPanel(tool_type).Align.move_child(ui_element["transparency_threshold_slider"].hbox,global.Editor.Tools[tool_type].Controls["FILL"].get_index())
	ui_element["transparency_threshold_slider"].hbox.visible = false

	var texturerect = TextureRect.new()
	texturerect.texture = load_image_texture("icons/settings-icon.png")
	texturerect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	texturerect.hint_tooltip = "Transparency Threshold"
	ui_element["transparency_threshold_slider"].hbox.add_child(texturerect)
	ui_element["transparency_threshold_slider"].hbox.move_child(texturerect,0)

	var reset_transparency_threshold_slider_button = make_button(ui_element["transparency_threshold_slider"].hbox, "res://ui/icons/menu/undo.png","Reset transparency threshold to 1.0", false)
	reset_transparency_threshold_slider_button.connect("pressed", self, "on_reset_transparency_threshold_slider_button_pressed")

# Function called when the transparency button is toggled
func on_transparency_button_toggled(button_pressed: bool, tool_type, location):

	outputlog("on_transparency_button_toggled",2)

	# Error check that we have not set the active terrain incorrectly.
	if not active_terrain_index < 0:
		set_terrain_colour(active_terrain_index,get_colour_config_from_terrain_ui())
		create_update_custom_history()

	ui_config[tool_type][location]["transparency_threshold_slider"].hbox.visible = button_pressed

# When the gradient is changed
func on_gradient_values_changed(tool_type: String, location: String):

	outputlog("on_gradient_values_changed",2)

	if tool_type != "TerrainBrush": return

	# Error check that we have not set the active terrain incorrectly.
	if not active_terrain_index < 0:
		set_terrain_colour(active_terrain_index,get_colour_config_from_terrain_ui())

# Get the colout config from the terrain ui
func get_colour_config_from_terrain_ui():

	var config = {
		"colour": ui_config["TerrainBrush"]["main"]["palette"].color.to_html(),
		"rotation": ui_config["TerrainBrush"]["main"]["rotation_slider"].value,
		"flip_x": ui_config["TerrainBrush"]["main"]["flip_x_button"].pressed,
		"flip_y": ui_config["TerrainBrush"]["main"]["flip_y_button"].pressed,
		"is_transparent": ui_config["TerrainBrush"]["main"]["transparency_button"].pressed,
		"transparent_threshold": ui_config["TerrainBrush"]["main"]["transparency_threshold_slider"].value
	}

	if ui_config["TerrainBrush"]["main"]["gradient_button"].pressed:
		config["shader_type"] = "gradient"
		config["gradient"] = ui_config["gradient_map"].get_gradient_data()
	else:
		config["shader_type"] = "none"
	
	return config

# Function to respond when one of the terrain buttons is pressed
func on_terrain_button_pressed(button_pressed: bool, index: int):

	outputlog("on_terrain_button_pressed: " + str(index),2)

	if not initialised_ui: return

	# Set the active terrain index so the colour changes are applied to the right terrain
	if button_pressed:
		toggle_off_other_terrain_buttons(index)
		active_terrain_index = index
		if store_terrain_custom_data.has(global.World.GetCurrentLevel()):
			update_terrain_colour_ui_to_terrain(index,store_terrain_custom_data[global.World.GetCurrentLevel()][index])
		show_hide_terrain_colour_ui(true)
		terrain_tool.terrainList.select(index)
	else:
		active_terrain_index = -1
		toggle_off_other_terrain_buttons(-1)
		show_hide_terrain_colour_ui(false)

# Show hide the terrain colour ui
func show_hide_terrain_colour_ui(make_visible: bool):

	outputlog("show_hide_terrain_colour_ui: " + str(make_visible),2)

	ui_config["TerrainBrush"]["main"]["tint_hbox"].visible = make_visible
	ui_config["TerrainBrush"]["main"]["palette"].visible = make_visible
	ui_config["TerrainBrush"]["main"]["rotation_slider"].hbox.visible = make_visible
	ui_config["TerrainBrush"]["main"]["flip_hbox"].visible = make_visible
	ui_config["TerrainBrush"]["main"]["transparency_button"].visible = make_visible
	ui_config["TerrainBrush"]["main"]["transparency_threshold_slider"].visible = make_visible
	if ui_config["TerrainBrush"]["main"]["gradient_button"].pressed && make_visible:
		ui_config["gradient_map"].show()
	else:
		ui_config["gradient_map"].hide()

# Function to update the terrain colour ui to match the stored values in the config
func update_terrain_colour_ui_to_terrain(index: int, config: Dictionary):

	outputlog("update_terrain_colour_ui_to_terrain: index: " + str(index) + " config: " + str(config),2)

	if not initialised_ui: return

	var ui_element = ui_config["TerrainBrush"]["main"]

	ui_element["palette"].SetColor(Color(config["colour"]), false)
	set_terrain_tex_rect_texture(index, config)
	ui_element["rotation_slider"].slider_and_spinbox_change(config["rotation"], true)
	ui_config["TerrainBrush"]["main"]["flip_x_button"].pressed = config["flip_x"]
	ui_config["TerrainBrush"]["main"]["flip_y_button"].pressed = config["flip_y"]

	# Set transparency values
	if config.has("is_transparent"):
		ui_config["TerrainBrush"]["main"]["transparency_button"].pressed = config["is_transparent"]
		ui_config["TerrainBrush"]["main"]["transparency_threshold_slider"].slider_and_spinbox_change(config["transparent_threshold"], true)
	else:
		ui_config["TerrainBrush"]["main"]["transparency_button"].pressed = false
		ui_config["TerrainBrush"]["main"]["transparency_threshold_slider"].slider_and_spinbox_change(1.0, true)

	match config["shader_type"]:
		"gradient":
			ui_element["gradient_button"].pressed = true
			ui_config["gradient_map"].set_gradient_values(config["gradient"])
		_:
			ui_element["gradient_button"].pressed = false
	
# Function to toggle off other terrain
func toggle_off_other_terrain_buttons(active_index: int):

	for _i in ui_config["TerrainBrush"]["button_vbox"].get_children().size():
		if _i != active_index:
			set_property_but_block_signals(ui_config["TerrainBrush"]["button_vbox"].get_child(_i).get_meta("button"),"pressed",false)

# Function when the terrain tool is opened/ or closed
func on_terrain_brush_visibility_changed():

	# If the terrain brush is opened
	if global.Editor.Toolset.GetToolPanel("TerrainBrush").visible:
		on_launch_terrain_tool()
	else:
		# Call the custom history function in case we are timing out a gradient slider when the tool is being closed.
		create_update_custom_history()

# Function called when the expand_slots_button is toggled
func on_expand_slots_button_toggled(button_pressed: bool):

	if not initialised_ui: return

	for _i in range(4,8,1):
		ui_config["TerrainBrush"]["button_vbox"].get_child(_i).get_meta("button").visible = button_pressed
		ui_config["TerrainBrush"]["button_vbox"].get_child(_i).get_meta("tex_rect").visible = button_pressed

# Function to update the current terrain ui from the stored values
func refresh_terrain_ui_from_stored_values():

	outputlog("refresh_terrain_ui_from_stored_values: ",2)

	# Deselect all the edit buttons
	on_terrain_button_pressed(false, 0)

	for index in 8:
		if not store_terrain_custom_data.has(global.World.GetCurrentLevel()):
			validate_and_create_terrain_data()
		update_terrain_colour_ui_to_terrain(index,store_terrain_custom_data[global.World.GetCurrentLevel()][index])
	
	

# Function called when the 
func on_item_selected_in_leveloptions(index: int):

	refresh_terrain_ui_from_stored_values()

#########################################################################################################
##
## UI CHANGE FUNCTIONS (COMMON WITH COLOUR MOD)
##
#########################################################################################################

func _on_tintcolour_changed(color: Color, tool_type: String, location: String):

	outputlog("_on_tintcolour_changed",2)
	var config = get_colour_config_from_terrain_ui()
	config["colour"] = color.to_html()

	set_terrain_colour(active_terrain_index,config)

func _on_new_colour_palette_item_selected(index: int, _ignore_this, tool_type: String, location: String):

	outputlog("_on_new_colour_palette_item_selected",2)

	var timer = Timer.new()
	global.Editor.get_node("Windows").add_child(timer)
	timer.autostart = false
	timer.one_shot = true
	
	# Wait a couple of seconds to ensure the palette presets list is updated.
	timer.start(0.1)
	yield(timer,"timeout")

	set_terrain_colour(active_terrain_index,get_colour_config_from_terrain_ui())
	create_update_custom_history()

	set_palette_list(tool_type,location)

	# Remove it
	global.Editor.get_node("Windows").remove_child(timer)
	timer.queue_free()

# Set the palette list - this error checking should be unnecessary
func set_palette_list(tool_type: String, location: String):

	if not global.ModMapData.has("ColourObjects"):
		global.ModMapData["ColourObjects"] = {}
	
	if not global.ModMapData["ColourObjects"].has("palettes"):
		global.ModMapData["ColourObjects"]["palettes"] = {}
	
	if not global.ModMapData["ColourObjects"]["palettes"].has(tool_type):
		global.ModMapData["ColourObjects"]["palettes"][tool_type] = DEFAULT_COLOUR_PRESETS
	else:
		# Update the palette for future use
		global.ModMapData["ColourObjects"]["palettes"][tool_type] = ui_config[tool_type][location]["palette"].Save()

# Function to capture when a 
func _on_preset_changed_in_palette(index: int, _ignore_this, tool_type: String, location: String):

	create_update_custom_history()

# Function to call when one of the colour options is selected
func _on_colour_option_button_pressed(button_pressed: bool, source_shader_type: String, tool_type: String, location: String, update_selection: bool):

	outputlog("_on_colour_option_button_pressed",2)
	outputlog("source_shader_type: " + str(source_shader_type),2)

	# Set the visibility of various colour ui elements based on the options change
	set_ui_visibilty_from_colour_options_change(button_pressed, source_shader_type, tool_type, location)

	# If there is an active index then make a change, otherwise it is a background refresh
	if active_terrain_index > -1:
		# Actually implement the change
		set_terrain_colour(active_terrain_index,get_colour_config_from_terrain_ui())
		create_update_custom_history()

# Function to update the ui reflecting the colour options
func set_ui_visibilty_from_colour_options_change(button_pressed: bool, source_shader_type: String, tool_type: String, location: String):

	outputlog("set_ui_visibilty_from_colour_options_change",2)

	var ui_element = ui_config[tool_type][location]
	var button_lookup = { "none": null, "gradient": ui_element["gradient_button"]}
	if ui_element == null: return
	# For each button, set the state without triggering further action so we don't infinitely call this function
	for shader_type in button_lookup.keys():
		if shader_type != "none":
			# If this isn't the source button then set it to false
			if shader_type != source_shader_type:
				set_property_but_block_signals(button_lookup[shader_type], "pressed", false)
			# If it is then set it to the value of button_pressed
			else:
				set_property_but_block_signals(button_lookup[shader_type], "pressed", button_pressed)
			
	# Set the visibility of the gradient ui
	if button_pressed && source_shader_type == "gradient":
		ui_config["gradient_map"].show()

	else:
		ui_config["gradient_map"].hide()

#########################################################################################################
##
## COPY LEVEL FUNCTIONS
##
#########################################################################################################

# Function to copy the level data
func _copy_terrain_data_to_new_level(level_id_being_copied: int):

	var new_level = find_new_level_created()
	if new_level == null:
		outputlog("failed to find new level",2)
		return
	var source_level = global.World.levels[level_id_being_copied]

	store_terrain_custom_data[new_level] = store_terrain_custom_data[source_level].duplicate(true)
	use_new_shaders(new_level)
	set_terrain_material_values(new_level)

# When create new level is pressed
func _on_create_new_level_pressed(cloneleveloptionbutton: OptionButton):

	outputlog("_on_create_new_level_pressed",2)

	var timer = Timer.new()
	timer.autostart = false
	timer.one_shot = true
	global.Editor.get_node("Windows").add_child(timer)

	var level_id_being_copied = cloneleveloptionbutton.selected

	# If we are cloning a level, ie selected index is more than zero, then do something but wait a bit first
	if level_id_being_copied > 0:
		timer.start(1.0)
		yield(timer,"timeout")
		_copy_terrain_data_to_new_level(level_id_being_copied)
	# If the new level isn't a copy we need to initialise the terrain
	else:
		outputlog("not a level copy set new ")
		var level = find_new_level_created()
		if level != null:
			create_set_store_terrain_data_to_default(level)
	
	global.Editor.get_node("Windows").remove_child(timer)
	timer.queue_free()

# Find the new level window
func find_new_level_window():

	outputlog("find_new_level_window",2)

	var valign = global.Editor.Windows["NewLevel"].get_node("Margins").get_node("VAlign")
	global.Editor.Windows["NewLevel"].connect("about_to_show", self, "on_new_level_window_opened")

	# If we have successfully found the Create Level window then connect to the "Create" button 
	if valign != null:
		if valign.get_node("Buttons") != null && valign.get_node("CloneLevel") != null:
			if valign.get_node("Buttons").get_node("OkayButton") != null && valign.get_node("CloneLevel").get_node("CloneLevelOptionButton") != null:
				var cloneleveloptionbutton = valign.get_node("CloneLevel").get_node("CloneLevelOptionButton")
				valign.get_node("Buttons").get_node("OkayButton").connect("pressed", self, "_on_create_new_level_pressed",[cloneleveloptionbutton])

# Function to capture when a new level window is opened so we can store the current level list
func on_new_level_window_opened():

	store_level_list = global.World.levels.duplicate(true)

# Compare the current list of levels with the stored list and a level that is not in the stored list is the new one
func find_new_level_created():

	for level in global.World.levels:
		if not level in store_level_list:
			return level

	return null

#########################################################################################################
##
## HISTORY FUNCTIONS
##
#########################################################################################################

# Function to take a node id and store their current status so that we can create a before and after data record
func add_update_history_data(level, index: int, config: Dictionary):

	outputlog("add_update_history_data: " +str(level),2)

	if index < 0:
		outputlog("error: index is: " + str(index))
		return

	# If this is first time, it is called then update the previous terrain data
	if history_record["level_node"] == null || history_record["level_node"] != level:
		history_record["level_node"] = level
		history_record["previous_terrain_data"] = store_terrain_custom_data[level].duplicate(true)
		history_record["new_terrain_data"] = store_terrain_custom_data[level].duplicate(true)

	history_record["new_terrain_data"][index] = config.duplicate(true)

# Function to reset the history data back to default values
func clear_history_data():

	history_record = DEFAULT_HISTORY_RECORD.duplicate(true)

# Create custom history record, called when a colour preset is selected, the color picker is closed, or a slider timer finishes
func create_update_custom_history(delay_secs: float = 0.0):

	var record_script
	outputlog("create_update_custom_history",2)

	# If we need a short delay then implement it
	if delay_secs > 0.0:
		var timer = Timer.new()
		global.Editor.get_node("Windows").add_child(timer)
		timer.autostart = false
		timer.one_shot = true
		# Wait a couple of seconds to ensure the palette presets list is updated.
		timer.start(delay_secs)
		yield(timer,"timeout")
		# Remove it
		global.Editor.get_node("Windows").remove_child(timer)
		timer.queue_free()

	# If there is no data in the record dictionary, then do nothing. This might fired from the "main" location
	if history_record["level_node"] == null:
		outputlog("no history data available",2)
		clear_history_data()
		return

	# Check if the data record for new and old is the same in which case do nothing
	if is_the_same(history_record["previous_terrain_data"],history_record["new_terrain_data"]):
		outputlog("No history record created as no difference between old and new status",2)
		# As the data is invalid, clear the data
		clear_history_data()
		return

	# Create a new record if one is needed or simply update the existing one
	record_script = reference_to_script.InstanceReference("library/custom_history_record_terrain.gd")

	# If this is null for any reason then return to avoid a crash
	if record_script == null:
		outputlog("record_script is null",2)
		# As the data is invalid, clear the data
		clear_history_data()
		return

	record_script.colourterrain = self
	record_script.level_node = history_record["level_node"]
	record_script.previous_terrain_data = history_record["previous_terrain_data"].duplicate(true)
	record_script.new_terrain_data = history_record["new_terrain_data"].duplicate(true)

	outputlog("previous_node_data\n" + JSON.print(record_script.previous_terrain_data,"\t"),2)
	outputlog("new_node_data\n" + JSON.print(record_script.new_terrain_data,"\t"),2)

	# If this is a new action then create a new custom record
	var record = global.Editor.History.CreateCustomRecord(record_script)

	# Reset the history record
	clear_history_data()

	# Save the store data to file, using the create history as a good proxy of a committed change
	save_terrain_data()

# Function called when the gradientmap emits record_history event. Noting that this signal may not be relevant for the TerrainBrush
func on_gradient_record_history_event(_ignore_this, _ignore_this_too, _and_this):

	# If the active tool is Terrain, then call create history. Noting that it is possible that a slider timeout might trigger when leaving the tool but we will capture this in the on_tool_launch function.
	if Global.Editor.ActiveToolName == "TerrainBrush":
		create_update_custom_history()


#########################################################################################################
##
## START FUNCTION
##
#########################################################################################################

# Function to initialise the modmapdata values
func initialise_colourthings_modmapdata():

	# Initialise ModMapData
	if not global.ModMapData.has("ColourObjects"):
		global.ModMapData["ColourObjects"] = {}

	# Note that we are removing this need with the customdatamanager
	if not global.ModMapData["ColourObjects"].has("data"):
		global.ModMapData["ColourObjects"]["data"] = {}

	if not global.ModMapData["ColourObjects"].has("brightness_data"):
		global.ModMapData["ColourObjects"]["brightness_data"] = {}
	
	if not global.ModMapData["ColourObjects"].has("palettes"):
		global.ModMapData["ColourObjects"]["palettes"] = {}

	# Set up each of the palette records
	for tool_type in ["TerrainBrush"]:
		if not global.ModMapData["ColourObjects"]["palettes"].has(tool_type):
			global.ModMapData["ColourObjects"]["palettes"][tool_type] = DEFAULT_COLOUR_PRESETS

# Main Script
func initialise() -> void:

	outputlog("ColourTerrain Mod Has been loaded.")
	if not ui_config.has("TerrainBrush"):
		ui_config["TerrainBrush"] = {}
	
	NewHSlider = ResourceLoader.load(global.Root + "NewHSlider.gd", "GDScript", true)

	terrain_tool = global.Editor.Tools["TerrainBrush"]

	global.Editor.Toolset.GetToolPanel("TerrainBrush").connect("visibility_changed", self, "on_terrain_brush_visibility_changed")
	init_terrain_data(global.World.GetCurrentLevel().ID)
	initialise_colourthings_modmapdata()

	make_transparency_ui_for_terrain("TerrainBrush","main")
	make_rotation_slider_for_terrain("TerrainBrush","main")
	make_flip_buttons_for_terrain("TerrainBrush","main")
	make_overridecolour_ui("TerrainBrush","main")

	show_hide_terrain_colour_ui(false)

	load_terrain_data()
	update_all_levels_terrain_shaders()

	# Link to signals for expanding the terrain slots
	terrain_tool.Controls["ExpandSlotsButton"].connect("toggled", self, "on_expand_slots_button_toggled")

	# Connect to signal when a new level might be created
	global.Editor.Windows["NewLevel"].connect("popup_hide", self, "on_possible_new_level")

	# Connect to signals when we might go up or down a level including in the exporter
	global.Editor.LevelOptions.connect("item_selected", self, "on_item_selected_in_leveloptions")
	if global.Editor.LevelOptions.get_parent().find_node("LevelDown") != null:
		global.Editor.LevelOptions.get_parent().find_node("LevelDown").connect("pressed", self, "refresh_terrain_ui_from_stored_values")
	if global.Editor.LevelOptions.get_parent().find_node("LevelUp") != null:
		global.Editor.LevelOptions.get_parent().find_node("LevelUp").connect("pressed", self, "refresh_terrain_ui_from_stored_values")
	
	# Set up gradient map signals
	ui_config["gradient_map"].connect("gradient_changed",self, "on_gradient_values_changed")
	ui_config["gradient_map"].connect("record_history",self, "on_gradient_record_history_event")

	# Force an initialisation event otherwise the terrain colours for a stored event will not fire
	on_possible_new_level()
	find_new_level_window()
	
