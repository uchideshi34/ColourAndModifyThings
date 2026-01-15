#########################################################################################################
##
## COLOUR OBJECTS AND PATHS MOD
##
#########################################################################################################

# Version 1.4.0
class_name ColourThings

var script_class = "tool"

var mod_tool_panel = null
var global = null

var last_node_id = -1
var store_last_valid_selection = []
var store_preview_config = {
	"texture": "",
	"shader_type": "none",
	"colour": "ffffffff"
	}
var store_active_path = null
var store_active_path_points = []
var is_editing_wall_points = false
var store_preview_node = null

var ui_config = {}

var GradientMap
var NewHSlider

const BUILD_THESE_TOOLS = ["ObjectTool", "ScatterTool", "PathTool", "PatternShapeTool","WallTool","PortalTool"]

const DEFAULT_COLOUR_PRESETS = ["ff6b3834", "ffac584c", "ff885848", "ffc0866c", "ff8d6d58", "fff3a768", "ff685848", "ff9c8868", "ffae9254", "ffd8c888", "ff888868", "ffaab478", "ff92aa58", "ff87a868", "ff679865", "ff789868", "ff546d56", "ff68887c", "ff667878", "ff809dab", "ff61788d", "ff535869", "ff786878", "ff886878", "ff905868", "ff994858", "ffffffff", "bfffffff", "7fffffff", "40ffffff"]
const TYPE_LOOKUP = {"ObjectTool": "objects","ScatterTool": "objects", "PathTool": "paths", "PatternShapeTool": "pattern_shapes", "WallTool": "walls", "PortalTool": "portals"}
const TOOL_TYPE_LOOKUP_BY_SELECTABLE = {"1": "WallTool", "2": "PortalTool", "3": "PortalTool", "4": "ObjectTool", "5": "PathTool", "6": "LightTool", "7": "PatternShapeTool", "8": "RoofTool"}
const HIDE_NONGRADIENT_BUTTON_TOOLS = ["PatternShapeTool","WallTool"]
const NON_CUSTOM_PALETTE_TOOLS = ["PatternShapeTool","WallTool"]

const LEVELS_SLIDER_STEP = 0.005
const SLIDER_WAIT_TIME = 1.0

var customdatamanager
var combinedshader

# Logging Functions
const ENABLE_LOGGING = true
var logging_level = 0
var gradientmap_log_level = 0
var gradientpresets_log_level = 0

#########################################################################################################
##
## UTILITY FUNCTIONS
##
#########################################################################################################

func outputlog(msg,level=0):
	if ENABLE_LOGGING:
		if level <= logging_level:
			printraw("(%d) <ColourThings>: " % OS.get_ticks_msec())
			print(msg)
	else:
		pass

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

	global.ModMapData["ColourObjects"]["brightness_data"][texture_path] = {"min_gray": min_gray, "max_gray": max_gray}

# Function to create a record for a texture's brightness min_gray and max_gray values so we don't have to keep calculating them
func get_brightness_data(texture_path: String) -> Dictionary:

	if global.ModMapData["ColourObjects"]["brightness_data"].has(texture_path):
		return global.ModMapData["ColourObjects"]["brightness_data"][texture_path]
	else:
		return {"min_gray": -1, "max_gray": -1}

# Function to create a record for a texture's brightness min_gray and max_gray values so we don't have to keep calculating them
func delete_brightness_data(texture_path: String):

	if global.ModMapData["ColourObjects"]["brightness_data"].has(texture_path):
		global.ModMapData["ColourObjects"]["brightness_data"].erase(texture_path)

#########################################################################################################
##
## UI CREATION & DISCOVERY FUNCTIONS
##
#########################################################################################################

# Function to return the ui_element or null if it doesn't exist
func get_ui_element(tool_type: String, location: String):

	if ui_config.has(tool_type):
		if ui_config[tool_type].has(location):
			return ui_config[tool_type][location]
	return null

# Function to hide non gradient buttons. Used for custom colour objects
func hide_non_gradient_buttons(tool_type: String, location: String):

	show_hide_non_gradient_buttons(tool_type, location, false)

# Function to show non-gradient buttons. Used for custom colour objects
func show_non_gradient_buttons(tool_type: String, location: String):

	show_hide_non_gradient_buttons(tool_type, location, true)

# Function to show or hide the non-gradient buttons
func show_hide_non_gradient_buttons(tool_type: String, location: String, show: bool):

	var ui_element = get_ui_element(tool_type,location)
	if ui_element == null:
		return
	# Get the list of non-gradient buttons
	var list_of_buttons = [ui_element["saturate_button"],ui_element["normalise_button"],ui_element["set_white_button"]]
	# Set those buttons to hidden
	for button in list_of_buttons:
		button.visible = show
		# If the button is pressed and we are hiding it, then we need to set it to not pressed
		if button.pressed && not show:
			button.pressed = false

# Function to move the gradient location
func move_gradient_location(tool_type: String, location: String):

	outputlog("move_gradient_location: " + str(tool_type) + " location: " + str(location),2)

	ui_config["gradient_map"].move_location(tool_type, "select", ui_config[tool_type][location]["gradient_button"].pressed)

# Function to register each standard tool and call a function on_tool_launch when they are launched
func register_tool_launch_or_close_signals():

	var tool_list = ["ObjectTool","ScatterTool","PathTool","PatternShapeTool","SelectTool","WallTool", "PortalTool"]

	# For each tool in the list
	for tool_type in tool_list:
		if global.Editor.Toolset.GetToolPanel(tool_type):
			global.Editor.Toolset.GetToolPanel(tool_type).connect("visibility_changed", self, "on_tool_launch",[tool_type])

# Function to register when select options vboxs become visible/hide
func register_select_options_launch_or_close_signals():

	var tool_list = ["ObjectTool","PathTool","PatternShapeTool","WallTool", "PortalTool"]

	# For each tool in the list
	for tool_type in tool_list:
		if find_select_vbox(tool_type):
			find_select_vbox(tool_type).connect("visibility_changed", self, "on_select_tool_option_launch",[tool_type])

# Function to create and set up the gradient map
func make_gradient_map_ui():

	outputlog("make_gradient_map_ui",0)

	ui_config["gradient_map"] = GradientMap.new()
	ui_config["gradient_map"].global = global
	ui_config["gradient_map"].tool_panel = mod_tool_panel
	
	ui_config["gradient_map"].initial_setup()
	ui_config["gradient_map"].connect("gradient_changed",self, "on_gradient_values_changed")
	ui_config["gradient_map"].connect("record_history",self, "create_update_custom_history", [0.0])
	ui_config["gradient_map"].connect("colour_picker_activated",self, "on_gradient_colour_picker_activated")
	
	ui_config["gradient_map"].reset()
	ui_config["gradient_map"].logging_level = gradientmap_log_level
	ui_config["gradient_map"].gradientpresets_log_level = gradientpresets_log_level

# When the gradient mod tool is opened, refresh the group list
func on_tool_enable(_tool_id):

	ui_config["gradient_map"].presetsdropdown.refresh_export_groups_menu_button()

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

