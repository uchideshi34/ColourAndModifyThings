#########################################################################################################
##
## CORE MOD
##
#########################################################################################################

var script_class = "tool"

var mod_tool_panel = null
var _lib_mod_config = null

var store_last_valid_selection = []
var store_preview_config = {
	"texture": "",
	"shader_type": "none",
	"colour": "ffffffff"
	}
var store_preview_node = null

var ui_config = {}

const BUILD_THESE_TOOLS = ["ObjectTool", "ScatterTool", "PathTool", "PatternShapeTool","WallTool","PortalTool"]

const DEFAULT_COLOUR_PRESETS = ["ff6b3834", "ffac584c", "ff885848", "ffc0866c", "ff8d6d58", "fff3a768", "ff685848", "ff9c8868", "ffae9254", "ffd8c888", "ff888868", "ffaab478", "ff92aa58", "ff87a868", "ff679865", "ff789868", "ff546d56", "ff68887c", "ff667878", "ff809dab", "ff61788d", "ff535869", "ff786878", "ff886878", "ff905868", "ff994858", "ffffffff", "bfffffff", "7fffffff", "40ffffff"]
const TYPE_LOOKUP = {"ObjectTool": "objects","ScatterTool": "objects", "PathTool": "paths", "PatternShapeTool": "pattern_shapes", "WallTool": "walls", "PortalTool": "portals"}
const TOOL_TYPE_LOOKUP_BY_SELECTABLE = {"1": "WallTool", "2": "PortalTool", "3": "PortalTool", "4": "ObjectTool", "5": "PathTool", "6": "LightTool", "7": "PatternShapeTool", "8": "RoofTool"}
const HIDE_NONGRADIENT_BUTTON_TOOLS = ["PatternShapeTool","WallTool"]

const LEVELS_SLIDER_STEP = 0.005
const SLIDER_WAIT_TIME = 1.0

var CustomDataManager
var customdatamanager

var CombinedShader
var combinedshader

var ColourThings
var colourthings

var EdgeBlurPatterns
var edgeblurpatterns

var ModifyPaths
var modifypaths

var ColourTerrain
var colourterrain
var _begun_save = false

# Logging Functions
const ENABLE_LOGGING = true
var logging_level = 0

#########################################################################################################
##
## UTILITY FUNCTIONS
##
#########################################################################################################

func outputlog(msg,level=0):
	if ENABLE_LOGGING:
		if level <= logging_level:
			printraw("(%d) <ColourAndModifyThings>: " % OS.get_ticks_msec())
			print(msg)
	else:
		pass

# Function to look at resource string and return the texture
func load_image_texture(texture_path: String):

	var image = Image.new()
	var texture = ImageTexture.new()

	# If it isn't an internal resource
	if not "res://" in texture_path:
		image.load(Global.Root + texture_path)
		texture.create_from_image(image)
	# If it is an internal resource then just use the ResourceLoader
	else:
		texture = ResourceLoader.load(texture_path)
	
	return texture

# A simplefunction to create a label and return its reference
func make_label(section,text,index):
	var mylabel = Label.new()
	mylabel.text = text
	section.add_child(mylabel)
	section.move_child(mylabel,index)
	return mylabel

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

# Function to set a property on an object but block any signals for it
func set_property_but_block_signals(obj: Object, property: String, value):

	outputlog("set_property_but_block_signals: " + str(obj) + " property: " + str(property) + " value: " + str(value),3)

	obj.set_block_signals(true)
	if obj.get(property) != null:
		obj.set(property,value)
	obj.set_block_signals(false)


# Create a linked slider because the standard one whinges about property values not being set
func make_hslider(vbox, default: float, minimum: float, maximum: float, step: float):

	var hbox = HBoxContainer.new()
	hbox.size_flags_vertical = 1
	hbox.size_flags_horizontal = 3

	outputlog("make_hslider",2)

	var hslider = HSlider.new()
	hslider.max_value = maximum
	hslider.min_value = minimum
	
	hslider.step = step
	hslider.size_flags_horizontal = 3
	hslider.size_flags_vertical = 3

	var timer = Timer.new()
	timer.one_shot = true
	timer.auto_start = false
	timer.wait_time = SLIDER_WAIT_TIME
	hslider.set_meta("timer",timer)
	hslider.get_meta("timer").connect("timeout", self, "emit_history_event_signal")
	
	var spinbox = SpinBox.new()
	spinbox.max_value = maximum
	spinbox.min_value = minimum
	spinbox.value = default
	spinbox.step = step
	spinbox.align = 1
	spinbox.connect("value_changed",self,"slider_change",[hslider,false])
	hslider.connect("value_changed",self,"slider_change",[spinbox,true])
	hslider.connect("value_changed",self,"start_slider_timer",[timer])
	hslider.set_meta("spinbox",spinbox)
	
	hbox.add_child(hslider)
	hbox.add_child(spinbox)
	hbox.add_child(timer)
	vbox.add_child(hbox)
	hslider.set_meta("hbox",hbox)

	spinbox.get_line_edit().expand_to_text_length = true

	# Silly work around to get the default value to display properly
	hslider.value = default
	if default != minimum:
		hslider.value = minimum
	elif default != maximum:
		hslider.value = maximum
	hslider.value = default
	
	return hslider

# Link spinbox and slider
func slider_change(value: float, target, suppress_signal: bool):

	if suppress_signal:
		target.set_block_signals(true)
		target.value = value
		target.set_block_signals(false)
	else:
		target.value = value

# Function to update the values of a slider and its spinbox without triggering further signals
func slider_and_spinbox_change(value: float, slider: HSlider, suppress_signal: bool):

	outputlog("slider_and_spinbox_change",2)

	if suppress_signal:
		slider_change(value, slider, suppress_signal)
		if slider.has_meta("spinbox"):
			if slider.get_meta("spinbox") is SpinBox:
				slider_change(value, slider.get_meta("spinbox"), suppress_signal)		
	else:
		# Note that this should automatically update the spinbox via signals
		slider.value = value

# Function to start or reset the slider timer. Once the timer completes we call a function to emit the record history event.
func start_slider_timer(value: float, timer: Timer):

	if timer.is_stopped():
		timer.start()
	else:
		timer.wait_time = SLIDER_WAIT_TIME

# Function to return bool if this is the object tool or the scatter tool
func is_object_tool_type(tool_type: String) -> bool:

	return tool_type in ["ObjectTool","ScatterTool"]


#########################################################################################################
##
## READ & WRITE MODMAPDATA FUNCTIONS
##
#########################################################################################################


# Function to create a record for a texture's brightness min_gray and max_gray values so we don't have to keep calculating them
func set_brightness_data(texture_path: String, min_gray: float, max_gray: float):

	Global.ModMapData["ColourObjects"]["brightness_data"][texture_path] = {"min_gray": min_gray, "max_gray": max_gray}

