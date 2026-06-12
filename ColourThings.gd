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

# Clipboard for copy/paste colour settings between selected assets
var clipboard_data = null
var clipboard_type = ""

# Stored random offsets for preview (regenerated after each placement)
var _preview_variant_offsets = {}
# Flag set by Core.gd when the preview asset changes (scroll wheel cycle)
var _preview_asset_changed = false
# Flag set by Core.gd when Shift+wheel is detected in ScatterTool
var _scatter_wheel_cycled = false

# Tracks the current type of change being made, for history granularity
var _current_change_source = ""

# Keys to copy/paste (colour/shader only, no edge blur or path modifiers)
const CLIPBOARD_KEYS = ["shader_type", "colour", "opacity", "saturation", "hue_shift", "lightness", "contrast", "invert", "gradient", "sat_levels", "sat_output_levels", "levels", "levels_default_brightness", "red_config", "colorable_custom_color", "original_dd_color", "texture", "colorable_protect"]

const BUILD_THESE_TOOLS = ["ObjectTool", "ScatterTool", "PathTool", "PatternShapeTool","WallTool","PortalTool"]

const DEFAULT_COLOUR_PRESETS = ["ff6b3834", "ffac584c", "ff885848", "ffc0866c", "ff8d6d58", "fff3a768", "ff685848", "ff9c8868", "ffae9254", "ffd8c888", "ff888868", "ffaab478", "ff92aa58", "ff87a868", "ff679865", "ff789868", "ff546d56", "ff68887c", "ff667878", "ff809dab", "ff61788d", "ff535869", "ff786878", "ff886878", "ff905868", "ff994858", "ffffffff", "bfffffff", "7fffffff", "40ffffff"]
const TYPE_LOOKUP = {"ObjectTool": "objects","ScatterTool": "objects", "PathTool": "paths", "PatternShapeTool": "pattern_shapes", "WallTool": "walls", "PortalTool": "portals"}
const TOOL_TYPE_LOOKUP_BY_SELECTABLE = {"1": "WallTool", "2": "PortalTool", "3": "PortalTool", "4": "ObjectTool", "5": "PathTool", "6": "LightTool", "7": "PatternShapeTool", "8": "RoofTool"}
const HIDE_NONGRADIENT_BUTTON_TOOLS = []
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

# Convert linear slider value (0-1) to non-linear gamma value (0.01-9.99 with 1.0 at center)
# slider=0 -> gamma=0.01, slider=0.5 -> gamma=1.0, slider=1 -> gamma=9.99
func slider_to_gamma(slider_value: float) -> float:
	if slider_value <= 0.5:
		# Map 0-0.5 to 0.01-1.0 (exponential curve)
		return 0.01 + (1.0 - 0.01) * pow(slider_value * 2.0, 2.0)
	else:
		# Map 0.5-1 to 1.0-9.99 (exponential curve)
		return 1.0 + (9.99 - 1.0) * pow((slider_value - 0.5) * 2.0, 2.0)

# Convert gamma value (0.01-9.99) to linear slider value (0-1)
func gamma_to_slider(gamma_value: float) -> float:
	if gamma_value <= 1.0:
		# Map 0.01-1.0 to 0-0.5
		return sqrt((gamma_value - 0.01) / (1.0 - 0.01)) * 0.5
	else:
		# Map 1.0-9.99 to 0.5-1
		return 0.5 + sqrt((gamma_value - 1.0) / (9.99 - 1.0)) * 0.5

# Convert linear slider value (0-1) to non-linear saturation value (0.0-4.0 with 1.0 at center)
# slider=0 -> sat=0.0, slider=0.5 -> sat=1.0, slider=1 -> sat=4.0
func slider_to_saturation(slider_value: float) -> float:
	if slider_value <= 0.5:
		# Map 0-0.5 to 0.0-1.0 (quadratic curve)
		return pow(slider_value * 2.0, 2.0)
	else:
		# Map 0.5-1 to 1.0-4.0 (quadratic curve)
		return 1.0 + (4.0 - 1.0) * pow((slider_value - 0.5) * 2.0, 2.0)

# Convert saturation value (0.0-4.0) to linear slider value (0-1)
func saturation_to_slider(sat_value: float) -> float:
	if sat_value <= 1.0:
		# Map 0.0-1.0 to 0-0.5
		return sqrt(sat_value) * 0.5
	else:
		# Map 1.0-4.0 to 0.5-1
		return 0.5 + sqrt((sat_value - 1.0) / (4.0 - 1.0)) * 0.5

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

	if node == null or not is_instance_valid(node):
		return null

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
	
	# Check if selection is colorable (objects or patterns)
	var is_colorable_selection = false
	if location == "select":
		is_colorable_selection = is_selection_colorable(tool_type)
	elif location == "main":
		is_colorable_selection = _is_current_main_object_colorable(tool_type)
	
	# Get the list of non-gradient buttons
	var list_of_buttons = [ui_element["saturate_button"],ui_element["normalise_button"],ui_element["set_white_button"]]
	# Set those buttons to hidden
	for button in list_of_buttons:
		button.visible = show
		# If the button is pressed and we are hiding it, then we need to set it to not pressed
		if button.pressed && not show:
			button.pressed = false
	
	# For colorable selections, hide normalise and white buttons but keep their space
	# and reorder so that saturate + gradient + reset are grouped on the right
	if show and is_colorable_selection:
		ui_element["normalise_button"].modulate.a = 0
		ui_element["normalise_button"].mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui_element["set_white_button"].modulate.a = 0
		ui_element["set_white_button"].mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Reorder: label, (invisible) normalise, (invisible) white, saturate, gradient, reset
		var hbox = ui_element["tint_hbox"]
		hbox.move_child(ui_element["normalise_button"], 1)
		hbox.move_child(ui_element["set_white_button"], 2)
		hbox.move_child(ui_element["saturate_button"], 3)
		hbox.move_child(ui_element["gradient_button"], 4)
		hbox.move_child(ui_element["reset_button"], 5)
	else:
		ui_element["normalise_button"].modulate.a = 1
		ui_element["normalise_button"].mouse_filter = Control.MOUSE_FILTER_STOP
		ui_element["set_white_button"].modulate.a = 1
		ui_element["set_white_button"].mouse_filter = Control.MOUSE_FILTER_STOP
		# Restore original order: label, saturate, normalise, gradient, white, reset
		var hbox = ui_element["tint_hbox"]
		hbox.move_child(ui_element["saturate_button"], 1)
		hbox.move_child(ui_element["normalise_button"], 2)
		hbox.move_child(ui_element["gradient_button"], 3)
		hbox.move_child(ui_element["set_white_button"], 4)
		hbox.move_child(ui_element["reset_button"], 5)

	# Update colorable protection checkboxes visibility
	update_colorable_protect_visibility(tool_type, location)

# Function to move the gradient location
func move_gradient_location(tool_type: String, location: String):

	outputlog("move_gradient_location: " + str(tool_type) + " location: " + str(location),2)

	ui_config["gradient_map"].move_location(tool_type, "select", ui_config[tool_type][location]["gradient_button"].pressed)

# Function to register each standard tool and call a function on_tool_launch when they are launched
func register_tool_launch_or_close_signals():

	var tool_list = ["ObjectTool","ScatterTool","PathTool","PatternShapeTool","SelectTool", "PortalTool"]

	# For each tool in the list
	for tool_type in tool_list:
		if global.Editor.Toolset.GetToolPanel(tool_type):
			global.Editor.Toolset.GetToolPanel(tool_type).connect("visibility_changed", self, "on_tool_launch",[tool_type])

# Function to register when select options vboxs become visible/hide
func register_select_options_launch_or_close_signals():

	var tool_list = ["ObjectTool","PathTool","PatternShapeTool","WallTool","PortalTool"]

	# For each tool in the list
	for tool_type in tool_list:
		if find_select_vbox(tool_type):
			find_select_vbox(tool_type).connect("visibility_changed", self, "on_select_tool_option_launch",[tool_type])