# Function to make the UI for the colour buttons
func make_overridecolour_ui(tool_type: String, location: String):

	outputlog("make_overridecolour_ui: " + str(tool_type) + " location: " + str(location),0)

	var vbox
	var find_text = ["CUSTOM COLOR","CUSTOM_COLOR","TRANSITION_IN","TRANSITION IN","COLOR","STYLE"]
	var hint_tooltips = {
		"saturate_button": "When enabled, changes the saturation of the underlying asset colours.",
		"normalise_button": "When enabled, normalises the grayscale values so the brightest part of the asset is white and the darkest is black. There may be a delay when this option is used for large base images.",
		"set_white_button": "When enabled, convert all colours to full white preserving alpha values only.",
		"gradient_button": "When enabled, a gradient map will be applied to the asset.",
		"reset_button": "Reset to non-coloured state.",
		"levels_default_button": "When enabled, brightness levels set to default values for the underlying asset."
	}
	var tool_panel
	var color_presets
	var colour_palette = null
	var hbox = HBoxContainer.new()
	var ui_element
	
	# Load in the colour palette data from the ModMapData entry
	match tool_type:
		"ObjectTool","ScatterTool":
			color_presets = global.ModMapData["ColourObjects"]["palettes"]["ObjectTool"]
		"PathTool","PortalTool":
			color_presets = global.ModMapData["ColourObjects"]["palettes"][tool_type]
		"PatternShapeTool", "WallTool":
			color_presets = ["ffffffff"]
		_:
			return
	
	# Set up the tool panel and vbox values
	if location == "main":
		tool_panel = global.Editor.Toolset.GetToolPanel(tool_type)
		vbox = tool_panel.Align
	else:
		tool_panel = global.Editor.Toolset.GetToolPanel("SelectTool")
		vbox = find_select_vbox(tool_type)
		if vbox == null:
			return
	
	# Create the ui_config dictionary records
	if not ui_config.has(tool_type):
		ui_config[tool_type] = {}
	if not ui_config[tool_type].has(location):
		ui_config[tool_type][location] = {}
	ui_element = ui_config[tool_type][location]

	var index = 0
	# Look through all the children and when we find a label or button with the right text then store that index
	for thing in vbox.get_children():
		if thing is Label || thing is Button:
			if thing.text.to_upper() in find_text:
				index = thing.get_index()
		if thing is HBoxContainer:
			if thing.get_children().size() > 0:
				if thing.get_child(0) is Label:
					if thing.get_child(0).text.to_upper() in find_text:
						index = thing.get_index()
	
	# Make levels sliders
	ui_element["levels_slider"] = tool_panel.CreateRange("new_levels_slider_"+str(tool_type)+str(location), 0.0, 1.0, LEVELS_SLIDER_STEP, 0.0, 1.0)

		# If needed move the colour palette to the right vbox
	if location == "select":
		tool_panel.Align.remove_child(ui_element["levels_slider"])
		vbox.add_child(ui_element["levels_slider"])
	vbox.move_child(ui_element["levels_slider"],index)

	# Make levels active and options hbox
	ui_element["levels_hbox"] = HBoxContainer.new()
	vbox.add_child(ui_element["levels_hbox"])
	vbox.move_child(ui_element["levels_hbox"],index)
	var levels_label = make_label(ui_element["levels_hbox"],"Brightness Levels",0)
	levels_label.size_flags_horizontal = 3
	ui_element["levels_hbox"].visible = false
	ui_element["levels_slider"].visible = false

	# Make the timer for the levels slider to manage history creation
	ui_element["levels_slider_timer"] = Timer.new()
	ui_element["levels_slider_timer"].one_shot = true
	ui_element["levels_slider_timer"].auto_start = false
	ui_element["levels_slider_timer"].wait_time = SLIDER_WAIT_TIME
	ui_element["levels_slider"].add_child(ui_element["levels_slider_timer"])
	ui_element["levels_slider_timer"].connect("timeout", self, "create_update_custom_history",[null,tool_type,location,0.0])
	
	# Make levels reset button to restore the default values of the assets
	ui_element["levels_default_button"] = make_button(ui_element["levels_hbox"], "icons/shadow-icon.png", hint_tooltips["levels_default_button"], true)
	ui_element["levels_default_button"].pressed = true
	ui_element["levels_default_button"].connect("toggled", self, "_on_levels_default_button_pressed",[tool_type,location])

	# Make saturation slider
	ui_element["saturation_slider"] = NewHSlider.new(vbox, 1.0, 0.0, 4.0, 0.01, false)
	vbox.move_child(ui_element["saturation_slider"].hbox,index)
	ui_element["saturation_label"] = make_label(vbox,"Saturation",index)
	ui_element["saturation_slider"].hbox.visible = false
	ui_element["saturation_label"].visible = false
	ui_element["saturation_slider"].connect("emit_history_event_signal", self, "create_update_custom_history",[null,tool_type,location,0.0])
	
	
	# Make the colour palette if it isn't a Pattern or Wall tool
	if not tool_type in ["PatternShapeTool","WallTool"]:

		# Make opacity slider
		ui_element["opacity_slider"] = NewHSlider.new(vbox, 255, 0, 255, 1, false)
		vbox.move_child(ui_element["opacity_slider"].hbox,index)
		make_label(ui_element["opacity_slider"].hbox,"Opacity",0)

		# If we are in the main scatter tool, then we want to be able to select multiple colour preset
		if tool_type == "ScatterTool" && location == "main":
			colour_palette = tool_panel.CreateColorPalette("new_palette"+str(tool_type)+str(location),false,"ffffffff", color_presets, true, true)
		# Works around a bug where initToolColor is true causes the creation to fail for PatternShapeTool when no default assets are available. Note we could simply remove the creation of the palette here.
		elif tool_type == "PatternShapeTool":
			colour_palette = tool_panel.CreateColorPalette("new_palette"+str(tool_type)+str(location),false,"ffffffff", color_presets, false, false)
		else:
			colour_palette = tool_panel.CreateColorPalette("new_palette"+str(tool_type)+str(location),false,"ffffffff", color_presets, false, true)

		# Connect to signal to check if a preset has been removed
		colour_palette.colorList.connect("item_selected",self,"_on_new_colour_palette_item_selected",[null,tool_type,location])
		colour_palette.colorList.connect("item_selected",self,"_on_preset_changed_in_palette",[null,tool_type,location])
		colour_palette.colorList.connect("multi_selected",self,"_on_new_colour_palette_item_selected",[tool_type,location])
		colour_palette.colorList.connect("multi_selected",self,"_on_preset_changed_in_palette",[tool_type,location])
		colour_palette.popup.connect("modal_closed",self,"_on_preset_changed_in_palette",[0,null,tool_type,location])
		colour_palette.colorPicker.connect("color_changed",self,"_on_tintcolour_ui_changed",[tool_type,location])
		colour_palette.paletteButton.hint_tooltip = "This colour (when not white) will tint the underlying asset similar to the lighting effect. If one of the grayscale options are enabled, this selected colour will work in a similar way to the Colorable feature."

		# Connect to signals to determine whether a history event should be recorded, ie when colour palette is closed
		colour_palette.colorPickerPopup.connect("popup_hide",self,"create_update_custom_history",[null,tool_type,location,0.2])
		# Check for a item selected signal but then delay the implementation by a bit in order for the actual colour change to complete
		colour_palette.colorList.connect("item_selected",self,"create_update_custom_history",[tool_type,location,0.2])


		# If needed move the colour palette to the right vbox
		if location == "select":
			tool_panel.Align.remove_child(colour_palette)
			vbox.add_child(colour_palette)
		vbox.move_child(colour_palette,index)
		ui_element["palette"] = colour_palette

		# Set up opacity slider signals
		ui_element["opacity_slider"].connect("value_changed", self, "_on_opacity_slider_ui_changed",[tool_type,location])
		ui_element["opacity_slider"].connect("emit_history_event_signal", self, "create_update_custom_history",[null,tool_type,location,0.0])
	else:
		ui_element["palette"] = null

	# Make the tint option control buttons
	vbox.add_child(hbox)
	vbox.move_child(hbox,index)
	var label = make_label(hbox,"Tint Color",0)
	label.size_flags_horizontal = 3
	ui_element["tint_hbox"] = hbox

	# Create colour option buttons
	ui_element["saturate_button"] = make_button(hbox, "icons/saturation-icon.png", hint_tooltips["saturate_button"], true)
	ui_element["saturate_button"].connect("toggled", self, "_on_colour_option_button_pressed",["saturation",tool_type,location, true])

	ui_element["normalise_button"] = make_button(hbox, "icons/shadow-icon.png", hint_tooltips["normalise_button"], true)
	ui_element["normalise_button"].connect("toggled", self, "_on_colour_option_button_pressed",["normalised",tool_type,location, true])

	ui_element["gradient_button"] = make_button(hbox, "icons/settings-icon.png", hint_tooltips["gradient_button"], true)
	ui_element["gradient_button"].connect("toggled", self, "_on_colour_option_button_pressed",["gradient",tool_type,location, true])

	ui_element["set_white_button"] = make_button(hbox, "icons/white-circle-icon.png", hint_tooltips["set_white_button"], true)
	ui_element["set_white_button"].connect("toggled", self, "_on_colour_option_button_pressed",["white",tool_type,location, true])

	# Create reset button
	ui_element["reset_button"] = make_button(hbox, "icons/trash-icon.png", hint_tooltips["reset_button"], false)
	ui_element["reset_button"].connect("pressed", self, "_on_reset_button_pressed",[tool_type,location])

	# Hide unneeded buttons
	if tool_type in HIDE_NONGRADIENT_BUTTON_TOOLS:
		ui_element["saturate_button"].visible = false
		ui_element["normalise_button"].visible = false
		ui_element["set_white_button"].visible = false
	
	# Link the signals at the end to stop early calls when the UI isn't complete	
	ui_element["levels_slider"].minSlider.connect("value_changed",self,"_on_levels_slider_value_changed",[tool_type,location])
	ui_element["levels_slider"].maxSlider.connect("value_changed",self,"_on_levels_slider_value_changed",[tool_type,location])

	# On saturation slider change
	ui_element["saturation_slider"].connect("value_changed",self,"_on_saturation_slider_value_changed",[tool_type,location])