# Function to create a record for a texture's brightness min_gray and max_gray values so we don't have to keep calculating them
func get_brightness_data(texture_path: String) -> Dictionary:

	if Global.ModMapData["ColourObjects"]["brightness_data"].has(texture_path):
		return Global.ModMapData["ColourObjects"]["brightness_data"][texture_path]
	else:
		return {"min_gray": -1, "max_gray": -1}

# Function to create a record for a texture's brightness min_gray and max_gray values so we don't have to keep calculating them
func delete_brightness_data(texture_path: String):

	if Global.ModMapData["ColourObjects"]["brightness_data"].has(texture_path):
		Global.ModMapData["ColourObjects"]["brightness_data"].erase(texture_path)

# Function to initialise the modmapdata values
func initialise_colourthings_modmapdata():

	# Initialise ModMapData
	if not Global.ModMapData.has("ColourObjects"):
		Global.ModMapData["ColourObjects"] = {}

	# Note that we are removing this need with the customdatamanager
	if not Global.ModMapData["ColourObjects"].has("data"):
		Global.ModMapData["ColourObjects"]["data"] = {}

	if not Global.ModMapData["ColourObjects"].has("brightness_data"):
		Global.ModMapData["ColourObjects"]["brightness_data"] = {}
	
	if not Global.ModMapData["ColourObjects"].has("palettes"):
		Global.ModMapData["ColourObjects"]["palettes"] = {}

	# Set up each of the palette records
	for tool_type in ["ObjectTool","PathTool","PortalTool","TerrainBrush"]:
		if not Global.ModMapData["ColourObjects"]["palettes"].has(tool_type):
			Global.ModMapData["ColourObjects"]["palettes"][tool_type] = DEFAULT_COLOUR_PRESETS

# Function to return the ui_element or null if it doesn't exist
func get_ui_element(tool_type: String, location: String):

	if ui_config.has(tool_type):
		if ui_config[tool_type].has(location):
			return ui_config[tool_type][location]
	return null


# When the gradient mod tool is opened, refresh the group list
func on_tool_enable(_tool_id):

	colourthings.ui_config["gradient_map"].presetsdropdown.refresh_export_groups_menu_button()

# Function to find the grid menu category so we can put UI around it and modify it. Note that category_label here is the singular version, eg "Wall" not "Walls"
func find_select_vbox(tool_name: String):

	match tool_name:
		"ObjectTool":
			return Global.Editor.Toolset.GetToolPanel("SelectTool").objectOptions
		"PathTool":
			return Global.Editor.Toolset.GetToolPanel("SelectTool").pathOptions
		"PatternShapeTool":
			return Global.Editor.Toolset.GetToolPanel("SelectTool").patternShapeOptions
		"WallTool":
			return Global.Editor.Toolset.GetToolPanel("SelectTool").wallOptions
		"PortalTool":
			return Global.Editor.Toolset.GetToolPanel("SelectTool").portalOptions
		_:
			outputlog("Error in find_select_grid_menu: vbox section not found. " + str(tool_name),4)
			return null


#########################################################################################################
##
## SET UI TO SELECTED NODE VALUES FUNCTIONS
##
#########################################################################################################


#########################################################################################################
##
## GET VALUES FROM UI FUNCTIONS
##
#########################################################################################################


#########################################################################################################
##
## UDPATE SELECTION WITH NEW VALUES FUNCTIONS
##
#########################################################################################################

		

#########################################################################################################
##
## HELPER FUNCTIONS
##
#########################################################################################################

# Find the colourable config values from the node by looking for the asset pack id and examining that asset packs red values
func get_colourable_config_values(node):

	var texture
	var red_config = {"min_redness":0.1, "red_tolerance": 0.04, "min_saturation": 0.0}
	var packID

	# If it is an object
	if node.has("Sprite"):
		texture = get_asset_texture(node, "ObjectTool")
	else:
		return red_config
	
	if texture != null:
		# If this is a custom colour
		if (texture.resource_path.left(12) == "res://packs/"):
			packID = texture.resource_path.right(12).split("/")[0]
		else:
			return red_config
		
	# For each asset pack in the manifest
	for assetpack in Global.Header.AssetManifest:
		if packID == assetpack.ID:
			red_config["min_redness"] = assetpack.MinRedness
			red_config["red_tolerance"] = assetpack.MinSaturation
			red_config["min_saturation"] = assetpack.RedTolerance
			break

	return red_config

# function to find texture brightness
func get_texture_brightness_range(texture: Texture) -> Dictionary:

	var min_brightness = 1.0
	var max_brightness = 0.0
	var brightness_data = {}

	outputlog("get_texture_brightness_range",2)

	# If we have already calculated the brightness data then don't do it again
	if not get_brightness_data(texture.resource_path)["min_gray"] < 0:
		
		brightness_data = get_brightness_data(texture.resource_path)
		min_brightness = brightness_data["min_gray"]
		max_brightness = brightness_data["max_gray"]

	else:

		var image = texture.get_data()
		image.lock()  # Lock to access pixels

		min_brightness = 1.0
		max_brightness = 0.0

		for y in range(image.get_height()):
			for x in range(image.get_width()):
				var color = image.get_pixel(x, y)
				var brightness = color.r * 0.299 + color.g * 0.587 + color.b * 0.114  # Luminance formula
				
				if color.a > 0.1:
					min_brightness = min(min_brightness, brightness)
					max_brightness = max(max_brightness, brightness)

		image.unlock()

	# Round the brightness data down to the nearest 
	min_brightness = round(min_brightness / LEVELS_SLIDER_STEP) * LEVELS_SLIDER_STEP
	max_brightness = round(max_brightness / LEVELS_SLIDER_STEP) * LEVELS_SLIDER_STEP

	# Store the brightness data
	set_brightness_data(texture.resource_path, min_brightness, max_brightness)
	return {"min_gray": min_brightness, "max_gray": max_brightness}

# Function to determine if any of the shader parameters are different between two configs, ie ignore the colours
func is_shader_config_the_same(colour_config_a, colour_config_b) -> bool:

	var copy_a = colour_config_a.duplicate(true)
	var copy_b = colour_config_b.duplicate(true)

	# Remove the colour from the dictionary
	copy_a.erase("colour")
	copy_b.erase("colour")

	# Remove texture from the dictionary
	copy_a.erase("texture")
	copy_b.erase("texture")

	return is_the_same(copy_a, copy_b)


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

# Function to find if the node_id referenced is already colourised			
func is_node_colourised(node_id: int):

	var record = customdatamanager.get_data(node_id)
	if record != null && Global.World.HasNodeID(node_id):
		if record["shader_type"] != "none":
			return true
	
	return false


# Function to return the shader type value from a set of booleans
func get_shader_type(make_colourised: bool, make_normalised: bool, make_white: bool, make_gradient: bool):

	if make_colourised:
		return "colourised"
	if make_normalised:
		return "normalised"
	if make_white:
		return "white"
	if make_gradient:
		return "gradient"

	return "none" 