# Called when a select tool options vbox becomes visible or hidden
func on_select_tool_option_launch(tool_type: String):

	outputlog("on_select_tool_option_launch: " + str(tool_type) + " visible: " + str(find_select_vbox(tool_type).visible if find_select_vbox(tool_type) != null else "null"), 0)

	var vbox = find_select_vbox(tool_type)
	if vbox == null:
		return

	# Only act when the vbox becomes visible (not when it hides)
	if not vbox.visible:
		outputlog("on_select_tool_option_launch: vbox hidden, returning", 0)
		return

	# If there is a selection, update the UI to reflect the selected node's values
	if global.Editor.Tools["SelectTool"].Selected.size() > 0:
		var node = global.Editor.Tools["SelectTool"].Selected[0]
		outputlog("on_select_tool_option_launch: updating UI for node " + str(node), 0)
		if is_instance_valid(node):
			set_colour_ui_to_selected_node_values(node, tool_type)
	else:
		outputlog("on_select_tool_option_launch: no selection", 0)

	# Move the gradient map to the correct location
	if ui_config.has("gradient_map"):
		if ui_config.has(tool_type) and ui_config[tool_type].has("select"):
			var gradient_pressed = ui_config[tool_type]["select"]["gradient_button"].pressed if ui_config[tool_type]["select"].has("gradient_button") else false
			ui_config["gradient_map"].move_location(tool_type, "select", gradient_pressed)

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
		"saturate_button": "When enabled, allows to change the gamma, saturation, hue, lightness, contrast and input/output levels of the underlying asset colours. Can also invert colors.",
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

	# === SATURATION MODE SLIDERS ===
	# Order of creation is reversed because move_child places them at the same index
	# Desired display order: Gamma, Saturation, Hue, Lightness, Contrast, In, Out, Invert Colors, [Colorable Protection]
	# So we create: Colorable Protection, Invert Colors, Output Levels, Input Levels, Contrast, Lightness, Hue, Saturation, Gamma
	
	# Make colorable protection checkboxes (only visible when a colorable asset is selected)
	# Use a VBoxContainer to put the label on one line and checkboxes on the next
	var colorable_protect_vbox = VBoxContainer.new()
	vbox.add_child(colorable_protect_vbox)
	vbox.move_child(colorable_protect_vbox, index)
	ui_element["colorable_protect_hbox"] = colorable_protect_vbox
	
	var protect_label = make_label(colorable_protect_vbox, "Keep Custom Color Settings:", 0)
	protect_label.hint_tooltip = "When checked, the corresponding slider will NOT affect the colorable (custom color) areas of the asset."
	
	var protect_checks_hbox = HBoxContainer.new()
	colorable_protect_vbox.add_child(protect_checks_hbox)
	
	var cb_protect_hue = CheckBox.new()
	cb_protect_hue.text = "Hue"
	cb_protect_hue.pressed = true
	cb_protect_hue.hint_tooltip = "Protect custom color areas from hue shift"
	protect_checks_hbox.add_child(cb_protect_hue)
	ui_element["colorable_protect_hue"] = cb_protect_hue
	
	var cb_protect_sat = CheckBox.new()
	cb_protect_sat.text = "Sat"
	cb_protect_sat.pressed = true
	cb_protect_sat.hint_tooltip = "Protect custom color areas from saturation changes"
	protect_checks_hbox.add_child(cb_protect_sat)
	ui_element["colorable_protect_sat"] = cb_protect_sat
	
	var cb_protect_light = CheckBox.new()
	cb_protect_light.text = "Lightness"
	cb_protect_light.pressed = true
	cb_protect_light.hint_tooltip = "Protect custom color areas from lightness changes"
	protect_checks_hbox.add_child(cb_protect_light)
	ui_element["colorable_protect_light"] = cb_protect_light
	
	colorable_protect_vbox.visible = false
	
	# Make invert colors toggle button (icon style like Dungeondraft)
	ui_element["invert_hbox"] = HBoxContainer.new()
	vbox.add_child(ui_element["invert_hbox"])
	vbox.move_child(ui_element["invert_hbox"],index)
	make_label(ui_element["invert_hbox"],"Invert Colors",0)
	ui_element["invert_button"] = Button.new()
	ui_element["invert_button"].toggle_mode = true
	ui_element["invert_button"].pressed = false
	ui_element["invert_button"].icon = load_image_texture("icons/white-circle-icon.png")
	ui_element["invert_hbox"].add_child(ui_element["invert_button"])
	ui_element["invert_hbox"].visible = false
	ui_element["invert_button"].connect("toggled", self, "_on_invert_button_toggled",[tool_type,location])
	# Spacer to push Reset All button to the right
	var reset_all_spacer = Control.new()
	reset_all_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui_element["invert_hbox"].add_child(reset_all_spacer)
	# Reset all button (25% smaller icon) with text
	ui_element["reset_all_button"] = make_button(ui_element["invert_hbox"], "icons/rotate-32.png", "Reset all HSL adjustments to default", false, 0.75)
	ui_element["reset_all_button"].text = "Reset All"
	ui_element["reset_all_button"].connect("pressed", self, "_on_reset_all_hsl_pressed",[tool_type,location])
	
	# Make output levels - HBox container with label, slider and reset button on same line
	ui_element["sat_output_levels_hbox"] = HBoxContainer.new()
	vbox.add_child(ui_element["sat_output_levels_hbox"])
	vbox.move_child(ui_element["sat_output_levels_hbox"],index)
	make_label(ui_element["sat_output_levels_hbox"],"Out",0)
	ui_element["sat_output_levels_slider"] = tool_panel.CreateRange("new_sat_output_levels_slider_"+str(tool_type)+str(location), 0.0, 1.0, 0.01, 0.0, 1.0)
	tool_panel.Align.remove_child(ui_element["sat_output_levels_slider"])
	ui_element["sat_output_levels_hbox"].add_child(ui_element["sat_output_levels_slider"])
	ui_element["sat_output_levels_slider"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui_element["sat_output_levels_hbox"].visible = false
	# Reset button for output levels (25% smaller icon)
	ui_element["sat_output_levels_reset_button"] = make_button(ui_element["sat_output_levels_hbox"], "icons/rotate-32.png", "Reset output levels to default (0.0 - 1.0)", false, 0.75)
	ui_element["sat_output_levels_reset_button"].connect("pressed", self, "_on_sat_output_levels_reset_pressed",[tool_type,location])
	
	# Make input levels - HBox container with label, slider and reset button on same line
	ui_element["sat_levels_hbox"] = HBoxContainer.new()
	vbox.add_child(ui_element["sat_levels_hbox"])
	vbox.move_child(ui_element["sat_levels_hbox"],index)
	make_label(ui_element["sat_levels_hbox"],"In",0)
	ui_element["sat_levels_slider"] = tool_panel.CreateRange("new_sat_levels_slider_"+str(tool_type)+str(location), 0.0, 1.0, 0.01, 0.0, 1.0)
	tool_panel.Align.remove_child(ui_element["sat_levels_slider"])
	ui_element["sat_levels_hbox"].add_child(ui_element["sat_levels_slider"])
	ui_element["sat_levels_slider"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui_element["sat_levels_hbox"].visible = false
	# Reset button for input levels (25% smaller icon)
	ui_element["sat_levels_reset_button"] = make_button(ui_element["sat_levels_hbox"], "icons/rotate-32.png", "Reset input levels to default (0.0 - 1.0)", false, 0.75)
	ui_element["sat_levels_reset_button"].connect("pressed", self, "_on_sat_levels_reset_pressed",[tool_type,location])
	
	# Make contrast slider - label on same line, range -1 to +1 (0 = no change)
	ui_element["contrast_slider"] = NewHSlider.new(vbox, 0.0, -1.0, 1.0, 0.01, false)
	vbox.move_child(ui_element["contrast_slider"].hbox,index)
	make_label(ui_element["contrast_slider"].hbox,"Contrast",0)
	ui_element["contrast_slider"].hbox.visible = false
	ui_element["contrast_slider"].connect("emit_history_event_signal", self, "create_update_custom_history",[null,tool_type,location,0.0])
	# Reset button for contrast (25% smaller icon)
	ui_element["contrast_reset_button"] = make_button(ui_element["contrast_slider"].hbox, "icons/rotate-32.png", "Reset contrast to default (0.0)", false, 0.75)
	ui_element["contrast_reset_button"].connect("pressed", self, "_on_contrast_reset_pressed",[tool_type,location])
	
	# Make lightness slider - label on same line, range -1 to +1 (0 = no change)
	ui_element["lightness_slider"] = NewHSlider.new(vbox, 0.0, -1.0, 1.0, 0.01, false)
	vbox.move_child(ui_element["lightness_slider"].hbox,index)
	make_label(ui_element["lightness_slider"].hbox,"Lightness",0)
	ui_element["lightness_slider"].hbox.visible = false
	ui_element["lightness_slider"].connect("emit_history_event_signal", self, "create_update_custom_history",[null,tool_type,location,0.0])
	# Reset button for lightness (25% smaller icon)
	ui_element["lightness_reset_button"] = make_button(ui_element["lightness_slider"].hbox, "icons/rotate-32.png", "Reset lightness to default (0.0)", false, 0.75)
	ui_element["lightness_reset_button"].connect("pressed", self, "_on_lightness_reset_pressed",[tool_type,location])
	
	# Make hue slider - label on same line as slider
	ui_element["hue_slider"] = NewHSlider.new(vbox, 0.0, -1.0, 1.0, 0.01, false)
	vbox.move_child(ui_element["hue_slider"].hbox,index)
	make_label(ui_element["hue_slider"].hbox,"Hue",0)
	ui_element["hue_slider"].hbox.visible = false
	ui_element["hue_slider"].connect("emit_history_event_signal", self, "create_update_custom_history",[null,tool_type,location,0.0])
	# Reset button for hue (25% smaller icon)
	ui_element["hue_reset_button"] = make_button(ui_element["hue_slider"].hbox, "icons/rotate-32.png", "Reset hue to default (0.0)", false, 0.75)
	ui_element["hue_reset_button"].connect("pressed", self, "_on_hue_reset_pressed",[tool_type,location])
	
	# Make saturation slider - label on same line, slider goes 0 to 1, converted to non-linear saturation (0.0 to 4.0 with 1.0 at center)
	ui_element["saturation_slider"] = NewHSlider.new(vbox, 0.5, 0.0, 1.0, 0.01, false)
	vbox.move_child(ui_element["saturation_slider"].hbox,index)
	make_label(ui_element["saturation_slider"].hbox,"Saturation",0)
	ui_element["saturation_slider"].hbox.visible = false
	ui_element["saturation_slider"].connect("emit_history_event_signal", self, "create_update_custom_history",[null,tool_type,location,0.0])
	# Reset button for saturation (25% smaller icon)
	ui_element["saturation_reset_button"] = make_button(ui_element["saturation_slider"].hbox, "icons/rotate-32.png", "Reset saturation to default (1.0)", false, 0.75)
	ui_element["saturation_reset_button"].connect("pressed", self, "_on_saturation_reset_pressed",[tool_type,location])
	
	# Midtones/gamma slider - label on same line, slider goes 0 to 1, converted to non-linear gamma (0.01 to 9.99 with 1.0 at center)
	ui_element["sat_midtones_slider"] = NewHSlider.new(vbox, 0.5, 0.0, 1.0, 0.01, false)
	vbox.move_child(ui_element["sat_midtones_slider"].hbox,index)
	make_label(ui_element["sat_midtones_slider"].hbox,"Gamma",0)
	ui_element["sat_midtones_slider"].hbox.visible = false
	ui_element["sat_midtones_slider"].connect("emit_history_event_signal", self, "create_update_custom_history",[null,tool_type,location,0.0])
	# Reset button for gamma (25% smaller icon)
	ui_element["sat_midtones_reset_button"] = make_button(ui_element["sat_midtones_slider"].hbox, "icons/rotate-32.png", "Reset gamma to default (1.0)", false, 0.75)
	ui_element["sat_midtones_reset_button"].connect("pressed", self, "_on_sat_midtones_reset_pressed",[tool_type,location])
	
	# Make opacity slider for all tools
	ui_element["opacity_slider"] = NewHSlider.new(vbox, 1.0, 0.0, 1.0, 0.01, false)
	vbox.move_child(ui_element["opacity_slider"].hbox,index)
	make_label(ui_element["opacity_slider"].hbox,"Opacity",0)
	# Reset button for opacity (25% smaller icon)
	ui_element["opacity_reset_button"] = make_button(ui_element["opacity_slider"].hbox, "icons/rotate-32.png", "Reset opacity to default (1.0)", false, 0.75)
	ui_element["opacity_reset_button"].connect("pressed", self, "_on_opacity_reset_pressed",[tool_type,location])

	# Make the colour palette if it isn't a Pattern or Wall tool
	if not tool_type in ["PatternShapeTool","WallTool"]:

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
	else:
		ui_element["palette"] = null

	# Set up opacity slider signals for all tools
	ui_element["opacity_slider"].connect("value_changed", self, "_on_opacity_slider_ui_changed",[tool_type,location])
	ui_element["opacity_slider"].connect("emit_history_event_signal", self, "create_update_custom_history",[null,tool_type,location,0.0])

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

	# Create Natural Color Variants for objects
	if tool_type in ["ObjectTool", "ScatterTool"]:
		# Select panel: click-to-apply button
		# Main panel: toggle that auto-randomises each new placed node
		var is_select = (location == "select")
		var is_main = (location == "main")

		if is_select or is_main:
			var variants_hbox = HBoxContainer.new()
			vbox.add_child(variants_hbox)
			vbox.move_child(variants_hbox, hbox.get_index() + 1)

			if is_select:
				# Click button for select tool
				ui_element["natural_variants_button"] = make_button(variants_hbox, "icons/dice-icon.png", "Apply random variations to selected parameters on each selected object. Click the cog to configure.", false)
				ui_element["natural_variants_button"].text = " Color Variants"
				ui_element["natural_variants_button"].size_flags_horizontal = 3
				ui_element["natural_variants_button"].connect("pressed", self, "_on_natural_variants_pressed", [tool_type])
			else:
				# Toggle button for main tool panel (auto-randomise on placement)
				ui_element["natural_variants_button"] = make_button(variants_hbox, "icons/dice-icon.png", "When enabled, each newly placed object will have subtle random colour variations applied automatically. Click the cog to configure.", true)
				ui_element["natural_variants_button"].text = " Color Variants"
				ui_element["natural_variants_button"].size_flags_horizontal = 3
				ui_element["natural_variants_button"].connect("toggled", self, "_on_variants_toggle_changed", [tool_type])

			ui_element["variants_advanced_toggle"] = make_button(variants_hbox, "icons/cog-32.png", "Show/hide advanced randomisation settings.", true, 0.75)
			ui_element["variants_advanced_toggle"].connect("toggled", self, "_on_variants_advanced_toggled", [tool_type, location])

			# Advanced settings container (hidden by default)
			var advanced_vbox = VBoxContainer.new()
			advanced_vbox.visible = false
			vbox.add_child(advanced_vbox)
			vbox.move_child(advanced_vbox, variants_hbox.get_index() + 1)
			ui_element["variants_advanced_vbox"] = advanced_vbox

			# Range slider (1% to 100%, default 10%)
			ui_element["variants_range_slider"] = NewHSlider.new(advanced_vbox, 10.0, 1.0, 100.0, 1.0, true)
			make_label(ui_element["variants_range_slider"].hbox, "Range %", 0)
			ui_element["variants_range_reset_button"] = make_button(ui_element["variants_range_slider"].hbox, "icons/rotate-32.png", "Reset range to default (10%)", false, 0.75)
			ui_element["variants_range_reset_button"].connect("pressed", self, "_on_variants_range_reset_pressed", [tool_type, location])

			# Parameter checkboxes
			var checks_hbox = HBoxContainer.new()
			advanced_vbox.add_child(checks_hbox)

			var cb_hue = CheckBox.new()
			cb_hue.text = "Hue"
			cb_hue.pressed = true
			checks_hbox.add_child(cb_hue)
			ui_element["variants_cb_hue"] = cb_hue

			var cb_sat = CheckBox.new()
			cb_sat.text = "Sat"
			cb_sat.pressed = true
			checks_hbox.add_child(cb_sat)
			ui_element["variants_cb_saturation"] = cb_sat

			var cb_gamma = CheckBox.new()
			cb_gamma.text = "Gamma"
			cb_gamma.pressed = true
			checks_hbox.add_child(cb_gamma)
			ui_element["variants_cb_gamma"] = cb_gamma

			var cb_levels = CheckBox.new()
			cb_levels.text = "In Levels"
			cb_levels.pressed = true
			checks_hbox.add_child(cb_levels)
			ui_element["variants_cb_levels"] = cb_levels

			ui_element["variants_hbox"] = variants_hbox

	# Create copy/paste settings buttons (only in select tool panel)
	if location == "select":
		var copypaste_hbox = HBoxContainer.new()
		vbox.add_child(copypaste_hbox)

		var copypaste_label = make_label(copypaste_hbox, "Copy/Paste Settings", 0)
		copypaste_label.size_flags_horizontal = 3

		ui_element["copy_settings_button"] = _make_text_button(copypaste_hbox, "Copy", "Copy the colour/shader settings from the first selected asset to the clipboard.", false)
		ui_element["copy_settings_button"].connect("pressed", self, "copy_colour_settings", [tool_type])

		ui_element["paste_settings_button"] = _make_text_button(copypaste_hbox, "Paste", "Paste the clipboard colour/shader settings to all selected assets of the same type.", false)
		ui_element["paste_settings_button"].connect("pressed", self, "paste_colour_settings", [tool_type])
		ui_element["paste_settings_button"].disabled = true

		# For ObjectTool select panel: mark for unified color picker setup
		# The tint palette will be relocated next to the DD Custom Color picker by setup_unified_select_picker()
		if tool_type == "ObjectTool" and ui_element["palette"] != null:
			ui_element["select_tint_relocated"] = true

		ui_element["copypaste_hbox"] = copypaste_hbox

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

	# On hue slider change
	ui_element["hue_slider"].connect("value_changed",self,"_on_hue_slider_value_changed",[tool_type,location])

	# On lightness slider change
	ui_element["lightness_slider"].connect("value_changed",self,"_on_lightness_slider_value_changed",[tool_type,location])

	# On contrast slider change
	ui_element["contrast_slider"].connect("value_changed",self,"_on_contrast_slider_value_changed",[tool_type,location])

	# On saturation levels sliders change (double slider for blacks/whites)
	ui_element["sat_levels_slider"].minSlider.connect("value_changed",self,"_on_sat_levels_slider_value_changed",[tool_type,location])
	ui_element["sat_levels_slider"].maxSlider.connect("value_changed",self,"_on_sat_levels_slider_value_changed",[tool_type,location])
	ui_element["sat_midtones_slider"].connect("value_changed",self,"_on_sat_levels_slider_value_changed",[tool_type,location])

	# On output levels sliders change
	ui_element["sat_output_levels_slider"].minSlider.connect("value_changed",self,"_on_sat_levels_slider_value_changed",[tool_type,location])
	ui_element["sat_output_levels_slider"].maxSlider.connect("value_changed",self,"_on_sat_levels_slider_value_changed",[tool_type,location])

	# On colorable protection checkbox change
	ui_element["colorable_protect_hue"].connect("toggled", self, "_on_colorable_protect_toggled",[tool_type,location])
	ui_element["colorable_protect_sat"].connect("toggled", self, "_on_colorable_protect_toggled",[tool_type,location])
	ui_element["colorable_protect_light"].connect("toggled", self, "_on_colorable_protect_toggled",[tool_type,location])

# Make a button and return it, with optional icon scale (default 1.0, use 0.75 for 25% smaller)
func make_button(parent_node, icon_path: String, hint_tooltip: String, toggle_mode: bool, icon_scale: float = 1.0) -> Button:

	var button = Button.new()
	button.toggle_mode = toggle_mode
	button.hint_tooltip = hint_tooltip
	
	var texture = load_image_texture(icon_path)
	if icon_scale != 1.0 && texture != null:
		# Create a scaled version of the icon
		var image = texture.get_data()
		var new_size = Vector2(image.get_width() * icon_scale, image.get_height() * icon_scale)
		image.resize(int(new_size.x), int(new_size.y), Image.INTERPOLATE_LANCZOS)
		var scaled_texture = ImageTexture.new()
		scaled_texture.create_from_image(image)
		button.icon = scaled_texture
	else:
		button.icon = texture
	
	parent_node.add_child(button)
	return button

# Make a simple text button (no icon) and return it
func _make_text_button(parent_node, text: String, hint_tooltip: String, toggle_mode: bool) -> Button:
	var button = Button.new()
	button.text = text
	button.toggle_mode = toggle_mode
	button.hint_tooltip = hint_tooltip
	parent_node.add_child(button)
	return button

# Function to show or hide the custom colour palette
func set_custom_color_palette_visible(tool_type: String, location: String, make_visible: bool):

	outputlog("set_custom_color_palette_visible",2)

	var ui_element = ui_config[tool_type][location]

	# Unified picker handling for ObjectTool select panel
	if tool_type == "ObjectTool" and location == "select" and ui_element.has("select_tint_relocated"):
		# Hide the "Tint Color" label (only shown in mixed mode via set_custom_color_palette_visible_mixed)
		if ui_element.has("unified_tint_label"):
			ui_element["unified_tint_label"].visible = false
		if make_visible:
			# Colorable asset selected: show Custom Color picker, hide tint palette
			if ui_element["custom_color_palette"] != null:
				ui_element["custom_color_palette"].visible = true
			if ui_element["custom_color_label"] != null:
				ui_element["custom_color_label"].visible = true
			ui_element["palette"].visible = false
		else:
			# Non-colorable asset selected: show tint palette at bottom, hide Custom Color
			if ui_element["custom_color_palette"] != null:
				ui_element["custom_color_palette"].visible = false
			if ui_element["custom_color_label"] != null:
				ui_element["custom_color_label"].visible = false
			ui_element["palette"].visible = true
		# Always show non-gradient buttons (HSL controls) regardless of colorable state
		show_non_gradient_buttons(tool_type, location)
		return

	# Default behaviour for other tools/locations
	# If we have successfully identified the custom colour palettes then we show/hide them
	if ui_element["custom_color_palette"] != null && ui_element["custom_color_label"] != null:
		ui_element["custom_color_palette"].visible = make_visible
		ui_element["custom_color_label"].visible = make_visible
	
	# Choose whether to set the ui for custom colour buttons visible
	if is_object_tool_type(tool_type):
		# Always show non-gradient buttons (HSL controls) so saturate mode works for colorable assets too
		show_non_gradient_buttons(tool_type, location)
		
		# Set the palette invisible when colorable asset is selected (custom color picker takes over)
		ui_config[tool_type][location]["palette"].visible = not make_visible
		# Always show opacity slider (it works for colorable assets too)
		ui_config[tool_type][location]["opacity_slider"].hbox.visible = true

		# If we are in the main tool, then check whether we should update the object library custom colour to match the dd custom colour palette
		if location == "main":
			# It should always reflect the custom colour and DD sometimes takes from elsewhere
			set_object_library_grid_custom_colour_to_dd_palette_colour(tool_type,location)


# Function to show both color pickers when a mixed selection (colorable + non-colorable) is active
func set_custom_color_palette_visible_mixed(tool_type: String, location: String):

	outputlog("set_custom_color_palette_visible_mixed",2)

	var ui_element = ui_config[tool_type][location]

	# Show both pickers
	if ui_element.has("custom_color_palette") and ui_element["custom_color_palette"] != null:
		ui_element["custom_color_palette"].visible = true
	if ui_element.has("custom_color_label") and ui_element["custom_color_label"] != null:
		ui_element["custom_color_label"].visible = true
	if ui_element.has("palette") and ui_element["palette"] != null:
		ui_element["palette"].visible = true
	# Show the "Tint Color" label above the tint palette
	if ui_element.has("unified_tint_label"):
		ui_element["unified_tint_label"].visible = true

	show_non_gradient_buttons(tool_type, location)


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
				# Also connect color_changed for real-time preview in HSL mode
				if ui_config[tool_type][location][custom_color_control_type].colorPicker != null:
					ui_config[tool_type][location][custom_color_control_type].colorPicker.connect("color_changed", self, "on_dd_custom_color_control_changed",[0,tool_type,location])
				

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


# Function to set up the unified color picker in the ObjectTool select panel.
# Relocates the tint palette to sit just after the DD Custom Color picker so that
# we can automatically switch between showing one or the other depending on whether
# the selected asset is colorable or not.
func setup_unified_select_picker():

	var tool_type = "ObjectTool"
	var location = "select"
	if not ui_config.has(tool_type): return
	if not ui_config[tool_type].has(location): return
	var ui_element = ui_config[tool_type][location]
	if not ui_element.has("select_tint_relocated"): return
	if ui_element["palette"] == null: return
	if not ui_element.has("custom_color_palette"): return
	if ui_element["custom_color_palette"] == null: return

	var palette = ui_element["palette"]
	var custom_color_palette = ui_element["custom_color_palette"]
	var vbox = find_select_vbox(tool_type)
	if vbox == null: return

	# Move the tint palette to just after the Custom Color palette (physically reparent it)
	palette.get_parent().remove_child(palette)
	vbox.add_child(palette)
	vbox.move_child(palette, custom_color_palette.get_index() + 1)
	palette.visible = false  # hidden by default, visibility controlled by set_custom_color_palette_visible

	# Create a "Tint Color" label just before the relocated tint palette (only shown in mixed selections)
	var tint_label = Label.new()
	tint_label.text = "Tint Color"
	tint_label.visible = false
	vbox.add_child(tint_label)
	vbox.move_child(tint_label, palette.get_index())
	ui_element["unified_tint_label"] = tint_label

	outputlog("setup_unified_select_picker: done", 0)


#########################################################################################################
##
## SET UI TO SELECTED NODE VALUES FUNCTIONS
##
#########################################################################################################

# Function to set the colour ui to reflect the values of the passed node, noting that this should generally be a selected node
func set_colour_ui_to_selected_node_values(node: Node2D, tool_type: String):

	var location = "select"

	outputlog("set_colour_ui_to_selected_node_values",2)

	outputlog("set_colour_ui_to_selected_node_values: tool_type=" + str(tool_type) + " node_id=" + str(global.Editor.Tools["SelectTool"].Selected[0].get_meta("node_id")) + " has_data=" + str(customdatamanager.has_data(global.Editor.Tools["SelectTool"].Selected[0].get_meta("node_id"))),0)

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
			# Restore opacity: prefer explicit opacity key, fall back to colour alpha
			if node_data.has("opacity"):
				ui_element["opacity_slider"].slider_and_spinbox_change(node_data["opacity"],true)
			else:
				ui_element["opacity_slider"].slider_and_spinbox_change(Color(node_data["colour"]).a,true)

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
					ui_element["saturation_slider"].slider_and_spinbox_change(saturation_to_slider(node_data["saturation"]), true)
				if node_data.has("hue_shift"):
					ui_element["hue_slider"].slider_and_spinbox_change(node_data["hue_shift"], true)
				else:
					ui_element["hue_slider"].slider_and_spinbox_change(0.0, true)
				if node_data.has("lightness"):
					ui_element["lightness_slider"].slider_and_spinbox_change(node_data["lightness"], true)
				else:
					ui_element["lightness_slider"].slider_and_spinbox_change(0.0, true)
				if node_data.has("contrast"):
					ui_element["contrast_slider"].slider_and_spinbox_change(node_data["contrast"], true)
				else:
					ui_element["contrast_slider"].slider_and_spinbox_change(0.0, true)
				if node_data.has("invert"):
					set_property_but_block_signals(ui_element["invert_button"], "pressed", node_data["invert"])
				else:
					set_property_but_block_signals(ui_element["invert_button"], "pressed", false)
				if node_data.has("sat_levels"):
					set_property_but_block_signals(ui_element["sat_levels_slider"].minSlider, "value", node_data["sat_levels"]["blacks"])
					set_property_but_block_signals(ui_element["sat_levels_slider"].maxSlider, "value", node_data["sat_levels"]["whites"])
					ui_element["sat_midtones_slider"].slider_and_spinbox_change(gamma_to_slider(node_data["sat_levels"]["midtones"]), true)
				else:
					set_property_but_block_signals(ui_element["sat_levels_slider"].minSlider, "value", 0.0)
					set_property_but_block_signals(ui_element["sat_levels_slider"].maxSlider, "value", 1.0)
					ui_element["sat_midtones_slider"].slider_and_spinbox_change(0.5, true)
				if node_data.has("sat_output_levels"):
					set_property_but_block_signals(ui_element["sat_output_levels_slider"].minSlider, "value", node_data["sat_output_levels"]["out_blacks"])
					set_property_but_block_signals(ui_element["sat_output_levels_slider"].maxSlider, "value", node_data["sat_output_levels"]["out_whites"])
				else:
					set_property_but_block_signals(ui_element["sat_output_levels_slider"].minSlider, "value", 0.0)
					set_property_but_block_signals(ui_element["sat_output_levels_slider"].maxSlider, "value", 1.0)
				# Restore colorable protection checkboxes
				if node_data.has("colorable_protect"):
					set_property_but_block_signals(ui_element["colorable_protect_hue"], "pressed", node_data["colorable_protect"]["hue"])
					set_property_but_block_signals(ui_element["colorable_protect_sat"], "pressed", node_data["colorable_protect"]["saturation"])
					set_property_but_block_signals(ui_element["colorable_protect_light"], "pressed", node_data["colorable_protect"]["lightness"])
				else:
					set_property_but_block_signals(ui_element["colorable_protect_hue"], "pressed", true)
					set_property_but_block_signals(ui_element["colorable_protect_sat"], "pressed", true)
					set_property_but_block_signals(ui_element["colorable_protect_light"], "pressed", true)
		
		outputlog("get colour config: " + str(get_colour_config_from_ui(tool_type, location)),3)
		_on_colour_option_button_pressed(true, node_data["shader_type"], tool_type, location, false)

	# If there is no data then we have selected a non-coloured asset and should update the palette items accordingly
	else:
		# Reset to white
		if not tool_type in NON_CUSTOM_PALETTE_TOOLS:
			ui_config[tool_type][location]["palette"].SetColor(Color.white,false)
			ui_element["opacity_slider"].slider_and_spinbox_change(1.0,true)
		else:
			force_refresh_dd_custom_colour_ui_from_selected_node(node, tool_type)

		# Reset all saturation mode sliders to default values
		ui_element["saturation_slider"].slider_and_spinbox_change(0.5, true)
		ui_element["hue_slider"].slider_and_spinbox_change(0.0, true)
		ui_element["lightness_slider"].slider_and_spinbox_change(0.0, true)
		ui_element["contrast_slider"].slider_and_spinbox_change(0.0, true)
		set_property_but_block_signals(ui_element["invert_button"], "pressed", false)
		set_property_but_block_signals(ui_element["sat_levels_slider"].minSlider, "value", 0.0)
		set_property_but_block_signals(ui_element["sat_levels_slider"].maxSlider, "value", 1.0)
		ui_element["sat_midtones_slider"].slider_and_spinbox_change(0.5, true)
		set_property_but_block_signals(ui_element["sat_output_levels_slider"].minSlider, "value", 0.0)
		set_property_but_block_signals(ui_element["sat_output_levels_slider"].maxSlider, "value", 1.0)
		# Reset colorable protection checkboxes to default (all protected)
		set_property_but_block_signals(ui_element["colorable_protect_hue"], "pressed", true)
		set_property_but_block_signals(ui_element["colorable_protect_sat"], "pressed", true)
		set_property_but_block_signals(ui_element["colorable_protect_light"], "pressed", true)

		_on_colour_option_button_pressed(true, "none", tool_type, location, false)
	
	# Show non-gradient buttons (HSL) for all tools now
	# Previously we hid them for colorable objects and walls, but now we support HSL on those too
	show_non_gradient_buttons(tool_type,location)

	# Auto-switch between Custom Color and Tint palette in the unified select panel
	if tool_type == "ObjectTool" and location == "select":
		var has_colorable = false
		var has_non_colorable = false
		for node in global.Editor.Tools["SelectTool"].Selected:
			if get_node_type(node) == "objects":
				if node.HasCustomColor():
					has_colorable = true
				else:
					has_non_colorable = true
		if has_colorable and has_non_colorable:
			# Mixed selection: show both pickers
			set_custom_color_palette_visible_mixed(tool_type, location)
		else:
			set_custom_color_palette_visible(tool_type, location, has_colorable)
	
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
		var selectable_key = str(global.Editor.Tools["SelectTool"].GetSelectableType(global.Editor.Tools["SelectTool"].Selected[0]))
		if not TOOL_TYPE_LOOKUP_BY_SELECTABLE.has(selectable_key):
			return
		tool_type = TOOL_TYPE_LOOKUP_BY_SELECTABLE[selectable_key]
		if tool_type == null:
			outputlog("set_colour_palette_to_selection: tool_type is null, returning", 0)
			return
	else:
		return
	
	outputlog("set_colour_palette_to_selection(): tool_type: " + str(tool_type),0)

	# If the Options vboxes are visible then only a single type is selected. This should always be the case when the function is called.
	# If we do not have only one type of asset chosen then return
	if find_select_vbox(tool_type) != null:
		outputlog("set_colour_palette_to_selection: vbox visible: " + str(find_select_vbox(tool_type).visible), 0)
		# If the select options is not visible then we have multiple types and we should stop and return
		if not find_select_vbox(tool_type).visible:
			outputlog("select vbox not visible",0)
			if not check_all_nodes_of_same_type(global.Editor.Tools["SelectTool"].Selected):
				outputlog("set_colour_palette_to_selection: not all same type, returning", 0)
				return
		
		outputlog("set_colour_palette_to_selection: calling set_colour_ui_to_selected_node_values", 0)
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
			colour_config["saturation"] = slider_to_saturation(ui_element["saturation_slider"].value)
			colour_config["hue_shift"] = ui_element["hue_slider"].value
			colour_config["lightness"] = ui_element["lightness_slider"].value
			colour_config["contrast"] = ui_element["contrast_slider"].value
			colour_config["invert"] = ui_element["invert_button"].pressed
			colour_config["sat_levels"] = {
				"blacks": ui_element["sat_levels_slider"].minSlider.value,
				"midtones": slider_to_gamma(ui_element["sat_midtones_slider"].value),
				"whites": ui_element["sat_levels_slider"].maxSlider.value
			}
			colour_config["sat_output_levels"] = {
				"out_blacks": ui_element["sat_output_levels_slider"].minSlider.value,
				"out_whites": ui_element["sat_output_levels_slider"].maxSlider.value
			}
			# Colorable protection: when checked, the slider does NOT affect custom color areas
			colour_config["colorable_protect"] = {
				"hue": ui_element["colorable_protect_hue"].pressed,
				"saturation": ui_element["colorable_protect_sat"].pressed,
				"lightness": ui_element["colorable_protect_light"].pressed
			}

	# For patterns or walls
	if tool_type in NON_CUSTOM_PALETTE_TOOLS:
		if ui_element["custom_color_button"] != null:
			outputlog("custom_color_button is not null",3)
			outputlog("custom_color_button color: " + str(ui_element["custom_color_button"].color.to_html()),3)
			outputlog("custom_color_button picker color: " + str(ui_element["custom_color_button"].get_picker().color.to_html()),3)
			# Note we are using the color picker color here as there seems to be a delay in the colour palette updating
			var pattern_color = ui_element["custom_color_button"].color
			# Apply opacity from slider for patterns
			if ui_element.has("opacity_slider"):
				pattern_color.a = ui_element["opacity_slider"].value
			colour_config["colour"] = pattern_color.to_html()
			colour_config["opacity"] = pattern_color.a
		else:
			colour_config["colour"] = "ffffffff"
			colour_config["opacity"] = 1.0
	else:
		# Note we are using the color picker color here as there seems to be a delay in the colour palette updating
		colour_config["colour"] = ui_element["palette"].colorPicker.color.to_html()
		# Store opacity from slider explicitly (needed for colorable objects where colour gets reset to white)
		if ui_element.has("opacity_slider"):
			colour_config["opacity"] = ui_element["opacity_slider"].value
		# Also store the custom color for colorable objects (from DD's custom color palette)
		if ui_element.has("custom_color_palette") and ui_element["custom_color_palette"] != null:
			var custom_palette = ui_element["custom_color_palette"]
			if custom_palette.has_method("get_picker"):
				colour_config["colorable_custom_color"] = custom_palette.get_picker().color.to_html()
			elif custom_palette.get("colorPicker") != null:
				colour_config["colorable_custom_color"] = custom_palette.colorPicker.color.to_html()

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


# Helper: call at the start of each UI change handler to ensure previous changes are finalized
# before starting a new type of change. This produces one undo point per change type.
func _begin_change(source: String):
	if _current_change_source != "" and _current_change_source != source:
		# A different type of change was in progress — finalize it
		combinedshader.finalize_pending_history()
	_current_change_source = source

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
## COPY AND PASTE COLOUR SETTINGS FUNCTIONS
##
#########################################################################################################

# Copy the colour/shader settings from the first selected node to the clipboard
func copy_colour_settings(tool_type: String):

	outputlog("copy_colour_settings: " + str(tool_type), 0)

	var selected = global.Editor.Tools["SelectTool"].Selected
	if selected.size() == 0:
		outputlog("copy_colour_settings: nothing selected", 0)
		return

	var node = selected[0]
	if not is_instance_valid(node): return
	if not node.has_meta("node_id"): return

	var node_id = node.get_meta("node_id")
	var node_type = TYPE_LOOKUP.get(tool_type, "")
	if node_type == "": return

	# Get the stored data for this node
	var data = customdatamanager.get_data_or_default(node_id)

	# Extract only the colour/shader keys
	clipboard_data = {}
	for key in CLIPBOARD_KEYS:
		if data.has(key):
			# Deep copy dictionaries and arrays
			if data[key] is Dictionary:
				clipboard_data[key] = data[key].duplicate(true)
			elif data[key] is Array:
				clipboard_data[key] = data[key].duplicate(true)
			else:
				clipboard_data[key] = data[key]

	clipboard_type = node_type

	# For colorable objects, always capture the current DD custom color from the node directly
	if node_type == "objects" and node.has_method("HasCustomColor") and node.HasCustomColor():
		clipboard_data["colorable_custom_color"] = node.GetCustomColor().to_html()

	outputlog("copy_colour_settings: copied from node " + str(node_id) + " type: " + str(node_type) + " data: " + str(clipboard_data), 0)

	# Update the paste button state for all tools
	_update_paste_button_states()

# Paste the clipboard colour/shader settings to all selected nodes of the same type
func paste_colour_settings(tool_type: String):

	outputlog("paste_colour_settings: " + str(tool_type), 0)

	if clipboard_data == null or clipboard_data.empty():
		outputlog("paste_colour_settings: clipboard is empty", 0)
		return

	var node_type = TYPE_LOOKUP.get(tool_type, "")
	if node_type == "": return

	# Check type compatibility
	if clipboard_type != node_type:
		outputlog("paste_colour_settings: type mismatch. clipboard=" + str(clipboard_type) + " target=" + str(node_type), 0)
		return

	var selected = global.Editor.Tools["SelectTool"].Selected
	if selected.size() == 0: return

	# Apply to each selected node
	for node in selected:
		if not is_instance_valid(node): continue
		if not node.has_meta("node_id"): continue

		var node_id = node.get_meta("node_id")
		if not global.World.HasNodeID(node_id): continue

		# Build the config to apply from the clipboard data
		var paste_config = clipboard_data.duplicate(true)
		paste_config["type"] = node_type

		# Record history before applying
		combinedshader.add_update_history_data(node_id, tool_type, customdatamanager.get_data_or_default(node_id))

		# For colorable objects, apply the custom color from clipboard to DD's node
		if node_type == "objects" and node.has_method("HasCustomColor") and node.HasCustomColor():
			if paste_config.has("colorable_custom_color") and paste_config["colorable_custom_color"] != null:
				node.SetCustomColor(Color(paste_config["colorable_custom_color"]))

		# Apply the settings to the node
		set_tint_colour(node_id, node_type, paste_config, false)

		# Record history after applying
		combinedshader.add_update_history_data(node_id, tool_type, paste_config)

	# Update the UI to reflect the first selected node's new state
	if selected.size() > 0 and is_instance_valid(selected[0]):
		set_colour_palette_to_selection()

	outputlog("paste_colour_settings: applied to " + str(selected.size()) + " nodes", 0)

# Update paste button enabled/disabled state based on clipboard compatibility
func _update_paste_button_states():
	for tool_type in BUILD_THESE_TOOLS:
		if not ui_config.has(tool_type): continue
		if not ui_config[tool_type].has("select"): continue
		var ui_element = ui_config[tool_type]["select"]
		if ui_element.has("paste_settings_button"):
			var node_type = TYPE_LOOKUP.get(tool_type, "")
			ui_element["paste_settings_button"].disabled = (clipboard_data == null or clipboard_type != node_type)

#########################################################################################################
##
## NATURAL COLOR VARIANTS
##
#########################################################################################################

# Default randomisation range (fraction, so 0.15 = +/- 15%)
const NATURAL_VARIANT_RANGE = 0.10

# Toggle advanced settings visibility
func _on_variants_advanced_toggled(pressed: bool, tool_type: String, location: String):
	var ui_element = ui_config[tool_type][location]
	if ui_element.has("variants_advanced_vbox"):
		ui_element["variants_advanced_vbox"].visible = pressed

# Called when the Color Variants toggle is switched on/off in main panel
func _on_variants_toggle_changed(pressed: bool, tool_type: String):
	if pressed:
		_regenerate_preview_variant_offsets(tool_type)
	else:
		_preview_variant_offsets = {}
	set_preview_colour(tool_type, true)

# Reset range slider to default (10%)
func _on_variants_range_reset_pressed(tool_type: String, location: String):
	var ui_element = ui_config[tool_type][location]
	if ui_element.has("variants_range_slider"):
		ui_element["variants_range_slider"].slider_and_spinbox_change(10.0, false)

# Apply subtle random colour variations to each selected object
func _on_natural_variants_pressed(tool_type: String):

	outputlog("_on_natural_variants_pressed: " + str(tool_type), 0)

	var location = "select"
	var node_type = TYPE_LOOKUP.get(tool_type, "")
	if node_type == "": return

	var selected = global.Editor.Tools["SelectTool"].Selected
	if selected.size() == 0: return

	# Apply a unique random offset to each selected node based on its own current values
	for node in selected:
		if not is_instance_valid(node): continue
		if not node.has_meta("node_id"): continue

		var node_id = node.get_meta("node_id")
		if not global.World.HasNodeID(node_id): continue

		# Record history before change
		combinedshader.add_update_history_data(node_id, tool_type, customdatamanager.get_data_or_default(node_id))

		# Apply variant
		_apply_variant_to_node(node_id, tool_type, location)

		# Record history after change
		combinedshader.add_update_history_data(node_id, tool_type, customdatamanager.get_data_or_default(node_id))

	# Refresh the UI to show the first selected node's values
	if selected.size() > 0 and is_instance_valid(selected[0]):
		set_colour_palette_to_selection()

	outputlog("_on_natural_variants_pressed: applied variants to " + str(selected.size()) + " nodes", 0)

# Apply a single random colour variation to a specific node (used by both select-tool and auto-placement)
func _apply_variant_to_node(node_id: int, tool_type: String, location: String):

	var node_type = TYPE_LOOKUP.get(tool_type, "")
	if node_type == "": return

	if not global.World.HasNodeID(node_id): return

	var ui_element = ui_config[tool_type][location]

	# Read settings from advanced panel if available, otherwise use defaults
	var variant_range = NATURAL_VARIANT_RANGE
	var do_hue = true
	var do_saturation = true
	var do_gamma = true
	var do_levels = true

	if ui_element.has("variants_range_slider"):
		variant_range = ui_element["variants_range_slider"].value / 100.0
	if ui_element.has("variants_cb_hue"):
		do_hue = ui_element["variants_cb_hue"].pressed
	if ui_element.has("variants_cb_saturation"):
		do_saturation = ui_element["variants_cb_saturation"].pressed
	if ui_element.has("variants_cb_gamma"):
		do_gamma = ui_element["variants_cb_gamma"].pressed
	if ui_element.has("variants_cb_levels"):
		do_levels = ui_element["variants_cb_levels"].pressed

	# Get this node's stored data as the base
	var node_data = customdatamanager.get_data_or_default(node_id)
	node_data["type"] = node_type

	var base_saturation = node_data["saturation"] if node_data.has("saturation") else 1.0
	var base_hue = node_data["hue_shift"] if node_data.has("hue_shift") else 0.0
	var base_gamma = 1.0
	var base_blacks = 0.0
	var base_whites = 1.0
	if node_data.has("sat_levels"):
		if node_data["sat_levels"].has("midtones"):
			base_gamma = node_data["sat_levels"]["midtones"]
		if node_data["sat_levels"].has("blacks"):
			base_blacks = node_data["sat_levels"]["blacks"]
		if node_data["sat_levels"].has("whites"):
			base_whites = node_data["sat_levels"]["whites"]

	node_data["shader_type"] = "saturation"

	if not node_data.has("sat_levels"):
		node_data["sat_levels"] = {"blacks": 0.0, "midtones": 1.0, "whites": 1.0}
	if not node_data.has("sat_output_levels"):
		node_data["sat_output_levels"] = {"out_blacks": 0.0, "out_whites": 1.0}
	if not node_data.has("contrast"):
		node_data["contrast"] = 0.0
	if not node_data.has("lightness"):
		node_data["lightness"] = 0.0
	if not node_data.has("invert"):
		node_data["invert"] = false

	if do_saturation:
		var base_sat_slider = saturation_to_slider(base_saturation)
		var new_sat_slider = clamp(base_sat_slider + rand_range(-variant_range, variant_range), 0.0, 1.0)
		node_data["saturation"] = slider_to_saturation(new_sat_slider)

	if do_hue:
		node_data["hue_shift"] = clamp(base_hue + 2.0 * rand_range(-variant_range, variant_range), -1.0, 1.0)

	if do_gamma:
		var base_gamma_slider = gamma_to_slider(base_gamma)
		var new_gamma_slider = clamp(base_gamma_slider + rand_range(-variant_range, variant_range), 0.0, 1.0)
		node_data["sat_levels"]["midtones"] = slider_to_gamma(new_gamma_slider)

	if do_levels:
		node_data["sat_levels"]["blacks"] = clamp(base_blacks + rand_range(-variant_range, variant_range), 0.0, 1.0)
		node_data["sat_levels"]["whites"] = clamp(base_whites + rand_range(-variant_range, variant_range), 0.0, 1.0)
		if node_data["sat_levels"]["blacks"] >= node_data["sat_levels"]["whites"]:
			node_data["sat_levels"]["blacks"] = base_blacks
			node_data["sat_levels"]["whites"] = base_whites

	set_tint_colour(node_id, node_type, node_data, false)

# Generate new random offsets for the preview variant display
func _regenerate_preview_variant_offsets(tool_type: String):
	var location = "main"
	if not ui_config.has(tool_type): return
	if not ui_config[tool_type].has(location): return
	var ui_element = ui_config[tool_type][location]

	var variant_range = NATURAL_VARIANT_RANGE
	if ui_element.has("variants_range_slider"):
		variant_range = ui_element["variants_range_slider"].value / 100.0

	_preview_variant_offsets = {
		"sat_slider_offset": rand_range(-variant_range, variant_range),
		"hue_offset": 2.0 * rand_range(-variant_range, variant_range),
		"gamma_slider_offset": rand_range(-variant_range, variant_range),
		"blacks_offset": rand_range(-variant_range, variant_range),
		"whites_offset": rand_range(-variant_range, variant_range)
	}

# Apply stored preview variant offsets to a colour_config dictionary (modifies in place)
func _apply_preview_variant_to_config(colour_config: Dictionary, tool_type: String):
	var location = "main"
	if not ui_config.has(tool_type): return colour_config
	if not ui_config[tool_type].has(location): return colour_config
	var ui_element = ui_config[tool_type][location]
	if _preview_variant_offsets.empty(): return colour_config

	var do_hue = true
	var do_saturation = true
	var do_gamma = true
	var do_levels = true
	if ui_element.has("variants_cb_hue"):
		do_hue = ui_element["variants_cb_hue"].pressed
	if ui_element.has("variants_cb_saturation"):
		do_saturation = ui_element["variants_cb_saturation"].pressed
	if ui_element.has("variants_cb_gamma"):
		do_gamma = ui_element["variants_cb_gamma"].pressed
	if ui_element.has("variants_cb_levels"):
		do_levels = ui_element["variants_cb_levels"].pressed

	# Ensure saturation mode keys exist
	colour_config["shader_type"] = "saturation"
	if not colour_config.has("saturation"):
		colour_config["saturation"] = 1.0
	if not colour_config.has("hue_shift"):
		colour_config["hue_shift"] = 0.0
	if not colour_config.has("sat_levels"):
		colour_config["sat_levels"] = {"blacks": 0.0, "midtones": 1.0, "whites": 1.0}
	if not colour_config.has("sat_output_levels"):
		colour_config["sat_output_levels"] = {"out_blacks": 0.0, "out_whites": 1.0}
	if not colour_config.has("contrast"):
		colour_config["contrast"] = 0.0
	if not colour_config.has("lightness"):
		colour_config["lightness"] = 0.0
	if not colour_config.has("invert"):
		colour_config["invert"] = false

	if do_saturation:
		var base_sat_slider = saturation_to_slider(colour_config["saturation"])
		colour_config["saturation"] = slider_to_saturation(clamp(base_sat_slider + _preview_variant_offsets["sat_slider_offset"], 0.0, 1.0))

	if do_hue:
		colour_config["hue_shift"] = clamp(colour_config["hue_shift"] + _preview_variant_offsets["hue_offset"], -1.0, 1.0)

	if do_gamma:
		var base_gamma_slider = gamma_to_slider(colour_config["sat_levels"]["midtones"])
		colour_config["sat_levels"]["midtones"] = slider_to_gamma(clamp(base_gamma_slider + _preview_variant_offsets["gamma_slider_offset"], 0.0, 1.0))

	if do_levels:
		var base_blacks = colour_config["sat_levels"]["blacks"]
		var base_whites = colour_config["sat_levels"]["whites"]
		colour_config["sat_levels"]["blacks"] = clamp(base_blacks + _preview_variant_offsets["blacks_offset"], 0.0, 1.0)
		colour_config["sat_levels"]["whites"] = clamp(base_whites + _preview_variant_offsets["whites_offset"], 0.0, 1.0)
		if colour_config["sat_levels"]["blacks"] >= colour_config["sat_levels"]["whites"]:
			colour_config["sat_levels"]["blacks"] = base_blacks
			colour_config["sat_levels"]["whites"] = base_whites

	return colour_config

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

# Function to check if the selection contains colorable assets (objects with HasCustomColor or colorable patterns)
func is_selection_colorable(tool_type: String) -> bool:

	outputlog("is_selection_colorable",2)
	
	# Check if any selected item is colorable
	for node in global.Editor.Tools["SelectTool"].Selected:
		if get_node_type(node) == "objects":
			if node.HasCustomColor():
				return true
		elif get_node_type(node) == "pattern_shapes":
			if combinedshader.is_colorable_pattern(node):
				return true
	
	return false

# Helper: check if the currently selected object in the main panel library is colorable
func _is_current_main_object_colorable(tool_type: String) -> bool:
	if not is_object_tool_type(tool_type):
		return false
	var preview_node = get_preview_node(tool_type)
	if preview_node != null and preview_node.has_method("HasCustomColor"):
		return preview_node.HasCustomColor()
	return false

# Function to update colorable protect checkbox visibility based on current selection
func update_colorable_protect_visibility(tool_type: String, location: String):
	var ui_element = get_ui_element(tool_type, location)
	if ui_element == null:
		return
	if not ui_element.has("colorable_protect_hbox"):
		return
	# Only show if saturation mode is active
	var sat_active = ui_element["saturate_button"].pressed
	if not sat_active:
		ui_element["colorable_protect_hbox"].visible = false
		return
	# Check if selection is colorable
	if location == "select":
		ui_element["colorable_protect_hbox"].visible = is_selection_colorable(tool_type)
	elif location == "main":
		ui_element["colorable_protect_hbox"].visible = _is_current_main_object_colorable(tool_type)

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

		# For colorable objects, apply custom color from config to DD's node (for undo/redo and paste)
		if type == "objects" and node.has_method("HasCustomColor") and node.HasCustomColor():
			if colour_config.has("colorable_custom_color") and colour_config["colorable_custom_color"] != null:
				var target_color = Color(colour_config["colorable_custom_color"])
				if node.GetCustomColor() != target_color:
					node.SetCustomColor(target_color)

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
		# Use colorPicker.color as palette.color may lag behind when using the eyedropper
		colour = ui_element["palette"].colorPicker.color
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

	# Save previous texture before overwriting store_preview_config
	var _previous_preview_texture = store_preview_config.get("texture", "")

	# Update stored values which include the colours
	store_preview_config = colour_config.duplicate(true)
	
	# Get the texture of the preview node, which is needed to know if the preview has changed to cycling through object library using scroll
	if get_asset_texture(preview_node,tool_type) != null:
		store_preview_config["texture"] = get_asset_texture(preview_node,tool_type).resource_path

	outputlog("store_preview_config: " + str(store_preview_config),2)

	# Check if Color Variants toggle is active for this tool
	var variants_active = false
	if tool_type in ["ObjectTool", "ScatterTool"]:
		if ui_element.has("natural_variants_button"):
			variants_active = ui_element["natural_variants_button"].pressed

	# If Color Variants toggle is active and a new preview cycle is needed, regenerate offsets
	# The flag is set by: Core.gd preview_changed (asset cycle) and set_tint_colour_on_new_node (after placement)
	if variants_active and _preview_asset_changed:
		_preview_asset_changed = false
		_regenerate_preview_variant_offsets(tool_type)

	# If there is no preview and the data is default only (but allow through if variants are active)
	if customdatamanager.is_data_default(colour_config) and not variants_active:

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

	# Apply Color Variants offsets to preview if toggle is active
	if variants_active:
		colour_config = _apply_preview_variant_to_config(colour_config, tool_type)

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

	outputlog("refresh_colours_on_walls",2)

	# If we need a delay then implement it
	if delay > 0.0:
		yield(global.Editor.get_tree().create_timer(delay), "timeout")

	# Re-apply wall colour data from stored mod data
	customdatamanager.apply_custom_data_to_map(["walls"], 0.0)

# Called when a new wall node appears (e.g. from a split). Looks at the new wall's joints
# to find a sibling wall that has mod data and propagates it.
func propagate_wall_data_to_new_wall(new_wall: Node2D, source_wall_id: int = -1):

	outputlog("propagate_wall_data_to_new_wall: " + str(new_wall) + " source_id=" + str(source_wall_id), 0)

	if new_wall == null or not is_instance_valid(new_wall):
		return
	if not new_wall.has_meta("node_id"):
		return

	var new_id = new_wall.get_meta("node_id")

	# If the new wall already has mod data, nothing to do
	if customdatamanager.has_data(new_id):
		return

	# Copy data from source wall if known and has tint data
	if source_wall_id >= 0 and customdatamanager.has_data(source_wall_id):
		var sdata = customdatamanager.get_data(source_wall_id)
		if sdata.has("type") and sdata["type"] == "walls":
			set_tint_colour(new_id, "walls", sdata.duplicate(true), true)
			yield(global.Editor.get_tree().create_timer(0.02), "timeout")
			if new_wall != null and is_instance_valid(new_wall):
				refresh_colours_on_walls(global.World.GetCurrentLevel(), 0.0)

# When a DD custom colour control changes the colour
func on_dd_custom_color_control_changed(_ignore_this, _ignore_this_too, tool_type: String, location: String):

	outputlog("on_dd_custom_color_control_changed",2)
	_begin_change("custom_color")

	var ui_element = ui_config[tool_type][location]

	# Propagate any alpha change to the opacity slider
	if ui_element.has("custom_color_button"):
		ui_element["opacity_slider"].set_value(ui_element["custom_color_button"].color.a, true)

	# Update the stored ui config
	refresh_combined_ui_stored_state(tool_type, location)

	var colour_config = customdatamanager.get_combined_ui_stored_state(tool_type, location)

	# For some tool types, this should drive a reset
	match tool_type:
		"ObjectTool","ScatterTool","PathTool":
			# Don't reset if we're in saturation mode - just update the selection
			if colour_config.has("shader_type") and colour_config["shader_type"] == "saturation":
				if location == "select":
					set_colour_of_selection(tool_type, false)
					create_update_custom_history(null, tool_type, location, 0.0)
			else:
				# Hit the reset function
				_on_reset_button_pressed(tool_type, location)
				if location == "select":
					set_object_library_grid_custom_colour_to_dd_palette_colour(tool_type, location)
					create_update_custom_history(null, tool_type, location, 0.0)

		# For wall and patternshape tools, we want to update the image as this is the core colour value (if for some reason we want to tint the gradient)
		"WallTool","PatternShapeTool":
			if location == "select":
				set_colour_of_selection(tool_type, false)
				create_update_custom_history(null, tool_type, location, 0.0)

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
	_begin_change("levels_default")

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
	_begin_change("levels")

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
	_begin_change("saturation")

	# Update the stored ui config
	refresh_combined_ui_stored_state(tool_type, location)

	# Only make an active change if there is something selected
	match location:
		"select":
			set_colour_of_selection(tool_type, false)
	
		# If we are in the main location and the preview button is enabled then update the preview
		"main":
			set_preview_colour(tool_type, false)

# Function to respond to changes if the hue slider is changed.
func _on_hue_slider_value_changed(_value: float, tool_type: String, location: String):

	outputlog("_on_hue_slider_value_changed",3)

	# Use call_deferred to ensure the slider value is fully updated before processing
	call_deferred("_apply_hue_change", tool_type, location)

# Deferred function to apply hue change after slider value is synchronized
func _apply_hue_change(tool_type: String, location: String):
	_begin_change("hue")

	# Update the stored ui config
	refresh_combined_ui_stored_state(tool_type, location)

	# Only make an active change if there is something selected
	match location:
		"select":
			set_colour_of_selection(tool_type, false)
	
		# If we are in the main location and the preview button is enabled then update the preview
		"main":
			set_preview_colour(tool_type, false)

# Function to respond to changes if any saturation levels slider is changed.
func _on_sat_levels_slider_value_changed(_value: float, tool_type: String, location: String):

	outputlog("_on_sat_levels_slider_value_changed",3)
	_begin_change("sat_levels")

	# Update the stored ui config
	refresh_combined_ui_stored_state(tool_type, location)

	# Only make an active change if there is something selected
	match location:
		"select":
			set_colour_of_selection(tool_type, false)
	
		# If we are in the main location and the preview button is enabled then update the preview
		"main":
			set_preview_colour(tool_type, false)

# Function to respond to changes if the lightness slider is changed.
func _on_lightness_slider_value_changed(_value: float, tool_type: String, location: String):

	outputlog("_on_lightness_slider_value_changed",3)
	_begin_change("lightness")

	# Use call_deferred to ensure the slider value is fully updated before processing
	call_deferred("_apply_lightness_change", tool_type, location)

# Deferred function to apply lightness change after slider value is synchronized
func _apply_lightness_change(tool_type: String, location: String):

	# Update the stored ui config
	refresh_combined_ui_stored_state(tool_type, location)

	# Only make an active change if there is something selected
	match location:
		"select":
			set_colour_of_selection(tool_type, false)
	
		# If we are in the main location and the preview button is enabled then update the preview
		"main":
			set_preview_colour(tool_type, false)

# Function to respond to changes if the contrast slider is changed.
func _on_contrast_slider_value_changed(_value: float, tool_type: String, location: String):

	outputlog("_on_contrast_slider_value_changed",3)
	_begin_change("contrast")

	# Use call_deferred to ensure the slider value is fully updated before processing
	call_deferred("_apply_contrast_change", tool_type, location)

# Deferred function to apply contrast change after slider value is synchronized
func _apply_contrast_change(tool_type: String, location: String):

	# Update the stored ui config
	refresh_combined_ui_stored_state(tool_type, location)

	# Only make an active change if there is something selected
	match location:
		"select":
			set_colour_of_selection(tool_type, false)
	
		# If we are in the main location and the preview button is enabled then update the preview
		"main":
			set_preview_colour(tool_type, false)

# Function to respond to changes if the invert button is toggled
func _on_invert_button_toggled(pressed: bool, tool_type: String, location: String):

	outputlog("_on_invert_button_toggled",3)
	_begin_change("invert")

	# Update the stored ui config
	refresh_combined_ui_stored_state(tool_type, location)

	# Only make an active change if there is something selected
	match location:
		"select":
			set_colour_of_selection(tool_type, false)
			create_update_custom_history(null, tool_type, location, 0.0)
	
		# If we are in the main location and the preview button is enabled then update the preview
		"main":
			set_preview_colour(tool_type, false)

# Function called when any colorable protection checkbox is toggled
func _on_colorable_protect_toggled(pressed: bool, tool_type: String, location: String):

	outputlog("_on_colorable_protect_toggled",3)
	_begin_change("colorable_protect")

	# Update the stored ui config
	refresh_combined_ui_stored_state(tool_type, location)

	# Only make an active change if there is something selected
	match location:
		"select":
			set_colour_of_selection(tool_type, false)
			create_update_custom_history(null, tool_type, location, 0.0)
		"main":
			set_preview_colour(tool_type, false)

# Function to reset saturation slider to default
func _on_saturation_reset_pressed(tool_type: String, location: String):
	outputlog("_on_saturation_reset_pressed",3)
	var ui_element = ui_config[tool_type][location]
	ui_element["saturation_slider"].slider_and_spinbox_change(0.5, false)
	_on_saturation_slider_value_changed(0.5, tool_type, location)
	create_update_custom_history(null, tool_type, location, 0.0)

# Function to reset hue slider to default
func _on_hue_reset_pressed(tool_type: String, location: String):
	outputlog("_on_hue_reset_pressed",3)
	var ui_element = ui_config[tool_type][location]
	ui_element["hue_slider"].slider_and_spinbox_change(0.0, false)
	_on_hue_slider_value_changed(0.0, tool_type, location)
	create_update_custom_history(null, tool_type, location, 0.0)

# Function to reset input levels slider to default
func _on_sat_levels_reset_pressed(tool_type: String, location: String):
	outputlog("_on_sat_levels_reset_pressed",3)
	var ui_element = ui_config[tool_type][location]
	set_property_but_block_signals(ui_element["sat_levels_slider"].minSlider, "value", 0.0)
	set_property_but_block_signals(ui_element["sat_levels_slider"].maxSlider, "value", 1.0)
	_on_sat_levels_slider_value_changed(0.0, tool_type, location)
	create_update_custom_history(null, tool_type, location, 0.0)

# Function to reset gamma/midtones slider to default
func _on_sat_midtones_reset_pressed(tool_type: String, location: String):
	outputlog("_on_sat_midtones_reset_pressed",3)
	var ui_element = ui_config[tool_type][location]
	ui_element["sat_midtones_slider"].slider_and_spinbox_change(0.5, false)
	_on_sat_levels_slider_value_changed(0.5, tool_type, location)
	create_update_custom_history(null, tool_type, location, 0.0)

# Function to reset lightness slider to default
func _on_lightness_reset_pressed(tool_type: String, location: String):
	outputlog("_on_lightness_reset_pressed",3)
	var ui_element = ui_config[tool_type][location]
	ui_element["lightness_slider"].slider_and_spinbox_change(0.0, false)
	_on_lightness_slider_value_changed(0.0, tool_type, location)
	create_update_custom_history(null, tool_type, location, 0.0)

# Function to reset contrast slider to default
func _on_contrast_reset_pressed(tool_type: String, location: String):
	outputlog("_on_contrast_reset_pressed",3)
	var ui_element = ui_config[tool_type][location]
	ui_element["contrast_slider"].slider_and_spinbox_change(0.0, false)
	_on_contrast_slider_value_changed(0.0, tool_type, location)
	create_update_custom_history(null, tool_type, location, 0.0)

# Function to reset output levels slider to default
func _on_sat_output_levels_reset_pressed(tool_type: String, location: String):
	outputlog("_on_sat_output_levels_reset_pressed",3)
	var ui_element = ui_config[tool_type][location]
	set_property_but_block_signals(ui_element["sat_output_levels_slider"].minSlider, "value", 0.0)
	set_property_but_block_signals(ui_element["sat_output_levels_slider"].maxSlider, "value", 1.0)
	_on_sat_levels_slider_value_changed(0.0, tool_type, location)
	create_update_custom_history(null, tool_type, location, 0.0)

# Function to reset all HSL adjustments to default
func _on_reset_all_hsl_pressed(tool_type: String, location: String):
	outputlog("_on_reset_all_hsl_pressed",3)
	var ui_element = ui_config[tool_type][location]
	
	# Reset all sliders
	ui_element["sat_midtones_slider"].slider_and_spinbox_change(0.5, true)
	ui_element["saturation_slider"].slider_and_spinbox_change(0.5, true)
	ui_element["hue_slider"].slider_and_spinbox_change(0.0, true)
	ui_element["lightness_slider"].slider_and_spinbox_change(0.0, true)
	ui_element["contrast_slider"].slider_and_spinbox_change(0.0, true)
	set_property_but_block_signals(ui_element["sat_levels_slider"].minSlider, "value", 0.0)
	set_property_but_block_signals(ui_element["sat_levels_slider"].maxSlider, "value", 1.0)
	set_property_but_block_signals(ui_element["sat_output_levels_slider"].minSlider, "value", 0.0)
	set_property_but_block_signals(ui_element["sat_output_levels_slider"].maxSlider, "value", 1.0)
	set_property_but_block_signals(ui_element["invert_button"], "pressed", false)
	
	# Update the stored ui config
	refresh_combined_ui_stored_state(tool_type, location)
	
	# Apply changes
	match location:
		"select":
			set_colour_of_selection(tool_type, false)
			create_update_custom_history(null, tool_type, location, 0.0)
		"main":
			set_preview_colour(tool_type, false)

# Function to reset opacity slider to default
func _on_opacity_reset_pressed(tool_type: String, location: String):
	outputlog("_on_opacity_reset_pressed",3)
	var ui_element = ui_config[tool_type][location]
	ui_element["opacity_slider"].slider_and_spinbox_change(1.0, false)
	_on_opacity_slider_ui_changed(null, tool_type, location)
	create_update_custom_history(null, tool_type, location, 0.0)

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
	
	# Reset all saturation/HSL mode sliders to default values
	ui_element["saturation_slider"].slider_and_spinbox_change(0.5, true)
	ui_element["hue_slider"].slider_and_spinbox_change(0.0, true)
	ui_element["lightness_slider"].slider_and_spinbox_change(0.0, true)
	ui_element["contrast_slider"].slider_and_spinbox_change(0.0, true)
	set_property_but_block_signals(ui_element["invert_button"], "pressed", false)
	set_property_but_block_signals(ui_element["sat_levels_slider"].minSlider, "value", 0.0)
	set_property_but_block_signals(ui_element["sat_levels_slider"].maxSlider, "value", 1.0)
	ui_element["sat_midtones_slider"].slider_and_spinbox_change(0.5, true)
	set_property_but_block_signals(ui_element["sat_output_levels_slider"].minSlider, "value", 0.0)
	set_property_but_block_signals(ui_element["sat_output_levels_slider"].maxSlider, "value", 1.0)
	
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
	ui_element["hue_slider"].hbox.visible = (source_shader_type == "saturation" && button_pressed)
	ui_element["lightness_slider"].hbox.visible = (source_shader_type == "saturation" && button_pressed)
	ui_element["contrast_slider"].hbox.visible = (source_shader_type == "saturation" && button_pressed)
	ui_element["invert_hbox"].visible = (source_shader_type == "saturation" && button_pressed)
	ui_element["sat_levels_hbox"].visible = (source_shader_type == "saturation" && button_pressed)
	ui_element["sat_midtones_slider"].hbox.visible = (source_shader_type == "saturation" && button_pressed)
	ui_element["sat_output_levels_hbox"].visible = (source_shader_type == "saturation" && button_pressed)

	# Show colorable protection checkboxes only when saturation mode is on AND a colorable asset is selected
	var show_colorable_protect = (source_shader_type == "saturation" && button_pressed)
	if show_colorable_protect and location == "select":
		show_colorable_protect = is_selection_colorable(tool_type)
	elif show_colorable_protect and location == "main":
		# In main mode, show if the current object in the library is colorable
		show_colorable_protect = _is_current_main_object_colorable(tool_type)
	ui_element["colorable_protect_hbox"].visible = show_colorable_protect

	if source_shader_type == "gradient" && button_pressed:
		ui_config["gradient_map"].show()
	else:
		ui_config["gradient_map"].hide()

	# Update the stored ui config
	refresh_combined_ui_stored_state(tool_type, location)

# Function to call when one of the colour options is selected
func _on_colour_option_button_pressed(button_pressed: bool, source_shader_type: String, tool_type: String, location: String, update_selection: bool):
	_begin_change("shader_mode_" + source_shader_type)

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
	ui_config[tool_type][location]["opacity_slider"].slider_and_spinbox_change(Color(colour_config["colour"]).a,true)
	
	# Call the function to act on the new change
	_on_tintcolour_changed(null, tool_type, location)

# Function called when the opacity slider changes
func _on_opacity_slider_ui_changed(_ignore_this, tool_type: String, location: String):
	_begin_change("opacity")

	# Update the tint colour only for tools with a palette
	if ui_config[tool_type][location]["palette"] != null:
		var color = ui_config[tool_type][location]["palette"].color
		color.a = ui_config[tool_type][location]["opacity_slider"].value
		ui_config[tool_type][location]["palette"].SetColor(color,false)

	# Update the stored ui config
	refresh_combined_ui_stored_state(tool_type, location)

	# Apply to selection if in select mode
	if location == "select":
		set_colour_of_selection(tool_type, false)
	
	# Update preview in main mode
	if location == "main":
		set_preview_colour(tool_type, false)

# Function called when a colour palette value is changed. Note this only has an immediate action if this is the select tool and something is selected.
func _on_tintcolour_changed(_ignore_this, tool_type: String, location: String):

	outputlog("_on_tintcolour_changed",2)
	_begin_change("tint_colour")

	# Update the stored ui config
	refresh_combined_ui_stored_state(tool_type, location)

	# Sync the palettes as we could have added a new colour to the presets
	_on_preset_changed_in_palette(0, null, tool_type, location)

	# Update the preview colour
	if location == "main":
		set_preview_colour(tool_type, false)

	# If this is an object tool type, the update the object library to the palette colour
	# Use call_deferred to ensure this runs AFTER DD's internal color processing
	if is_object_tool_type(tool_type):
		# Reset back to the custom colour
		call_deferred("set_object_library_grid_custom_colour_to_dd_palette_colour", tool_type, location)

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
			if node != null and is_instance_valid(node):
				# Call the set tint colour function. Noting this is structured this way as post v1.2.0.0 we will call this function directly
				set_tint_colour_on_new_node(node)

# Function called when a new node is added to the World
func set_tint_colour_on_new_node(node: Node2D):

	outputlog("set_tint_colour_on_new_node: " + str(node),2)

	if node == null or not is_instance_valid(node):
		outputlog("node is null or freed",2)
		return
	
	var node_id
	if node.has_meta("node_id"):
		node_id = node.get_meta("node_id")
		outputlog("node_id: " + str(node_id),2)
	else:
		return

	# Get the tool type from the active tool name
	var tool_type = global.Editor.ActiveToolName

	# Guard: tool_type must be in TYPE_LOOKUP (e.g. SelectTool is not)
	if not TYPE_LOOKUP.has(tool_type):
		return

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

	# If Color Variants toggle is active, save current offsets for the placed node and generate new ones for the next preview
	var _saved_variant_offsets = {}
	if tool_type in ["ObjectTool", "ScatterTool"]:
		if ui_element.has("natural_variants_button"):
			if ui_element["natural_variants_button"].pressed:
				# Save the current offsets (these will be applied to the node we're about to place)
				_saved_variant_offsets = _preview_variant_offsets.duplicate(true)
				# Flag that the next set_preview_colour should regenerate offsets
				_preview_asset_changed = true

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

	# Apply the saved variant offsets to the placed node (same offsets that were shown in preview)
	if not _saved_variant_offsets.empty():
		var placed_node_data = customdatamanager.get_data_or_default(node_id)
		placed_node_data["type"] = TYPE_LOOKUP[tool_type]
		# Temporarily swap in the saved offsets
		var _current_offsets = _preview_variant_offsets
		_preview_variant_offsets = _saved_variant_offsets
		placed_node_data = _apply_preview_variant_to_config(placed_node_data, tool_type)
		_preview_variant_offsets = _current_offsets
		set_tint_colour(node_id, TYPE_LOOKUP[tool_type], placed_node_data, false)
	
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
	_current_change_source = ""

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


	



	