# Make a button and return it
func make_button(parent_node, icon_path: String, hint_tooltip: String, toggle_mode: bool) -> Button:

	var button = Button.new()
	button.toggle_mode = toggle_mode
	button.icon = load_image_texture(icon_path)
	button.hint_tooltip = hint_tooltip
	parent_node.add_child(button)
	return button

# Function to show or hide the custom colour palette
func set_custom_color_palette_visible(tool_type: String, location: String, make_visible: bool):

	outputlog("set_custom_color_palette_visible",2)

	var ui_element = ui_config[tool_type][location]

	# If we have successfully identified the custom colour palettes then we show/hide them
	if ui_element["custom_color_palette"] != null && ui_element["custom_color_label"] != null:
		ui_element["custom_color_palette"].visible = make_visible
		ui_element["custom_color_label"].visible = make_visible
	
	# Choose whether to set the ui for custom colour buttons visible
	if is_object_tool_type(tool_type):
		# If we are aking the custom colours visible, then we hide the non-gradient buttons
		if make_visible:
			hide_non_gradient_buttons(tool_type,location)
		else:
			show_non_gradient_buttons(tool_type,location)
		
		# Set the palette invisible which is a bit odd for mixed selections
		ui_config[tool_type][location]["palette"].visible = not make_visible
		ui_config[tool_type][location]["opacity_slider"].hbox.visible = not make_visible

		# If we are in the main tool, then check whether we should update the object library custom colour to match the dd custom colour palette
		if location == "main":
			# It should always reflect the custom colour and DD sometimes takes from elsewhere
			set_object_library_grid_custom_colour_to_dd_palette_colour(tool_type,location)


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
				ui_config[tool_type][location][custom_color_control_type] = global.Editor.Tools[tool_type].Controls["CustomColor"]
				ui_config[tool_type][location]["custom_color_label"] = global.Editor.Tools[tool_type].Controls["CustomColor"].get_parent().get_child(global.Editor.Tools[tool_type].Controls["CustomColor"].get_index()-1)
			"PatternShapeTool","WallTool":
				ui_config[tool_type][location][custom_color_control_type] = global.Editor.Tools[tool_type].Controls["Color"]
				ui_config[tool_type][location]["custom_color_label"] = global.Editor.Tools[tool_type].Controls["Color"].get_parent().get_parent().get_child(global.Editor.Tools[tool_type].Controls["Color"].get_parent().get_index()-1)
	else:
		match tool_type:
			"PathTool":
				ui_config[tool_type][location][custom_color_control_type] = null
				ui_config[tool_type][location]["custom_color_label"] = null
			"ObjectTool","ScatterTool":
				ui_config[tool_type][location][custom_color_control_type] = global.Editor.Tools["SelectTool"].Controls["CustomColor"]
				ui_config[tool_type][location]["custom_color_label"] = global.Editor.Tools["SelectTool"].Controls["CustomColor"].get_parent().get_child(global.Editor.Tools["SelectTool"].Controls["CustomColor"].get_index()-1)
			"PatternShapeTool":
				ui_config[tool_type][location][custom_color_control_type] = global.Editor.Tools["SelectTool"].Controls["PatternColor"]
				ui_config[tool_type][location]["custom_color_label"] = global.Editor.Tools["SelectTool"].Controls["PatternColor"].get_parent().get_parent().get_child(global.Editor.Tools["SelectTool"].Controls["PatternColor"].get_parent().get_index()-1)
			"WallTool":
				ui_config[tool_type][location][custom_color_control_type] = global.Editor.Tools["SelectTool"].Controls["WallColor"]
				ui_config[tool_type][location]["custom_color_label"] = global.Editor.Tools["SelectTool"].Controls["WallColor"].get_parent().get_parent().get_child(global.Editor.Tools["SelectTool"].Controls["WallColor"].get_parent().get_index()-1)


#########################################################################################################
##
## SET UI TO SELECTED NODE VALUES FUNCTIONS
##
#########################################################################################################

# Function to set the colour ui to reflect the values of the passed node, noting that this should generally be a selected node
func set_colour_ui_to_selected_node_values(node: Node2D, tool_type: String):

	var location = "select"

	outputlog("set_colour_ui_to_selected_node_values",2)

	var node_id = global.Editor.Tools["SelectTool"].Selected[0].get_meta("node_id")
	outputlog("node_id: " + str(node_id),2)
	var ui_element = ui_config[tool_type][location]

	# If the first node is coloured then set the UI to match it but check whether it is already correct
	if customdatamanager.has_data(node_id):
		var node_data = customdatamanager.get_data(node_id)
		outputlog("node_data: " + str(node_data),2)

		# If the UI is not the same as the current pattern then update it so that it does reflect the node's config
		var colour_config = customdatamanager.get_combined_ui_stored_state(tool_type, location)
		outputlog("colour config: " + str(colour_config),2)
		# Update the colour of the palette (with triggering a signal so all selected nodes update)
		if not tool_type in NON_CUSTOM_PALETTE_TOOLS:
			ui_element["palette"].SetColor(Color(node_data["colour"]),false)
			ui_element["opacity_slider"].slider_and_spinbox_change(int(Color(node_data["colour"]).a * 255),true)

		# When we are using the DD custom colour palette, then force set the palette to the node item. This should be redundant but may cause race condition issues
		else:
			outputlog("trying force refresh",2)
			force_refresh_dd_custom_colour_ui_from_selected_node(node, tool_type)

		# Update the levels slider if needed
		match node_data["shader_type"]:
			# If the node is normalised then update its valuea
			"normalised":
				# There should always be a levels entry but check anyway
				if node_data.has("levels"):

					# Set the slider levels
					set_property_but_block_signals(ui_element["levels_slider"].minSlider, "value", node_data["levels"][0])
					set_property_but_block_signals(ui_element["levels_slider"].maxSlider, "value", node_data["levels"][2])

					# Update the default button value if it matches the first selected value
					var brightness_data = get_texture_brightness_range(get_asset_texture(node,tool_type))

					# Update the default button value to pressed or not pressed
					if is_equal_approx(brightness_data["min_gray"],node_data["levels"][0]) && is_equal_approx(brightness_data["max_gray"],node_data["levels"][2]):
						set_property_but_block_signals(ui_element["levels_default_button"], "pressed", true)
					else:
						set_property_but_block_signals(ui_element["levels_default_button"], "pressed", false)
								
			# Update the gradient if needed
			"gradient":
				# There should always be a gradient dictionary entry but check anywat
				if node_data.has("gradient"):
					outputlog("trying set gradient map",2)
					ui_config["gradient_map"].set_block_signals(true)
					ui_config["gradient_map"].set_gradient_values(node_data["gradient"])
					ui_config["gradient_map"].set_block_signals(false)
			
			"saturation":
				if node_data.has("saturation"):
					ui_element["saturation_slider"].slider_and_spinbox_change(node_data["saturation"], true)
		
		outputlog("get colour config: " + str(get_colour_config_from_ui(tool_type, location)),3)
		_on_colour_option_button_pressed(true, node_data["shader_type"], tool_type, location, false)

	# If there is no data then we have selected a non-coloured asset and should update the palette items accordingly
	else:
		# Reset to white
		if not tool_type in NON_CUSTOM_PALETTE_TOOLS:
			ui_config[tool_type][location]["palette"].SetColor(Color.white,false)
			ui_element["opacity_slider"].slider_and_spinbox_change(255,true)
		else:
			force_refresh_dd_custom_colour_ui_from_selected_node(node, tool_type)

		_on_colour_option_button_pressed(true, "none", tool_type, location, false)
	
	# Check if we have only selected custom colour objects and hide or show the non-gradient 
	if is_selection_only_custom_colour_objects() || tool_type in ["PatternShapeTool","WallTool"]:
		hide_non_gradient_buttons(tool_type,location)
	else:
		show_non_gradient_buttons(tool_type,location)
	