# Function to return the colour string from the patternshape
func get_pattern_colour(patternshape):

	if patternshape != null:
		var definition = patternshape.Save(true)
		if definition != null:
			if definition.has("color"):
				return definition["color"]
	
	return null


# Function to get the preview node based on tool_type
func get_preview_node(tool_type):

	outputlog("get_preview_node: " + str(tool_type),2)

	# Select the right preview type
	match tool_type:
		"ObjectTool","ScatterTool":
			return Global.Editor.Tools[tool_type].Preview
		"PathTool":
			return Global.Editor.Tools[tool_type].ActivePath
	return null


# Function to determine if the selected list only contains custom coloured objects
func is_selection_only_custom_colour_objects():

	outputlog("is_selection_only_custom_colour_objects",2)

	for node in Global.Editor.Tools["SelectTool"].Selected:
		if get_node_type(node) == "objects":
			if not node.HasCustomColor():
				return false
		else:
			return false
	
	return true

# Function to remove the tint colour config from custom colour nodes.
# Note that this allows us to have tint colours active in the UI without propagating them to colorable objects.
# However this prevents us from tinting colorable objects, eg setting them to semi-transparent
func remove_tint_colour_from_custom_colour_objects(node, colour_config):

	outputlog("remove_tint_colour_from_custom_colour_objects",2)

	if get_node_type(node) == "objects":
		if node.HasCustomColor():
			outputlog("current colour: " + str(colour_config["colour"]),2)
			colour_config["colour"] = Color.white.to_html()
			outputlog("resource_path: " + str(node.Texture.resource_path),2)
			outputlog("current custom colour: " + str(node.GetCustomColor().to_html()),2)
			outputlog("tint colour removed",2)
			
	return colour_config

# Correct the custom colour of the node
func correct_custom_colour(tool_type, node):

	# Get the valid custom colour list
	var valid_colour_list = get_valid_custom_colours(tool_type)
	# If for some reason the custom colour of the node is not in that list then call for a new random value from that list
	if not node.GetCustomColor().to_html() in valid_colour_list || true:
		# Get a new random colour
		var colour = get_random_colour_from_colour_palette(ui_config[tool_type]["main"]["custom_color_palette"])
		outputlog("node colour is invalid, setting a new random value: " + str(node.get_meta("node_id")) + " new colour value: " + str(colour),2)
		# Set it
		node.SetCustomColor(Color(colour))

# Function to get the list of valid custom colours from the standard DD palette
func get_valid_custom_colours(tool_type):

	var palette = ui_config[tool_type]["main"]["custom_color_palette"]
	var valid_colour_list = []

	# For each of the selected colours in the palette, add the html to the list
	for index in palette.get_selected_items():
		valid_colour_list.append(palette.colorList.get_item_icon_modulate(index).to_html())
	
	# Check if the displayed colour is a preset and if not add it as an extra colour
	if not palette.color.to_html() in valid_colour_list:
		valid_colour_list.append(palette.color.to_html())
	
	return valid_colour_list

# Function to select a random colour from the scatter tool main colour palette
func get_random_colour_from_colour_palette(palette) -> Color:

	outputlog("get_random_colour_from_colour_palette", 2)

	var colour_options = [-1]
	var index = -1

	# If the main colour is white and we only have one selected preset, assume that the selected preset is not required. Note this is marginally better than forcing the palette to have a white preset.
	if palette.color == Color.white && palette.colorList.get_selected_items().size() < 2:
		outputlog("palette color is white and selection is only one item",2)

		return palette.color

	# Build an array from the main colour and any selected preset colour values
	colour_options.append_array(palette.colorList.get_selected_items())

	outputlog("colour_options: " + str(colour_options),2)

	# Choose a random index from the list which gives us a random colour
	index = colour_options[ randi() % colour_options.size() ]

	# Return the appropriate colour, using the main colour when index is -1
	if index == -1:
		outputlog("Colour: " + str(palette.color.to_html()),2)
		return palette.color
	else:
		outputlog("Colour: " + str(palette.colorList.get_item_icon_modulate(index).to_html()),2)
		return palette.colorList.get_item_icon_modulate(index)


#########################################################################################################
##
## DD COLOUR PALETTES FUNCTIONS & SIGNALS
##
#########################################################################################################


# Function to register all the custom color palettes in the ui config dictionary
func find_all_custom_color_palettes():

	var custom_color_control_type = "custom_color_palette"
	for location in ["select","main"]:
		# For custom colour palette tools
		for tool_type in ["ObjectTool","ScatterTool","PathTool"]:
			custom_color_control_type = "custom_color_palette"
			# Skip Select and scatter tool
			if location == "select" && tool_type == "ScatterTool":
				continue
			
			find_custom_color_palette(tool_type, location, custom_color_control_type)
			if ui_config[tool_type][location][custom_color_control_type] != null:
				ui_config[tool_type][location][custom_color_control_type].colorPickerPopup.connect("popup_hide", self, "on_dd_custom_color_control_changed",[0,0,tool_type,location])
				ui_config[tool_type][location][custom_color_control_type].colorList.connect("item_selected", self, "on_dd_custom_color_control_changed",[0,tool_type,location])
				ui_config[tool_type][location][custom_color_control_type].colorList.connect("multi_selected", self, "on_dd_custom_color_control_changed",[tool_type,location])
				

		# For custom colour picker button tools
		for tool_type in ["PatternShapeTool","WallTool"]:
			custom_color_control_type = "custom_color_button"
			find_custom_color_palette(tool_type, location, custom_color_control_type)
			if ui_config[tool_type][location][custom_color_control_type] != null:
				# Get the popup and link when it hides
				ui_config[tool_type][location][custom_color_control_type].get_popup().connect("popup_hide", self, "on_dd_custom_color_control_changed",[0,0,tool_type,location])
				ui_config[tool_type][location][custom_color_control_type].connect("color_changed", self, "on_dd_custom_color_control_changed",[0,tool_type,location])
				ui_config[tool_type][location][custom_color_control_type].get_parent().get_child(1).connect("pressed", self, "on_dd_custom_color_control_changed",[0,0,tool_type,location])


# Function to find and store a reference to the standard custom color palettes for each tool and location
func find_custom_color_palette(tool_type: String, location: String, custom_color_control_type: String):

	outputlog("find_custom_color_palette: " + str(tool_type) + " " + str(location) + " " + str(custom_color_control_type),0)

	# create ui_config dictionary entries if they don't exist
	if not ui_config.has(tool_type):
		ui_config[tool_type] = {}
	if not ui_config[tool_type].has(location):
		ui_config[tool_type][location] = {}

	if location == "main":
		match tool_type:
			"PathTool":
				ui_config[tool_type][location][custom_color_control_type] = null
				ui_config[tool_type][location]["custom_color_label"] = null
			"ObjectTool","ScatterTool":
				ui_config[tool_type][location][custom_color_control_type] = Global.Editor.Tools[tool_type].Controls["CustomColor"]
				ui_config[tool_type][location]["custom_color_label"] = Global.Editor.Tools[tool_type].Controls["CustomColor"].get_parent().get_child(Global.Editor.Tools[tool_type].Controls["CustomColor"].get_index()-1)
			"PatternShapeTool","WallTool":
				ui_config[tool_type][location][custom_color_control_type] = Global.Editor.Tools[tool_type].Controls["Color"]
				ui_config[tool_type][location]["custom_color_label"] = Global.Editor.Tools[tool_type].Controls["Color"].get_parent().get_parent().get_child(Global.Editor.Tools[tool_type].Controls["Color"].get_parent().get_index()-1)
	else:
		match tool_type:
			"PathTool":
				ui_config[tool_type][location][custom_color_control_type] = null
				ui_config[tool_type][location]["custom_color_label"] = null
			"ObjectTool","ScatterTool":
				ui_config[tool_type][location][custom_color_control_type] = Global.Editor.Tools["SelectTool"].Controls["CustomColor"]
				ui_config[tool_type][location]["custom_color_label"] = Global.Editor.Tools["SelectTool"].Controls["CustomColor"].get_parent().get_child(Global.Editor.Tools["SelectTool"].Controls["CustomColor"].get_index()-1)
			"PatternShapeTool":
				ui_config[tool_type][location][custom_color_control_type] = Global.Editor.Tools["SelectTool"].Controls["PatternColor"]
				ui_config[tool_type][location]["custom_color_label"] = Global.Editor.Tools["SelectTool"].Controls["PatternColor"].get_parent().get_parent().get_child(Global.Editor.Tools["SelectTool"].Controls["PatternColor"].get_parent().get_index()-1)
			"WallTool":
				ui_config[tool_type][location][custom_color_control_type] = Global.Editor.Tools["SelectTool"].Controls["WallColor"]
				ui_config[tool_type][location]["custom_color_label"] = Global.Editor.Tools["SelectTool"].Controls["WallColor"].get_parent().get_parent().get_child(Global.Editor.Tools["SelectTool"].Controls["WallColor"].get_parent().get_index()-1)

# When a DD custom colour control changes the colour
func on_dd_custom_color_control_changed(_ignore_this, _ignore_this_too, tool_type: String, location: String):

	outputlog("on_dd_custom_color_control_changed",2)

	var focus = Global.Editor.GetFocus()

	outputlog("focus is: " + str(focus),2)

	# Pass to the colourthings class. Noting that it isn't necessary to also pass to the EdgeBlurPatterns as the ColourThings class will deal with this.
	colourthings.on_dd_custom_color_control_changed(_ignore_this, _ignore_this_too, tool_type, location)


#########################################################################################################
##
## DD PATTERNSHAPE ROTATION FUNCTIONS & SIGNALS
##
#########################################################################################################

# Function to find the grid menu of the patternshape tool menu
func find_official_patternshape_rotation_slider(location: String):

	outputlog("find_official_patternshape_color_palette",0)

	var vbox
	var find_text = ["ROTATION"]
	var found_label = false

	# Depending on the location find the enclosing vbox
	if location == "main":
		return
	else:
		vbox = Global.Editor.Toolset.GetToolPanel("SelectTool").patternShapeOptions

	# Look in each element of the panel.Align vbox
	for element in vbox.get_children():
		if element is Label:
			if element.text.to_upper() in find_text:
				found_label = true
		# If the node is a n hbox with a hslider in it then it should be the right thing
		if element is HBoxContainer && found_label:
			for thing in element.get_children():
				if thing is HSlider:
					return thing		
	
	return null

# Captpure the signals from grid menu
func setup_value_changed_signals_from_patternshape_rotation_slider(location: String):

	outputlog("setup_value_changed_signals_from_patternshape_rotation_slider",0)

	var slider = find_official_patternshape_rotation_slider(location)
	if slider != null:
		if not ui_config.has(location):
			ui_config[location] = {}
		ui_config[location]["rotation_slider"] = slider
		slider.connect("value_changed", self, "on_patternshape_rotation_slider_changed",[location])

# Called when the patternshape rotation slider changes
func on_patternshape_rotation_slider_changed(value, location: String):
	
	outputlog("on_patternshape_rotation_slider_changed: " + str(location),2)

	if location == "select":
		refresh_selected_nodes()
		
# Function to read the data for selected nodes and reapply the shader parameters as needed
func refresh_selected_nodes():

	outputlog("refresh_selected_nodes",2)

	if Global.Editor.Tools["SelectTool"].Selected.size() > 0:
		for node in Global.Editor.Tools["SelectTool"].Selected:
			combinedshader.refresh_node(node)


#########################################################################################################
##
## DD GRID MENUS FUNCTIONS & SIGNALS
##
#########################################################################################################

# Find all the official patternshape grid menus
func find_official_gridmenus():

	for tool_type in ["PatternShapeTool","WallTool"]:
		# create ui_config dictionary entries if they don't exist
		if not ui_config.has(tool_type):
			ui_config[tool_type] = {}

		for location in ["main", "select"]:
			if not ui_config[tool_type].has(location):
				ui_config[tool_type][location] = {}
			
			ui_config[tool_type][location]["gridmenu"] = find_official_gridmenu(tool_type, location)
			if ui_config[tool_type][location]["gridmenu"] != null:
				ui_config[tool_type][location]["gridmenu"].connect("item_selected", self, "_on_item_selected_in_gridmenu",[tool_type,location])

# Function to find the grid menu of the patternshape tool menu
func find_official_gridmenu(tool_type: String, location: String):

	outputlog("find_official_gridmenu: " +  str(tool_type) + " " +  str(location),0)

	# Depending on the location find the enclosing vbox
	if location == "main":
		return Global.Editor.Tools[tool_type].Controls["Texture"]
	else:
		match tool_type:
			"WallTool":
				return Global.Editor.Tools["SelectTool"].Controls["WallTexture"]
			"PatternShapeTool":
				return Global.Editor.Tools["SelectTool"].Controls["PatternTexture"]
			"PortalTool":
				return Global.Editor.Tools["SelectTool"].Controls["PortalTexture"]
			_:
				return null

# Function to respond when a new pattern is selected in the gridmenu
func _on_item_selected_in_gridmenu(_id: int, tool_type: String, location: String):

	outputlog("_on_item_selected_in_gridmenu",2)
	colourthings.refresh_combined_ui_stored_state(tool_type, location)

	# If the location is select then update any selected items
	if location == "select":
		if Global.Editor.Tools["SelectTool"].Selected.size() > 0:
			colourthings.set_colour_of_selection(tool_type, false)

#########################################################################################################
##
## CUSTOM DATA DRIVEN FUNCTIONS
##
#########################################################################################################

# Function to apply custom data to the node, noting this should only be called from a data function
func apply_custom_data_to_node(node: Node2D, config: Dictionary):

	outputlog("apply_custom_data_to_node: " + str(node.get_meta("node_id")),2)

	if Global.World.HasNodeID(node.get_meta("node_id")):
		combinedshader.set_custom_attributes_on_node(node, config)
		# Required of this is a copy data driven function
		customdatamanager.set_data(node.get_meta("node_id"), config)