# Function to force the dd custom colour ui to match the selected node in case the timeframe for setting it is out of kilter with this mod
func force_refresh_dd_custom_colour_ui_from_selected_node(node: Node2D, tool_type: String):

	outputlog("force_refresh_dd_custom_colour_ui_from_selected_node: " + str(node) + "tool_type: " + str(tool_type),2)

	var location = "select"
	var ui_element = ui_config[tool_type][location]

	# Only do this for Patterns and Walls
	if not tool_type in NON_CUSTOM_PALETTE_TOOLS: return
	# If the node doesn't match the tool_type then do nothing
	if get_node_type(node) != TYPE_LOOKUP[tool_type]: return

	match tool_type:
		"PatternShapeTool":
			var color_string = get_pattern_colour(node)
			if color_string != null:
				ui_element["custom_color_button"].color = Color(color_string)
				outputlog("setting patternshape color: " + str(node) + " colour: " + str(color_string),2)
		
		"WallTool":
			ui_element["custom_color_button"].color = node.Color
			outputlog("setting wall color: " + str(node) + " colour: " + str(node.Color.to_html()),2)


# Function to look at the selected items in the select tool and change their colour if they are all of the correct type
func set_colour_palette_to_selection():

	var location = "select"
	var tool_type
	var colour_config

	# Get the first selectable node
	if global.Editor.Tools["SelectTool"].Selected.size() > 0:
		tool_type = TOOL_TYPE_LOOKUP_BY_SELECTABLE[str(global.Editor.Tools["SelectTool"].GetSelectableType(global.Editor.Tools["SelectTool"].Selected[0]))]
		if tool_type == null:
			return
	else:
		return
	
	outputlog("set_colour_palette_to_selection(): tool_type: " + str(tool_type),2)

	# If the Options vboxes are visible then only a single type is selected. This should always be the case when the function is called.
	# If we do not have only one type of asset chosen then return
	if find_select_vbox(tool_type) != null:
		# If the select options is not visible then we have multiple types and we should stop and return
		if not find_select_vbox(tool_type).visible:
			outputlog("select vbox not visible",2)
			if not check_all_nodes_of_same_type(global.Editor.Tools["SelectTool"].Selected):
				return
		
		set_colour_ui_to_selected_node_values(global.Editor.Tools["SelectTool"].Selected[0], tool_type)


# Check all nodes in list are the same type
func check_all_nodes_of_same_type(list_of_nodes) -> bool:

	if list_of_nodes.size() == 0: return true

	var type = get_node_type(list_of_nodes[0])

	for node in list_of_nodes:
		if get_node_type(node) != type:
			return false
	
	return true

#########################################################################################################
##
## GET VALUES FROM UI FUNCTIONS
##
#########################################################################################################

# Function to return a colour config from a ui_element
func get_colour_config_from_ui(tool_type: String, location: String, debug: bool = true):

	outputlog("get_colour_config_from_ui",3)
	var ui_element = ui_config[tool_type][location]

	var colour_config = {
		"shader_type": get_shader_type(ui_element["saturate_button"].pressed, ui_element["normalise_button"].pressed, ui_element["set_white_button"].pressed, ui_element["gradient_button"].pressed)
	}

	match colour_config["shader_type"]:
		# If we have a levels value present then add it to the colour config
		"normalised":
			colour_config["levels"] = [ui_element["levels_slider"].minSlider.value,0.0,ui_element["levels_slider"].maxSlider.value]
			colour_config["levels_default_brightness"] = ui_element["levels_default_button"].pressed

		# If this is a gradient type then add the UI's gradient config
		"gradient":
			colour_config["gradient"] = ui_config["gradient_map"].get_gradient_data(debug)
		
		"saturation":
			colour_config["saturation"] = ui_element["saturation_slider"].value

	# For patterns or walls
	if tool_type in NON_CUSTOM_PALETTE_TOOLS:
		if ui_element["custom_color_button"] != null:
			outputlog("custom_color_button is not null",3)
			outputlog("custom_color_button color: " + str(ui_element["custom_color_button"].color.to_html()),3)
			outputlog("custom_color_button picker color: " + str(ui_element["custom_color_button"].get_picker().color.to_html()),3)
			# Note we are using the color picker color here as there seems to be a delay in the colour palette updating
			colour_config["colour"] = ui_element["custom_color_button"].color.to_html()
		else:
			colour_config["colour"] = "ffffffff"
	else:
		# Note we are using the color picker color here as there seems to be a delay in the colour palette updating
		colour_config["colour"] = ui_element["palette"].colorPicker.color.to_html()	

	outputlog("colour_config: " + str(colour_config),3)

	return colour_config

#########################################################################################################
##
## UDPATE SELECTION WITH NEW VALUES FUNCTIONS
##
#########################################################################################################

# Function to look at the selected items in the select tool and change their colour if they are all of the correct type
func set_colour_of_selection(tool_type: String, reset_levels_to_default: bool):

	var location = "select"

	outputlog("set_colour_of_selection: " + str(tool_type) + " reset_levels: " + str(reset_levels_to_default),2)

	# Error check in case this is called with the ScatterTool
	if tool_type == "ScatterTool": return
	
	outputlog("selected: " + str(global.Editor.Tools["SelectTool"].Selected),3)
	
	# For each selected node 
	for selected_node in global.Editor.Tools["SelectTool"].Selected:
		outputlog("selected_node: " + str(selected_node),3)
		# Update some selected nodes with the colour values in the ui
		update_placed_node_with_colour_ui_values(selected_node, tool_type, location, reset_levels_to_default)
	
	# If there is something to update, we need to update the levels to reflect the brightness
	if reset_levels_to_default:
		if global.Editor.Tools["SelectTool"].Selected.size() > 0:
			# If we are resetting levels to default, then we need to update the levels ui to reflect the first selected node
			set_levels_ui_to_base_asset_brightness(tool_type, location, global.Editor.Tools["SelectTool"].Selected[0])


# Function to update a placed node with the colour values in the ui
func update_placed_node_with_colour_ui_values(node: Node2D, tool_type: String, location: String, reset_levels_to_default: bool):

	outputlog("update_placed_node_with_colour_ui_values",2)

	if node == null: return

	var node_id = node.get_meta("node_id")

	if not global.World.HasNodeID(node_id): return

	# Add or update the history data noting we can call this repeatedly and it will simply update the new state
	combinedshader.add_update_history_data(node_id, tool_type, get_data_or_default(node_id))

	# Get the colour config from the current ui settings
	var colour_config = get_colour_config_from_ui(tool_type,location)

	# If we are resetting the levels back to the default for that asset
	if reset_levels_to_default && colour_config["shader_type"] == "normalised":
		var brightness_data = get_texture_brightness_range(get_asset_texture(node, tool_type))
		colour_config["levels"] = [brightness_data["min_gray"],0.0,brightness_data["max_gray"]]
		
	colour_config = customdatamanager.merge_dict(get_data_or_default(node_id),colour_config)

	# Add or update the history data noting we can call this repeatedly and it will simply update the new state
	combinedshader.add_update_history_data(node_id, tool_type, colour_config)
			
	# Set the tint colour	
	set_tint_colour(node.get_meta("node_id"),TYPE_LOOKUP[tool_type], colour_config, false)

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
	for assetpack in global.Header.AssetManifest:
		if packID == assetpack.ID:
			red_config["min_redness"] = assetpack.MinRedness
			red_config["red_tolerance"] = assetpack.RedTolerance
			red_config["min_saturation"] = assetpack.MinSaturation
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
	if record != null && global.World.HasNodeID(node_id):
		if record["shader_type"] != "none":
			return true
	
	return false


# Function to return the shader type value from a set of booleans
func get_shader_type(make_saturation: bool, make_normalised: bool, make_white: bool, make_gradient: bool):

	if make_saturation:
		return "saturation"
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
			return global.Editor.Tools[tool_type].Preview
		"PathTool":
			return global.Editor.Tools[tool_type].ActivePath
	return null


# Function to determine if the selected list only contains custom coloured objects
func is_selection_only_custom_colour_objects():

	outputlog("is_selection_only_custom_colour_objects",2)

	for node in global.Editor.Tools["SelectTool"].Selected:
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
	if not node.GetCustomColor().to_html() in valid_colour_list:
		# Get a new random colour
		var colour = get_random_colour_from_colour_palette(ui_config[tool_type]["main"]["custom_color_palette"])
		var node_id = "none"
		if node.has_meta("node_id"):
			node_id = node.get_meta("node_id")
		outputlog("node colour is invalid, setting a new random value: " + str(node_id) + " new colour value: " + str(colour),2)
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
## CHANGE COLOUR FUNCTIONS
##
#########################################################################################################

# Function to convery a map node to grayscale
func set_custom_attributes_on_map_node(node, type: String, colour_config: Dictionary, force_shader: bool):

	if node == null:
		return
	
	var node_id = node.get_meta("node_id")

	outputlog("set_custom_attributes_on_map_node: node_id: " + str(node_id) + " type: " + str(type) + " colour_config: " + str(colour_config),2)

	if global.World.HasNodeID(node_id):
		
		# Check if the colour config is normalised and doesn't have predefined levels, find those from the brightness data if so
		if colour_config["shader_type"] == "normalised" && not colour_config.has("levels"):
			var texture = get_asset_texture(node, type)
			if texture != null:
				var brightness_range = get_texture_brightness_range(texture)
				if brightness_range != null:
					colour_config["levels"] = [brightness_range["min_gray"],0.0,brightness_range["max_gray"]]
		
		# Check for custom colour values
		if type == "objects":
			# If this is custom coloured
			if node.HasCustomColor():
				# Find the values for redness from the pack data and add them to the config payload
				colour_config["red_config"] = get_colourable_config_values(node)

		if colour_config["type"] != type:
			colour_config["type"] = type
		
		# Call the shader
		combinedshader.set_custom_attributes_on_node(node, colour_config)


# Function to respond to a call from the CustomDataManager which occurs when the map opens, levels are copied or assets are copy-pasted
func set_colour(node: Node2D, data: Dictionary):

	outputlog("set_colour", 2)

	if node.has_meta("node_id"):
		if global.World.HasNodeID(node.get_meta("node_id")):
			if not customdatamanager.is_data_default(data):
				outputlog("Data is not default so do something: " + str(data))
				set_tint_colour(node.get_meta("node_id"), data["type"], data, true)


# Applies the tint colour to the canvas item and stores the data in the mod data entry
func set_tint_colour(node_id: int, type: String, colour_config: Dictionary, force_shader: bool):

	outputlog("set_tint_colour: node_id: " + str(node_id) + " type: " + type + " colour_config: " + str(colour_config) + " force_shader: " + str(force_shader),2)
	var node 

	# Check that the node_id does really exist
	if global.World.HasNodeID(node_id):

		outputlog("node_id: " + str(node_id),2)
		node = global.World.GetNodeByID(node_id)
		outputlog("node: " + str(node),2)

		# Remove tint colour from any object that is colorable 
		colour_config = remove_tint_colour_from_custom_colour_objects(node, colour_config)

		# Set custom values on the node
		set_custom_attributes_on_map_node(node, type, colour_config, force_shader)

		# Update the data record for the node
		customdatamanager.set_data(node_id, colour_config)
	

# Function to set the object preview colour to match the colour in the tint
func set_preview_colour(tool_type: String, force_change: bool):

	var preview_node
	var ui_element = ui_config[tool_type]["main"]
	var colour
	var colour_config

	# Do nothing for patterns or walls
	if not tool_type in ["ObjectTool","ScatterTool","PathTool"]:
		return

	# Select the right preview type
	preview_node = get_preview_node(tool_type)
	
	# Error check if the preview_node is null
	if preview_node == null:
		outputlog("preview node is null",2)
		return
	
	outputlog("set_preview_colour: tool_type: " + str(tool_type) + " node: " + str(preview_node),2)

	# DEBUG auto set force change to true as this condition seems to cause issues when the mod thinks that nothing has changed
	force_change = true

	# Get the colour config from the current ui settings
	colour_config = customdatamanager.get_combined_ui_stored_state(tool_type, "main")

	# Define the colour for the new preview, choosing a random one if we are in the scatter tool
	if tool_type == "ScatterTool":
		colour = get_random_colour_from_colour_palette(ui_config["ScatterTool"]["main"]["palette"])
	else:
		colour = ui_element["palette"].color
	colour_config["colour"] = colour.to_html()

	# For normalised mode, where the default brightness is enabled
	if colour_config["shader_type"] == "normalised" && ui_element["levels_default_button"].pressed:
		# Update the levels ui
		set_levels_ui_to_base_asset_brightness(tool_type, "main", preview_node)
		# Retrieve the levels setting
		colour_config = customdatamanager.get_combined_ui_stored_state(tool_type, "main")
		# Reapply the calculated colour
		colour_config["colour"] = colour.to_html()
	
	# Remove any tint colour from the custom colour objects.
	colour_config = remove_tint_colour_from_custom_colour_objects(preview_node, colour_config)

	# Update stored values which include the colours
	store_preview_config = colour_config.duplicate(true)
	
	# Get the texture of the preview node, which is needed to know if the preview has changed to cycling through object library using scroll
	if get_asset_texture(preview_node,tool_type) != null:
		store_preview_config["texture"] = get_asset_texture(preview_node,tool_type).resource_path

	outputlog("store_preview_config: " + str(store_preview_config),2)

	# If there is no preview and the data is default only
	if customdatamanager.is_data_default(colour_config):

		# Correct the custom colour if it isn't right
		if is_object_tool_type(tool_type):
			check_and_correct_custom_colour(tool_type, preview_node)
		
		# Reset the preview to default
		reset_preview_node(preview_node, tool_type)
		return
	
	# Convert to grayscale which is only necessary if something other than colour has changed
	colour_config["type"] = TYPE_LOOKUP[tool_type]

	if colour_config["type"] == "objects":
		if preview_node.HasCustomColor():
			# Find the values for redness from the pack data and add them to the config payload
			colour_config["red_config"] = get_colourable_config_values(preview_node)

	# Apply custom settings to the node
	combinedshader.set_custom_attributes_on_node(preview_node, colour_config)


#########################################################################################################
##
## UI DRIVEN CHANGE FUNCTIONS
##
#########################################################################################################

# Function to respond to the signal from the gradient map when it changes
func on_gradient_values_changed(tool_type: String, location: String):

	outputlog("on_gradient_values_changed: tool_type: " + str(tool_type) + " location: " + str(location),2)
	# Update the stored ui config
	refresh_combined_ui_stored_state(tool_type, location)

	# Only make an active change if there is something selected and the gradient is active
	if location == "select" && ui_config[tool_type][location]["gradient_button"].pressed:
		set_colour_of_selection(tool_type, false)

	# If we are in the main tool, check the preview button
	if location == "main":
		set_preview_colour(tool_type, false)