#########################################################################################################
##
## HISTORY RECORD FUNCTIONS FOR UNDO & REDO
##
#########################################################################################################

# Create custom history record, called when a colour preset is selected, the color picker is closed, or a slider timer finishes
func create_update_custom_history(_ignore_this, _tool_type: String, _location: String, delay_secs: float):

	combinedshader.create_update_custom_history(delay_secs)

#########################################################################################################
##
## INITIALISE SUPPORTING CLASSES FUNCTIONS
##
#########################################################################################################

func initialise_customdatamanager():

	# Set up Custom Data Manager which deals with data acess and manages copy and paste and duplicate level features
	CustomDataManager = ResourceLoader.load(Global.Root + "CustomDataManager.gd", "GDScript", true)
	customdatamanager = CustomDataManager.new()
	customdatamanager.global = Global
	if Engine.has_signal("_lib_register_mod"):
		customdatamanager.logging_level = int(_lib_mod_config.datamanager_log_level)
	# Find new level function
	customdatamanager.find_new_level_window()

	# Connect to the signal called when a new apply custom data event occurs
	customdatamanager.connect("apply_custom_data_to_node", self, "apply_custom_data_to_node")

	# Functions to prepare the copy and paste actions
	customdatamanager.register_copy_keys_action()
	customdatamanager.register_paste_keys_action()
	# Send the message to the custom data manager
	Global.Editor.Toolset.GetToolPanel("SelectTool").copyButton.connect("pressed",customdatamanager,"store_copy_data")
	Global.Editor.Toolset.GetToolPanel("SelectTool").pasteButton.connect("pressed",customdatamanager,"apply_custom_data_to_pasted_nodes")

	# Function to migrate the legacy data into the new structure
	customdatamanager.migrate_legacy_modmapdata()

	

func initialise_combinedshader():

	CombinedShader = ResourceLoader.load(Global.Root + "CombinedShader.gd", "GDScript", true)
	combinedshader = CombinedShader.new()
	combinedshader.universalshader = ResourceLoader.load(Global.Root + "shaders/universalshader.shader","Shader",true)
	combinedshader.customdatamanager = customdatamanager
	combinedshader.reference_to_script = Script

	if Engine.has_signal("_lib_register_mod"):
		combinedshader.logging_level = int(_lib_mod_config.combinedshader_log_level)

# Initialise the ColourThings class
func initialise_colourthings():

	ColourThings = ResourceLoader.load(Global.Root + "ColourThings.gd", "GDScript", true)
	colourthings = ColourThings.new()
	colourthings.global = Global
	if Engine.has_signal("_lib_register_mod"):
		colourthings.logging_level = int(_lib_mod_config.colourthings_log_level)
		colourthings.gradientmap_log_level = int(_lib_mod_config.gradientmap_log_level)
		colourthings.gradientpresets_log_level = int(_lib_mod_config.gradientpresets_log_level)

	colourthings.customdatamanager = customdatamanager
	colourthings.combinedshader = combinedshader
	colourthings.mod_tool_panel = mod_tool_panel
	colourthings.initialise()

	

# Initialise the ColourThings class
func initialise_edgeblurpatterns():

	EdgeBlurPatterns = ResourceLoader.load(Global.Root + "EdgeBlurPatterns.gd", "GDScript", true)
	edgeblurpatterns = EdgeBlurPatterns.new()
	if Engine.has_signal("_lib_register_mod"):
		edgeblurpatterns.logging_level = int(_lib_mod_config.edgeblur_log_level)
	edgeblurpatterns.global = Global
	edgeblurpatterns.customdatamanager = customdatamanager
	edgeblurpatterns.combinedshader = combinedshader
	edgeblurpatterns.initialise()

	


# Initialise the ColourThings class
func initialise_modifypaths():

	ModifyPaths = ResourceLoader.load(Global.Root + "ModifyPaths.gd", "GDScript", true)
	modifypaths = ModifyPaths.new()
	if Engine.has_signal("_lib_register_mod"):
		modifypaths.logging_level = int(_lib_mod_config.modifypaths_log_level)
	modifypaths.global = Global
	modifypaths.customdatamanager = customdatamanager
	modifypaths.combinedshader = combinedshader
	modifypaths.reference_to_script = Script
	modifypaths.initialise()

	
# Initialise the ColourThings class
func initialise_colourterrain():

	ColourTerrain = ResourceLoader.load(Global.Root + "ColourTerrain.gd", "GDScript", true)
	colourterrain = ColourTerrain.new()
	if Engine.has_signal("_lib_register_mod"):
		colourterrain.logging_level = int(_lib_mod_config.colourterrain_log_level)
	colourterrain.global = Global
	colourterrain.reference_to_script = Script
	colourterrain.ui_config["gradient_map"] = colourthings.ui_config["gradient_map"]
	colourterrain.initialise()
	
#########################################################################################################
##
## REGISTER ACTIONS FUNCTION
##
#########################################################################################################

# Function to register an action for left mouse click
func register_left_mouse_click_action():

	var event = InputEventMouseButton.new()

	event.pressed = true
	event.button_index = 1 #Left mouse button

	if not InputMap.has_action("left_mouse_click"):
		InputMap.add_action("left_mouse_click",0.5)
		InputMap.action_add_event("left_mouse_click", event)

#########################################################################################################
##
## SELECT TOOL SIGNALS FUNCTION
##
#########################################################################################################

# Function to set up signals based on the options vboxes changing visibility
func setup_select_tool_options_change():

	outputlog("setup_select_tool_options_change")

	var vbox

	for tool_type in BUILD_THESE_TOOLS:
		# If the options vbox is not null and visible
		vbox = find_select_vbox(tool_type)
		if vbox != null:
			vbox.connect("visibility_changed", self, "on_select_tool_option_visibility_changed", [vbox, tool_type])

# Function to respond when a select tool option becomes visible or hidden
func on_select_tool_option_visibility_changed(vbox: VBoxContainer, tool_type: String):

	outputlog("on_select_tool_option_visibility_changed: " + str(tool_type) + " visible: " + str(vbox.visible),2)

	# If it has become visible then
	if vbox.visible:
		if colourthings != null:
			# Move the gradient map to that tool_type's options vbox
			colourthings.move_gradient_location(tool_type,"select")

# Function to check if the selection has changed
func has_selection_changed() -> bool:

	outputlog("has_selection_changed: " + str(Global.Editor.Tools["SelectTool"].Selected),4)

	# Check if it has changed from the stored version and update it if it has changed
	if not is_the_same(store_last_valid_selection, Global.Editor.Tools["SelectTool"].Selected):
		store_last_valid_selection = Global.Editor.Tools["SelectTool"].Selected
		return true
	else:
		return false

#########################################################################################################
##
## PATH TOOL SIGNALS FUNCTION
##
#########################################################################################################

# Function to register the path tool signals
func register_path_tool_signals():

	outputlog("register_path_tool_signals()",0)

	var tool_name = "PathTool"
	for signal_name in ["OnStartPath", "OnEndPath", "OnStartEditPath","OnUpdateEditPath","OnEndEditPath"]:
		outputlog("connecting to signal: " + str(signal_name),1)
		Global.Editor.Tools[tool_name].connect(signal_name, self, "on_signal_from_path_tool",[signal_name])

# Function to respond to signals from the path tool
func on_signal_from_path_tool(node: Node2D, signal_name: String):

	outputlog("on_signal_from_path_tool: node: " + str(node) + " signal_name: " + str(signal_name),2)

	match signal_name:
		"OnStartEditPath","OnUpdateEditPath","OnEndEditPath":
			# If the path has values that need updating then refresh it, ie fadein or fadeout
			if node.FadeIn || node.FadeOut:
				combinedshader.refresh_node(node)

		"OnStartPath":
			modifypaths.set_active_path_custom_values()
			colourthings.set_preview_colour("PathTool",true)
		
		"OnEndPath":
			colourthings.set_preview_colour("PathTool",true)
	
#########################################################################################################
##
## WALL TOOL SIGNALS FUNCTION
##
#########################################################################################################

# Function to register the path tool signals
func register_wall_tool_signals():

	outputlog("register_wall_tool_signals()",0)

	var tool_name = "WallTool"

	Global.Editor.Tools[tool_name].connect("OnStartWall", self, "on_signal_from_wall_tool",[null,"OnStartWall"])

	for signal_name in ["OnEndWall", "OnStartEditWall","OnUpdateEditWall","OnEndEditWall"]:
		outputlog("connecting to signal: " + str(signal_name))
		Global.Editor.Tools[tool_name].connect(signal_name, self, "on_signal_from_wall_tool",[signal_name])

# Function to respond to signals from the path tool
func on_signal_from_wall_tool(node: Node2D, signal_name: String):

	outputlog("on_signal_from_wall_tool: " + str(signal_name),3)

	match signal_name:
		"OnStartEditWall","OnUpdateEditWall","OnEndEditWall":
			# Colour resets on a wall when the points are edited so always refresh the node shader
			combinedshader.refresh_node(node)

		"OnStartWall", "OnEndWall":
			pass

#########################################################################################################
##
## PATTERNSHAPE TOOL SIGNALS FUNCTION
##
#########################################################################################################

# Function to register the path tool signals
func register_patternshape_tool_signals():

	outputlog("register_patternshape_tool_signals()",0)

	var tool_name = "PatternShapeTool"
	for signal_name in ["OnStartEditShape","OnUpdateEditShape","OnEndEditShape"]:
		outputlog("connecting to signal: " + str(signal_name),1)
		Global.Editor.Tools[tool_name].connect(signal_name, self, "on_signal_from_patternshape_tool",[signal_name])
	
	for signal_name in ["OnStartShape","OnEndShape"]:
		outputlog("connecting to signal: " + str(signal_name),1)
		Global.Editor.Tools[tool_name].connect(signal_name, self, "on_signal_from_patternshape_tool",[0,signal_name])

# Function to respond to signals from the path tool
func on_signal_from_patternshape_tool(node, signal_name: String):

	outputlog("on_signal_from_patternshape_tool: node: " + str(node) + " signal: " + str(signal_name),3)

	match signal_name:
		"OnStartEditShape","OnUpdateEditShape","OnEndEditShape":
			# If ths pattern has data
			if customdatamanager.has_data(node.get_meta("node_id")):
				# Get the node's config data
				var config = customdatamanager.get_data(node.get_meta("node_id"))
				# Check if EdgeBlur is active
				if config["has_edge_blur"]:
					# run the refresh on the node
					combinedshader.refresh_node(node)

		"OnStartShape":
			pass
		# Use this event not the node added function to trigger a custom application
		"OnEndShape":
			on_end_pattern_shape()

# Function called when an pattern shape is completed. Note that we need to do this as messing with the pattern before this point creates issues.
func on_end_pattern_shape():

	outputlog("on_end_pattern_shape",2)

	var node_id = Global.World.nextNodeID-1

	if Global.World.HasNodeID(node_id):
		var node = Global.World.GetNodeByID(node_id)
		# Noting this is sufficient for edgeblur patterns as well
		colourthings.set_tint_colour_on_new_node(node)

#########################################################################################################
##
## CORE SIGNALS RESPONSE FUNCTIONS
##
#########################################################################################################

# Called when a new node is added to the world
func on_new_node_added_to_world(node):

	outputlog("on_new_node_added_to_world: " + str(node),2)

	if Global.Editor.ActiveToolName in BUILD_THESE_TOOLS:
		# Exclude the pattern shape tool as it behaves oddly before the shape is complete.
		#if get_node_type(node) != "pattern_shapes":
		if Global.Editor.ActiveToolName != "PatternShapeTool":
			# Note we only need to call one new node function
			colourthings.set_tint_colour_on_new_node(node)

# Function to capture actions which only happen the first time we launch a tool
func on_tool_launch(tool_type: String):

	outputlog("on_tool_launch: " + str(tool_type) + " visible: " + str(Global.Editor.Toolset.GetToolPanel(tool_type).visible),2)

	# If we have just launched the tool
	if Global.Editor.Toolset.GetToolPanel(tool_type).visible:
		# Reset the store preview value.
		colourthings.store_preview_config = customdatamanager.DEFAULT_COMBINED_DATA.duplicate(true)
		colourthings.store_preview_config["texture"] = ""

		# Set the Preview colour of the object if we are in Object or Scatter tool
		if is_object_tool_type(tool_type):
			colourthings.touch_custom_color_palette(tool_type,"main")
			colourthings.set_preview_colour(tool_type, true)

		# Move the gradient map ui to the currently active tool
		if tool_type in ["ObjectTool","ScatterTool","PathTool","PatternShapeTool","WallTool","PortalTool"]:
			colourthings.ui_config["gradient_map"].move_location(tool_type, "main", colourthings.ui_config[tool_type]["main"]["gradient_button"].pressed)
		if tool_type in ["TerrainBrush"]:
			colourterrain.ui_config["gradient_map"].move_location(tool_type, "main", colourterrain.ui_config[tool_type]["main"]["gradient_button"].pressed)
	# If this is a close event
	else:
		# If this is a wall tool closure event
		if tool_type == "WallTool":
			# If we were in the middle of editing a wall and the switched tools (probably via a shortcut key), then refresh the wall colours
			colourthings.refresh_colours_on_walls(Global.World.GetCurrentLevel(), 0.0)