# Function to refresh all walls if they have custom colours
func refresh_colours_on_walls(level, delay: float = 0.0):

	outputlog("refresh_colours_on_walls: delay: " + str(delay),0)	
	
	# Make a timer to
	var timer = Timer.new()
	timer.autostart = false
	timer.one_shot = true
	global.Editor.get_node("Windows").add_child(timer)

	# Wait a couple of seconds to ensure everything has been drawn, the delay value has been set.
	if delay > 0.0:
		timer.start(delay)
		yield(timer,"timeout")

	var colour_config = {}
	var node_id

	# For each wall on this level
	for wall in global.World.GetLevelByID(level.ID).Walls.get_children():

		node_id = wall.get_meta("node_id")
		# If it has a colour then reapply it
		if customdatamanager.has_data(node_id):
			colour_config = customdatamanager.get_data(node_id)
			set_tint_colour(int(node_id),colour_config["type"], colour_config, true)

	global.Editor.get_node("Windows").remove_child(timer)
	timer.queue_free()

# When a DD custom colour control changes the colour
func on_dd_custom_color_control_changed(_ignore_this, _ignore_this_too, tool_type: String, location: String):

	outputlog("on_dd_custom_color_control_changed",2)

	var ui_element = ui_config[tool_type][location]

	# Update the stored ui config
	refresh_combined_ui_stored_state(tool_type, location)

	var colour_config = customdatamanager.get_combined_ui_stored_state(tool_type, location)

	# For some tool types, this should drive a reset
	match tool_type:
		"ObjectTool","ScatterTool","PathTool":
			# Hit the reset function
			_on_reset_button_pressed(tool_type, location)
			if location == "select":
				set_object_library_grid_custom_colour_to_dd_palette_colour(tool_type, location)

		# For wall and patternshape tools, we want to update the image as this is the core colour value (if for some reason we want to tint the gradient)
		"WallTool","PatternShapeTool":
			if location == "select":
				set_colour_of_selection(tool_type, false)

# Function to respond to when a gradient colour picker is opened or closed
func on_gradient_colour_picker_activated(is_activated: bool, tool_type: String, _location: String):
	
	var preview_node = get_preview_node(tool_type)

	if preview_node == null:
		return
	
	# If the colour picker is active then set preview to false. Noting that we also do this in select tool which may be odd
	if is_activated:
		preview_node.visible = false
	else:
		preview_node.visible = true

# Function to manage the change in levels to and from default values. Note we must be in normalise mode
func _on_levels_default_button_pressed(button_pressed: bool, tool_type: String, location: String):

	outputlog("_on_levels_default_button_pressed",2)

	# Don't change anything if the button is not pressed, this simply keeps the UI as the current version
	if not button_pressed:
		return

	if location == "main":
		set_preview_colour(tool_type, true)
		# This should automatically update the asset due to signals
		#set_levels_ui_to_base_asset_brightness(tool_type, location, get_preview_node(tool_type))

	# If this is the select tool, then update each asset
	elif location == "select":
		# Set the colour noting that if selection is empty this still works
		set_colour_of_selection(tool_type, true)
		create_update_custom_history(null, tool_type, location, 0.0)

# Function to respond to changes if the levels slider is changed.
func _on_levels_slider_value_changed(_value: float, tool_type: String, location: String):

	outputlog("_on_levels_slider_value_changed",3)

	# Change the default button status to unchecked
	if ui_config[tool_type][location].has("levels_default_button"):
		set_property_but_block_signals(ui_config[tool_type][location]["levels_default_button"], "pressed", false)

	# Update the stored ui config
	refresh_combined_ui_stored_state(tool_type, location)

	# Only make an active change if there is something selected
	match location:
		"select":
			set_colour_of_selection(tool_type, false)
			# Start the timer and emit a history event when it completes
			if ui_config[tool_type][location].has("levels_slider_timer"):
				start_slider_timer(0.0,ui_config[tool_type][location]["levels_slider_timer"])
	
		# If we are in the main location and the preview button is enabled then update the preview
		"main":
			set_preview_colour(tool_type, false)

# Function to respond to changes if the levels slider is changed.
func _on_saturation_slider_value_changed(_value: float, tool_type: String, location: String):

	outputlog("_on_saturation_slider_value_changed",3)

	# Update the stored ui config
	refresh_combined_ui_stored_state(tool_type, location)

	# Only make an active change if there is something selected
	match location:
		"select":
			set_colour_of_selection(tool_type, false)
	
		# If we are in the main location and the preview button is enabled then update the preview
		"main":
			set_preview_colour(tool_type, false)

# Function to update the levels UI to reflect the brightness of the underlying asset
func set_levels_ui_to_base_asset_brightness(tool_type: String, location: String, node):

	var brightness_data
	var ui_element = ui_config[tool_type][location]

	outputlog("set_levels_ui_to_base_asset_brightness",2)
	
	if node == null:
		outputlog("node is null",2)
		return
	
	var texture = get_asset_texture(node, tool_type)

	# If the normalise button is active then go looking for the brightness range
	if ui_element["normalise_button"].pressed && texture != null:
		brightness_data = get_texture_brightness_range(texture)
	else:
		brightness_data = {"min_gray": 0.0, "max_gray": 1.0}
	
	outputlog("brightness_data: " + str(brightness_data),2)
	set_property_but_block_signals(ui_element["levels_slider"].minSlider, "value", brightness_data["min_gray"])
	set_property_but_block_signals(ui_element["levels_slider"].maxSlider, "value", brightness_data["max_gray"])

	# Update the stored ui config
	refresh_combined_ui_stored_state(tool_type, location)

# Function to synchronise the colour palettes
func _on_preset_changed_in_palette(_idx: int, _ignore_this, tool_type: String, location: String):

	outputlog("_on_preset_changed_in_palette",2)
	
	var timer = Timer.new()
	timer.autostart = false
	timer.one_shot = true
	global.Editor.get_node("Windows").add_child(timer)
	
	var target_location
	var list_of_presets = []
	var object_palettes = [ui_config["ObjectTool"]["main"]["palette"],ui_config["ObjectTool"]["select"]["palette"],ui_config["ScatterTool"]["main"]["palette"]]

	# Wait a couple of seconds to ensure the palette presets list is updated.
	timer.start(1.0)
	yield(timer,"timeout")

	# Sync the other locations for 
	if location == "select":
		target_location = "main"
	else:
		target_location = "select"
	# Store the list of presets into an array
	list_of_presets = ui_config[tool_type][location]["palette"].Save()

	# For treat path and objects differently
	match tool_type:
		"ObjectTool","ScatterTool":
			for palette in object_palettes:
				if palette != ui_config[tool_type][location]["palette"]:
					palette.Load(list_of_presets)
			global.ModMapData["ColourObjects"]["palettes"]["ObjectTool"] = list_of_presets
		"PathTool","PortalTool":
			ui_config[tool_type][target_location]["palette"].Load(list_of_presets)
			global.ModMapData["ColourObjects"]["palettes"][tool_type] = list_of_presets
		_:
			return
	
	global.Editor.get_node("Windows").remove_child(timer)
	timer.queue_free()
			
# Reset the preview node back to default behaviour
func reset_preview_node(preview_node, tool_type: String):

	outputlog("reset_preview_node",2)

	# Reset the preview config
	store_preview_config = customdatamanager.DEFAULT_COMBINED_DATA.duplicate(true)
	store_preview_config["texture"] = ""

	# Reset the node.
	# Noting this also sets modulate to white, which needs changing if we want colorable assets to have tint colours
	combinedshader.reset_node(preview_node)
	
	# Check if we are looking at an object that has a custom color
	if is_object_tool_type(tool_type):
		if preview_node.HasCustomColor():
			outputlog("preview shader: " + str(preview_node.Sprite.material.shader),2)
			outputlog("universal shader: " + str(combinedshader.universalshader),2)
			set_object_library_grid_custom_colour_to_dd_palette_colour(tool_type, "main")
			# If we are using the custom shader then update the object library to the custom colour
			if combinedshader.is_node_using_universal_shader(preview_node):
				outputlog("no custom data so restore preview to default",2)
				
				# Set the not to a randomly selected custom colour
				preview_node.SetCustomColor(get_random_colour_from_colour_palette(ui_config[tool_type]["main"]["custom_color_palette"]))
				
			else:
				outputlog("universal shader not active",2)
				match tool_type:
					"ScatterTool":
						preview_node.SetCustomColor(get_random_colour_from_colour_palette(ui_config[tool_type]["main"]["custom_color_palette"]))
					"ObjectTool":
						preview_node.SetCustomColor(ui_config[tool_type]["main"]["custom_color_palette"].color)
				
			outputlog("custom colour: " + str(preview_node.GetCustomColor().to_html()),2)

# Function when the reset button is pressed
func _on_reset_button_pressed(tool_type: String, location: String):

	outputlog("_on_reset_button_pressed",2)

	if not ui_config.has(tool_type):
		return
	if not ui_config[tool_type].has(location):
		return
	var ui_element = ui_config[tool_type][location]

	if not tool_type in NON_CUSTOM_PALETTE_TOOLS:
		ui_element["palette"].SetColor(Color.white,true)

	for button in [ui_element["saturate_button"], ui_element["normalise_button"], ui_element["set_white_button"], ui_element["gradient_button"]]:
		button.pressed = false
	
	# Update the stored ui config
	refresh_combined_ui_stored_state(tool_type, location)

	if location == "select":
		set_colour_of_selection(tool_type, false)
	
	# If this is the main tool
	if location == "main":
		# Get the preview node
		var preview_node = get_preview_node(tool_type)
		# Reset the preview colour
		if preview_node != null:
			reset_preview_node(preview_node, tool_type)

# Function to update the ui reflecting the colour options
func set_ui_visibilty_from_colour_options_change(button_pressed: bool, source_shader_type: String, tool_type: String, location: String):

	outputlog("set_ui_visibilty_from_colour_options_change",2)

	var ui_element = ui_config[tool_type][location]
	var button_lookup = { "none": null, "saturation": ui_element["saturate_button"], "normalised": ui_element["normalise_button"], "white": ui_element["set_white_button"], "gradient": ui_element["gradient_button"]}

	# For each button, set the state without triggering further action so we don't infinitely call this function
	for shader_type in button_lookup.keys():
		if shader_type != "none":
			# If this isn't the source button then set it to false
			if shader_type != source_shader_type:
				set_property_but_block_signals(button_lookup[shader_type], "pressed", false)
			# If it is then set it to the value of button_pressed
			else:
				set_property_but_block_signals(button_lookup[shader_type], "pressed", button_pressed)
			
	# Set the visibility of the levels slider
	ui_element["levels_slider"].visible = (source_shader_type == "normalised" && button_pressed)
	ui_element["levels_hbox"].visible = (source_shader_type == "normalised" && button_pressed)
	ui_element["saturation_slider"].hbox.visible = (source_shader_type == "saturation" && button_pressed)
	ui_element["saturation_label"].visible = (source_shader_type == "saturation" && button_pressed)

	if source_shader_type == "gradient" && button_pressed:
		ui_config["gradient_map"].show()
	else:
		ui_config["gradient_map"].hide()

	# Update the stored ui config
	refresh_combined_ui_stored_state(tool_type, location)

# Function to call when one of the colour options is selected
func _on_colour_option_button_pressed(button_pressed: bool, source_shader_type: String, tool_type: String, location: String, update_selection: bool):

	outputlog("_on_colour_option_button_pressed",2)
	outputlog("source_shader_type: " + str(source_shader_type),2)

	# Set the visibility of various colour ui elements based on the options change
	set_ui_visibilty_from_colour_options_change(button_pressed, source_shader_type, tool_type, location)

	# Actively do something if we have something selected.
	if location == "select" && update_selection:
		outputlog("update selection",3)
		# Set the colour. Noting we want to set the brightness levels to default here as there is a material change in whether the normalised is active
		set_colour_of_selection(tool_type, true)
		# As this is an instant event, record this as a history event
		create_update_custom_history(null, tool_type, location, 0.0)
	
	# If we are in the object or scatter tool and preview colours are active
	if location == "main":
		set_preview_colour(tool_type, true)

# Function to get the combined config from the ui, by retrieving the current colour config and adding it to the stored values
func refresh_combined_ui_stored_state(tool_type: String, location: String):

	outputlog("refresh_combined_ui_stored_state: tool_type: " + str(tool_type) + " location: " + str(location),2)
	# Set a default value in case the ui_config check fails
	var colour_config = { "shader_type": "none", "colour": "ffffffff"}

	# If we have created a ui_config yet 
	if ui_config.has(tool_type):
		if ui_config[tool_type].has(location):
			colour_config = get_colour_config_from_ui(tool_type, location)
	
	# Set the type based on the tool_type
	colour_config["type"] = TYPE_LOOKUP[tool_type]
	customdatamanager.set_combined_ui_stored_state(colour_config, tool_type, location)

# Function to respond to a new palette item being selected. Noting we need this in addition to _on_tint_colour_changed as it takes a frame or something for the colour to propagate to the palette
func _on_new_colour_palette_item_selected(_ignore_this, _ignore_this_too, tool_type: String, location: String):

	var timer = Timer.new()
	timer.autostart = false
	timer.one_shot = true
	global.Editor.get_node("Windows").add_child(timer)

	outputlog("_on_new_colour_palette_item_selected",2)
	# Back wait a fraction of a second so that the colour is updated in the UI
	timer.start(0.05)
	yield(timer,"timeout")

	_on_tintcolour_ui_changed(null, tool_type, location)
		
	global.Editor.get_node("Windows").remove_child(timer)
	timer.queue_free()

# Function call when the tint colour ui is changed
func _on_tintcolour_ui_changed(_ignore_this, tool_type: String, location: String):

	# Sync the opacity slider to the new value
	var colour_config = get_colour_config_from_ui(tool_type, location)
	ui_config[tool_type][location]["opacity_slider"].slider_and_spinbox_change(int(Color(colour_config["colour"]).a * 255),true)
	
	# Call the function to act on the new change
	_on_tintcolour_changed(null, tool_type, location)

# Function called when the opacity slider changes
func _on_opacity_slider_ui_changed(_ignore_this, tool_type: String, location: String):

	# Update the tint colour
	var color = ui_config[tool_type][location]["palette"].color
	color.a = ui_config[tool_type][location]["opacity_slider"].value / 255.0
	ui_config[tool_type][location]["palette"].SetColor(color,false)

	# Call the function to act on the new change
	_on_tintcolour_changed(null, tool_type, location)

# Function called when a colour palette value is changed. Note this only has an immediate action if this is the select tool and something is selected.
func _on_tintcolour_changed(_ignore_this, tool_type: String, location: String):

	outputlog("_on_tintcolour_changed",2)

	# Update the stored ui config
	refresh_combined_ui_stored_state(tool_type, location)

	# Sync the palettes as we could have added a new colour to the presets
	_on_preset_changed_in_palette(0, null, tool_type, location)

	# Update the preview colour
	if location == "main":
		set_preview_colour(tool_type, false)

	# If this is an object tool type, the update the object library to the palette colour
	if is_object_tool_type(tool_type):
		# Reset back to the custom colour
		set_object_library_grid_custom_colour_to_dd_palette_colour(tool_type, location)

	# Check that this is just for the select tool
	if location == "select":
		# For each node, noting that the palette is only visible when only one type of thing is selected so this must be only objects or paths
		set_colour_of_selection(tool_type, false)