# Function to register each standard tool and call a function on_tool_launch when they are launched
func register_tool_launch_or_close_signals():

	var tool_list = ["ObjectTool","ScatterTool","PathTool","PatternShapeTool","SelectTool","WallTool", "PortalTool","TerrainBrush"]

	# For each tool in the list
	for tool_type in tool_list:
		if Global.Editor.Toolset.GetToolPanel(tool_type):
			Global.Editor.Toolset.GetToolPanel(tool_type).connect("visibility_changed", self, "on_tool_launch",[tool_type])

#########################################################################################################
##
## SCATTERBRUSH FUNCTIONS
##
#########################################################################################################

# Look for and register the scatter brush signals
func register_scatterbrush_signals():

	outputlog("register_scatterbrush_signals",0)

	# If the scatter brush mod is loaded
	if "uchideshi34.ScatterBrush" in Script.GetActiveMods():
		if Engine.has_signal("_lib_register_mod"):
			Global.API.ModSignalingApi.connect_deferred("scatterbrush_stroke_end",self, "on_scatterbrush_stroke_complete")

# When you see a scatter brush end event, this should happen after the new node ids have been assigned
func on_scatterbrush_stroke_complete(array_of_nodes):

	outputlog("on_scatterbrush_stroke_complete",2)

	if array_of_nodes == null:
		return
	
	# For each node in the last brush stroke
	for node in array_of_nodes:
		# Check if has a valid meta for node_id
		if node.has_meta("node_id"):
			outputlog("node: " + str(node) + " node_id: " + str(node.get_meta("node_id")),2)
			colourthings.set_tint_colour_on_new_node(node)

#########################################################################################################
##
## REFRESH NODE SIGNAL FUNCTIONS
##
#########################################################################################################

# Createa signal so other mods can call refresh node function.
func register_refresh_node_signal():

	outputlog("register_refresh_node_signal",0)

	# If _lib is loaded then add the refresh node signal
	if Engine.has_signal("_lib_register_mod"):
		Global.API.ModSignalingApi.add_user_signal("refresh_node_combined_shader")
		Global.API.ModSignalingApi.connect_deferred("refresh_node_combined_shader", combinedshader, "refresh_node")

#########################################################################################################
##
## PREVIEW & SELECTION CHANGED FUNCTIONS
##
#########################################################################################################

# Function called when preview node has changed
func preview_changed(tool_type: String):

	outputlog("preview_changed",2)

	# if this is an object type
	if is_object_tool_type(tool_type):
		# Refresh the preview colour
		colourthings.set_preview_colour(tool_type, true)

# Function called with the selection has changed
func selection_changed():

	outputlog("selection_changed",2)

	if colourthings != null: colourthings.set_colour_palette_to_selection()
	if edgeblurpatterns != null: edgeblurpatterns.set_edgeblur_ui_to_selection()
	if modifypaths != null: modifypaths.set_path_ui_to_selection()

# Function called when a new object is selected in the object library panel
func _on_new_object_selected_in_panel(index: int, selected: bool):

	# Route this to the colour things class
	if colourthings != null: colourthings._on_new_object_selected_in_panel(index, selected)

#########################################################################################################
##
## INPUT CAPTURE FUNCTIONS
##
#########################################################################################################

# Function to respond to unhandled mouse events
func on_unhandled_mouse_event(event):

	outputlog("on_unhandled_mouse_event",4)

	# Check the tool type
	match Global.Editor.ActiveToolName:
		"SelectTool":
			outputlog(Global.Editor.ActiveToolName,4)
			# If we are in a portal tool selection, then we are like dragging the portal
			if find_select_vbox("PortalTool").visible:
				outputlog("mouse_event - portal options",4)
				# If we have just released a drag action then refresh the wall colours as this may have been a portal move action
				if Input.is_action_just_released("left_mouse_click",true):
					refresh_colours_on_walls(Global.World.GetCurrentLevel(), 0.1)
			
		"PathTool":
			# If we are drawing
			if Global.Editor.Tools["PathTool"].isDrawing:
				# If the active path is not null
				if Global.Editor.Tools["PathTool"].ActivePath != null:
					# Check if fade is active
					if Global.Editor.Tools["PathTool"].ActivePath.FadeIn || Global.Editor.Tools["PathTool"].ActivePath.FadeOut:
						# Try a set preview colour if so
						colourthings.set_preview_colour("PathTool",true)


# Function to respond to unhandled key events
func on_unhandled_key_event(event):

	match Global.Editor.ActiveToolName:
		"SelectTool":
			if Input.is_action_just_pressed("paste_keys_pressed"):
				customdatamanager.apply_custom_data_to_pasted_nodes()
			# Capture a copy event from the key presses
			if Input.is_action_just_pressed("copy_keys_pressed"):
				customdatamanager.store_copy_data()

# Function to set up the 
func set_up_input_capture():
	var unhandledeventemitter = UnhandledEventEmitter.new()
	unhandledeventemitter.global = Global
	Global.World.add_child(unhandledeventemitter)
	unhandledeventemitter.connect("key_input", self, "on_unhandled_key_event")
	unhandledeventemitter.connect("mouse_input", self, "on_unhandled_mouse_event")

# Class to emit unhandled events
class UnhandledEventEmitter extends Node:

	var global = null

	signal key_input
	signal mouse_input

	func _unhandled_input(event):

		if not global.Editor.SearchHasFocus:
			var focus = global.Editor.GetFocus()
			if focus == null || (not focus is LineEdit && not focus is Tree):
				if event is InputEventKey:
					self.emit_signal("key_input", event)
	
	func _input(event):

		if not global.Editor.SearchHasFocus:
			var focus = global.Editor.GetFocus()
			if focus == null || (not focus is LineEdit && not focus is Tree):
				if event is InputEventMouse:
					self.emit_signal("mouse_input", event)

#########################################################################################################
##
## MAIN UPDATE FUNCTION
##
#########################################################################################################

# Check something every frame
func update(_delta):

	# Watch for a preview node change in one of the object tools and update the preview if it has. Noting this is needed as the added node signal fires before (or in parallel to when) the preview node has been updated.
	if is_object_tool_type(Global.Editor.ActiveToolName):
		# If the stored value is not the current object value
		if store_preview_node != Global.Editor.Tools[Global.Editor.ActiveToolName].Preview:
			# Call preview changed function
			preview_changed(Global.Editor.ActiveToolName)
			# Update the stored preview
			store_preview_node = Global.Editor.Tools[Global.Editor.ActiveToolName].Preview

	# A new node has been added since we last checked
	if Global.Editor.ActiveToolName == "SelectTool":
		# If the selection has changed then call the selection changed function
		if has_selection_changed():
			selection_changed()

	if (_begun_save and not Global.Editor.Infobar.spinBusyIcon):
		outputlog("save finished",2)
		_begun_save = false
		if colourterrain:
			colourterrain.save_terrain_data()		

#########################################################################################################
##
## _LIB CONFIG FUNCTIONS
##
#########################################################################################################