# When a new object is selected in the object panel we need to check whether a new Preview recolour is required.
func _on_new_object_selected_in_panel(index: int, _selected: bool):

	var tool_type = global.Editor.ActiveToolName
	var objectmenu = global.Editor.ObjectLibraryPanel.objectMenu
	var custom_color_ui_visible = false

	outputlog("_on_new_object_selected_in_panel", 2)

	# Double check we are actually in the object or scatter tool in case another mod is using the library
	if not is_object_tool_type(tool_type):
		return

	if tool_type == "ObjectTool":
		# If the item icon modulate is red then the item is colourable
		if objectmenu.get_item_icon_modulate(index) == Color(1.0,0.0,0.0,1.0):
			# Set the tint ui to hidden
			custom_color_ui_visible = true
	if tool_type == "ScatterTool":
		# Assume it will be hidden
		custom_color_ui_visible = true
		# Check each of the selected items, if any a normal (i.e. not colorable) then make the tint ui visible
		for _i in objectmenu.get_selected_items():
			# Check if the item is non-red and so make visible and break
			if objectmenu.get_item_icon_modulate(_i) != Color(1.0,0.0,0.0,1.0):
				custom_color_ui_visible = false
				break
	
	# Implement the visibility condition
	set_custom_color_palette_visible(tool_type, "main", custom_color_ui_visible)

	# If there is non-null value in the Preview, then modify it
	if global.Editor.Tools[tool_type].Preview != null:
		set_preview_colour(tool_type, true)

# Function called when new placed nodes are detected and may need colouring
func set_tint_colour_on_placed_nodes(tool_type: String):

	outputlog("set_tint_colour_on_placed_nodes: " + str(tool_type),2)
	var node

	# Look at each node in the range from one more than the last detected node to the most recent node_id
	for node_id in range(last_node_id+1,global.World.nextNodeID,1):
		outputlog("node_id: " + str(node_id),2)
		# Check it exists in the world
		if global.World.HasNodeID(node_id):
			# Get the node itself
			node = global.World.GetNodeByID(node_id)
			if node != null:
				# Call the set tint colour function. Noting this is structured this way as post v1.2.0.0 we will call this function directly
				set_tint_colour_on_new_node(node)

# Function called when a new node is added to the World
func set_tint_colour_on_new_node(node: Node2D):

	outputlog("set_tint_colour_on_new_node: " + str(node),2)

	if node == null:
		outputlog("node is null",2)
		return
	
	var node_id
	if node.has_meta("node_id"):
		node_id = node.get_meta("node_id")
		outputlog("node_id: " + str(node_id),2)
	else:
		return

	# Get the tool type from the active tool name
	var tool_type = global.Editor.ActiveToolName
	# Check the node type actually matches the active tool name type. Noting that there are some mods that create assets while in other tools
	if TYPE_LOOKUP[tool_type] != get_node_type(node):
		outputlog("node type does not match tool_type: node type: " + str(get_node_type(node)) + " tool_type: " + str(tool_type),2)
		return
	
	var ui_element = ui_config[tool_type]["main"]
	var colour_config = customdatamanager.get_combined_ui_stored_state(tool_type, "main")
	
	# If the node is a portal then we have to refresh the wall id resides on
	if tool_type == "PortalTool":
		refresh_wall_colour(node_id)
	
	# If the store_preview has a colour for the scatter tool, then use it. Noting that all other values should be the same
	if tool_type == "ScatterTool" && store_preview_config.has("colour"):
		colour_config["colour"] = store_preview_config["colour"]

	# If in the objects tool type
	match tool_type:
		"ObjectTool","ScatterTool":
			# If we have an active preview button then refresh the preview
			set_preview_colour(tool_type, true)
		"PathTool":
			# Set the active path to null so we can start again
			store_active_path = null
			store_active_path_points = []
	
	# Set the tint colour for the new node. Noting this should be redundant if the preview is active
	set_tint_colour(node_id,TYPE_LOOKUP[tool_type], colour_config, false)
	
	# Custom Colours seem to be set inconsistently, so this just reviews and checks that the custom color is valid
	if is_object_tool_type(node):
		# If it is a colorable object
		if node.HasCustomColor():
			outputlog("node custom colour: " + str(colour_config["colour"]),2)
			check_and_correct_custom_colour(tool_type, node)

# Function to check whether a custom colour is actually a valid custom colour as these seem to get reset by DD somehow
func check_and_correct_custom_colour(tool_type, node):

	outputlog("check_and_correct_custom_colour: " + str(node),2)

	# This is only relevant for the scatter tool and custom colours
	if tool_type in ["ScatterTool","ObjectTool"] && node.HasCustomColor():
		if node.has_meta("node_id"):
			# If there is a custom shader data then do nothing. Might need to revisit this assumption
			if not customdatamanager.has_data(node.get_meta("node_id")):
				outputlog("no custom data for this node",2)
				# Get the list of valid colours which is taken from the current state of the UI
				correct_custom_colour(tool_type, node)	
			else:
				var data = customdatamanager.get_data(node.get_meta("node_id"))
				outputlog("found custom data for this node: " + str(data),2)
				if data["shader_type"] != "gradient":
					# Get the list of valid colours which is taken from the current state of the UI
					correct_custom_colour(tool_type, node)
				else:
					# Set the custom colour to white
					node.SetCustomColor(Color.white)
					# Run the shader against the stored data
					set_custom_attributes_on_map_node(node, "objects", data, true)
		else:
			outputlog("no custom data for this node",2)
			# Get the list of valid colours which is taken from the current state of the UI
			correct_custom_colour(tool_type, node)	

# Function to refresh the wall colour of the wall that the portal node is on
func refresh_wall_colour(portal_node_id: int):

	var portal_node = null

	outputlog("refresh_wall_colour",2)

	if global.World.HasNodeID(portal_node_id):
		outputlog("WallID: " + str(global.World.GetNodeByID(portal_node_id).WallID),2)
		if global.World.GetNodeByID(portal_node_id).has("WallID"):
			# If this is not a freestanding portal
			portal_node = global.World.GetNodeByID(portal_node_id)
			if portal_node.WallID >= 0:
				# If it is valid which it surely is 
				if global.World.HasNodeID(portal_node.WallID):
					# If the wall is coloured then do something
					if customdatamanager.has_data(portal_node.WallID):
						var colour_config = customdatamanager.get_data(portal_node.WallID)
						set_tint_colour(portal_node.WallID,colour_config["type"], colour_config, true)

# Function to update the obejct library custom colour to the DD colour palette colour
func set_object_library_grid_custom_colour_to_dd_palette_colour(tool_type: String, location: String):

	outputlog("set_object_library_grid_custom_colour_to_dd_palette_colour",2)

	# Exclude anything that isn't an object type tool
	if not is_object_tool_type(tool_type):
		return
	
	if ui_config[tool_type][location].has("custom_color_palette"):
		if ui_config[tool_type][location]["custom_color_palette"] != null:
			# Set the preview colour of the object library panel as the DD colour palette colour
			global.Editor.ObjectLibraryPanel.objectMenu.SetCustomColor(ui_config[tool_type][location]["custom_color_palette"].color)

# Function to use touch the custom color palette in order to refresh the colours on the object preview panel
func touch_custom_color_palette(tool_type: String, location: String):

	outputlog("touch_custom_color_palette",2)

	if ui_config[tool_type][location].has("custom_color_palette"):
		outputlog("found custom colour palette",2)
		if ui_config[tool_type][location]["custom_color_palette"] != null:
			# Set the custom color palette to itself but critically emiting the appropriate signal which seems to trigger the object panel preview colour
			ui_config[tool_type][location]["custom_color_palette"].SetColor(ui_config[tool_type][location]["custom_color_palette"].color, true)

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

#########################################################################################################
##
## START FUNCTION
##
#########################################################################################################

func _init():

	pass


# Main Script
func initialise() -> void:

	outputlog("ColourThings Class Has been loaded.")
	randomize()
	NewHSlider = ResourceLoader.load(global.Root + "NewHSlider.gd", "GDScript", true)

	# Find all the custom colour palettes so that we can refresh them so the Object Library shows the custom colours not the tint colours
	find_all_custom_color_palettes()

	# Set Up Classes for PresetsDropdown and GradientMaps
	GradientMap = ResourceLoader.load(global.Root + "GradientMap.gd", "GDScript", true)
	
	# Make the UI for each tool and location
	for location in ["main","select"]:
		for tool_type in BUILD_THESE_TOOLS:
			if tool_type == "ScatterTool" && location == "select":
				continue
			make_overridecolour_ui(tool_type,location)

	make_gradient_map_ui()

	# Call the reset button for each instance to reset the Object panels
	for tool_type in ["ObjectTool","ScatterTool"]:
		_on_reset_button_pressed(tool_type,"main")


	



	