func make_lib_configs():

	# Create a config builder to ensure we can update the offset if needed
	var _lib_config_builder = Global.API.ModConfigApi.create_config()
	_lib_config_builder\
		.h_box_container().enter()\
			.label("Core Log Level ")\
			.option_button("core_log_level", 0, ["0","1","2","3","4"])\
		.exit()\
		.h_box_container().enter()\
			.label("ColourTerrain Log Level ")\
			.option_button("colourterrain_log_level", 0, ["0","1","2","3","4"])\
		.exit()\
		.h_box_container().enter()\
			.label("ColourThings Log Level ")\
			.option_button("colourthings_log_level", 0, ["0","1","2","3","4"])\
		.exit()\
		.h_box_container().enter()\
			.label("CombinedShader Log Level ")\
			.option_button("combinedshader_log_level", 0, ["0","1","2","3","4"])\
		.exit()\
		.h_box_container().enter()\
			.label("DataManager Log Level ")\
			.option_button("datamanager_log_level", 0, ["0","1","2","3","4"])\
		.exit()\
		.h_box_container().enter()\
			.label("EdgeBlur Log Level ")\
			.option_button("edgeblur_log_level", 0, ["0","1","2","3","4"])\
		.exit()\
		.h_box_container().enter()\
			.label("ModifyPaths Log Level ")\
			.option_button("modifypaths_log_level", 0, ["0","1","2","3","4"])\
		.exit()\
		.h_box_container().enter()\
			.label("NewHslider Log Level ")\
			.option_button("newhslider_log_level", 0, ["0","1","2","3","4"])\
		.exit()\
		.h_box_container().enter()\
			.label("Gradient Map Log Level ")\
			.option_button("gradientmap_log_level", 0, ["0","1","2","3","4"])\
		.exit()\
		.h_box_container().enter()\
			.label("Gradient Presets Log Level ")\
			.option_button("gradientpresets_log_level", 0, ["0","1","2","3","4"])\
		.exit()
	_lib_mod_config = _lib_config_builder.build()

	logging_level = int(_lib_mod_config.core_log_level)

#########################################################################################################
##
## VERSION CHECKER FUNCTIONS
##
#########################################################################################################

# Check whether a semver strng 2 is greater than string one. Only works on simple comparisons - DO NOT USE THIS FUNCTION OUTSIDE THIS CONTEXT
func compare_semver(semver1: String, semver2: String) -> bool:

	outputlog("compare_semver: semver1: " + str(semver1) + " semver2" + str(semver2),2)
	var semver1data = get_semver_data(semver1)
	var semver2data = get_semver_data(semver2)

	if semver1data == null || semver2data == null : return false

	if semver1data["major"] != semver2data["major"]:
		return semver1data["major"] < semver2data["major"]
	if semver1data["minor"] != semver2data["minor"]:
		return semver1data["minor"] < semver2data["minor"]
	if semver1data["patch"] != semver2data["patch"]:
		return semver1data["major"] < semver2data["major"]
	
	return false

# Parse the semver string
func get_semver_data(semver: String):

	var data = {}

	if semver.split(".").size() < 3: return null

	return {
		"major": int(semver.split(".")[0]),
		"minor": int(semver.split(".")[1]),
		"patch": int(semver.split(".")[2].split("-")[0])
	}

#########################################################################################################
##
## START FUNCTION
##
#########################################################################################################

# Main Script
func start() -> void:

	outputlog("ColourAndModifyThings Mod Has been loaded.")

	if "uchideshi34.ColourObjectsAndPaths" in Script.GetActiveMods() || "uchideshi34.EdgeBlurPatterns" in Script.GetActiveMods():
		Global.Editor.Warn("Mod Conflict","The ColourAndModifyThings should not be active at the same time as the ColourObjectsAndPaths or the EdgeBlurPatterns mods. They will conflict with each other and may break your maps.")
		
	randomize()

	# Register the mod with _lib if that mod is loaded
	if Engine.has_signal("_lib_register_mod"):
		Engine.emit_signal("_lib_register_mod", self)
		make_lib_configs()

		var _lib_mod_meta = Global.API.ModRegistry.get_mod_info("CreepyCre._Lib").mod_meta
		if _lib_mod_meta != null:
			if compare_semver("1.1.2", _lib_mod_meta["version"]):
				var update_checker = Global.API.UpdateChecker
				
				update_checker.register(Global.API.UpdateChecker.builder()\
														.fetcher(update_checker.github_fetcher("uchideshi34", "ColourAndModifyThings"))\
														.downloader(update_checker.github_downloader("uchideshi34", "ColourAndModifyThings"))\
														.build())
	ui_config = {}
	var category = "Settings"
	var unique_id = "uchideshi34.ColourAndModifyThings"
	var mod_name = "Colour Gradients"
	var icon = Global.Root + "icons/settings-icon.png"

	# Make mod tool for exporting and importing preset values
	mod_tool_panel = Global.Editor.Toolset.CreateModTool(self, category, unique_id, mod_name, icon)
	
	initialise_colourthings_modmapdata()

	initialise_customdatamanager()
	initialise_combinedshader()

	initialise_colourthings()
	initialise_edgeblurpatterns()
	initialise_modifypaths()
	initialise_colourterrain()

	# Find all the custom colour palettes so that we can refresh them so the Object Library shows the custom colours not the tint colours
	find_all_custom_color_palettes()
	find_official_gridmenus()

	register_left_mouse_click_action()
	register_tool_launch_or_close_signals()

	# Load all the data from the ModMapData record and apply it to the elements on the map
	customdatamanager.apply_custom_data_to_map()
	
	# Connect to the signal for the ObjectLibraryPanel to check if a new preview recolour is required and to suppress the tint ui for custom colour assets.
	Global.Editor.ObjectLibraryPanel.objectMenu.connect("item_selected", self, "_on_new_object_selected_in_panel",[false])
	Global.Editor.ObjectLibraryPanel.objectMenu.connect("multi_selected", self, "_on_new_object_selected_in_panel")

	# Reapply the portals colour as they get reset as part of the load procedure
	customdatamanager.apply_custom_data_to_map(["portals","walls"],0.5)

	# Link to the rotation slider in the select tool pattern shape so that it drives a colour update when changed.
	setup_value_changed_signals_from_patternshape_rotation_slider("select")

	# Set up signals
	Global.World.connect("OnAssignNode", self, "on_new_node_added_to_world")
	register_scatterbrush_signals()
	register_refresh_node_signal()
	set_up_input_capture()
	setup_select_tool_options_change()
	register_path_tool_signals()
	register_wall_tool_signals()
	register_patternshape_tool_signals()

	setup_detect_save()

#########################################################################################################
##
## DETECT SAVE FUNCTION (from _Lib)
##
#########################################################################################################

func setup_detect_save():

	outputlog("setup_detect_save")

	Global.Editor.Infobar.busyIcon.connect("visibility_changed", self, "_busy_icon_visibility_changed")

func _busy_icon_visibility_changed():
	match Global.Editor.Infobar.cornerInfo.text:
		"Saving...", "Backing up...", "SAVING", "BACKING_UP":
			_begun_save = true
	



	
