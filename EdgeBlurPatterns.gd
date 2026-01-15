#########################################################################################################
##
## EDGE BLUR PATTERNS MOD
##
#########################################################################################################

# Version 1.2.4
class_name EdgeBlurPatterns

var script_class = "tool"
var global

var ui_config = {}

const ENABLE_BLUR_DIRECTION = false
const TYPE_LOOKUP = {"ObjectTool": "objects","ScatterTool": "objects", "PathTool": "paths", "PatternShapeTool": "pattern_shapes", "WallTool": "walls", "PortalTool": "portals"}

const SLIDER_WAIT_TIME = 1.0

var customdatamanager
var combinedshader

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
			printraw("(%d) <EdgeBlurPatterns>: " % OS.get_ticks_msec())
			print(msg)
	else:
		pass

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
		set_property_but_block_signals(target, "value", value)
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

# Make a button and return it
func make_button(parent_node, icon_path: String, hint_tooltip: String, toggle_mode: bool) -> Button:

	var button = Button.new()
	button.toggle_mode = toggle_mode
	button.icon = load_image_texture(icon_path)
	button.hint_tooltip = hint_tooltip
	parent_node.add_child(button)
	return button

# Add two angles in radians constraining the result to -PI to PI
func add_angles(angle1: float, angle2: float) -> float:
	var sum = angle1 + angle2
	return fposmod(sum + PI, TAU) - PI  # Keeps result in (-PI, PI]

func draw_path(points: Array,texture_path: String,layer: int,width: float,fade: bool):
	var temp_array = []
	var pathway
	var texture = load_image_texture(texture_path)
	pathway = global.World.GetCurrentLevel().Pathways.CreatePath(texture,layer,1,fade,fade,false,false)
	pathway.SetEditPoints(points)
	pathway.SetWidthScale(width)
	pathway.Smoothness = 0.0
	pathway.SetBlockLight(false)
	pathway.Smooth()
	global.World.AssignNodeID(pathway)
	pathway.set_meta("preview",false)

# Function to return the colour string from the patternshape
func get_pattern_colour(patternshape):

	if patternshape != null:
		var definition = patternshape.Save(true)
		if definition != null:
			if definition.has("color"):
				return definition["color"]
	
	return null

#########################################################################################################
##
## READ & WRITE MODMAPDATA FUNCTIONS
##
#########################################################################################################


# Function to remove data related to this node
func erase_data(node_id: int):

	customdatamanager.erase_data(node_id)

# Function to get the node data
func get_data(node_id: int):

	return customdatamanager.get_data(node_id)

# Function to check whether there is node data
func has_data(node_id: int):

	return customdatamanager.get_data(node_id)

# Function to update the modmap data stored in the map file
func set_data(node_id: int, data: Dictionary):

	customdatamanager.set_data(node_id, data)


#########################################################################################################
##
## UI CREATION & DISCOVERY FUNCTIONS
##
#########################################################################################################

func make_edgeblur_ui(location: String):

	outputlog("make_overridecolour_ui: location: " + str(location))

	var vbox
	var find_text = ["COLOR"]
	var hint_tooltips = {
		"use_texture_button": "When enabled, convert draw pattern as a flat colourable texture rather than the source texture.",
		"reset_button": "Reset to non-coloured state."
	}
	var tool_panel
	var hbox = HBoxContainer.new()
	

	# Set up the tool panel and vbox values
	if location == "main":
		tool_panel = global.Editor.Toolset.GetToolPanel("PatternShapeTool")
		vbox = tool_panel.Align
	else:
		tool_panel = global.Editor.Toolset.GetToolPanel("SelectTool")
		vbox = tool_panel.patternShapeOptions
	
	# Create the ui_config dictionary records
	if not ui_config.has(location):
		ui_config[location] = {}

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

	# Make the tint option control buttons
	vbox.add_child(hbox)
	vbox.move_child(hbox,index)
	var label = make_label(hbox,"Override Color",0)
	label.size_flags_horizontal = 3
	ui_config[location]["tint_hbox"] = hbox

	ui_config[location]["use_texture_button"] = make_button(hbox, "icons/white-circle-icon.png", hint_tooltips["use_texture_button"], true)
	ui_config[location]["use_texture_button"].connect("toggled", self, "on_ui_button_changed",[location,"use_texture_button"])

	# Create colour option buttons	
	ui_config[location]["blur_slider"] = make_hslider(vbox, 1.0, 0.0, 5.0, 0.1)

	# Link to Function to update the UI store
	ui_config[location]["blur_slider"].connect("value_changed", self, "on_edge_blur_slider_value_changed",[location, "blur_range"])

	vbox.move_child(ui_config[location]["blur_slider"].get_parent(),index)
	ui_config[location]["blur_range_label"] = make_label(vbox,"Blur Range",index)
	
	ui_config[location]["smoothness_slider"] = make_hslider(vbox, 5.0, 0.0, 50.0, 0.5)
	# Link to Function to update the UI store and selected values
	ui_config[location]["smoothness_slider"].connect("value_changed", self, "on_edge_blur_slider_value_changed",[location,"smoothness"])

	vbox.move_child(ui_config[location]["smoothness_slider"].get_parent(),index)
	ui_config[location]["smoothness_label"] = make_label(vbox,"Smoothness",index)

	
	# Create Sun Direction slider and activation button
	ui_config[location]["sun_direction_slider"] = make_hslider(vbox, 0.0, -180.0, 180.0, 1.0)
	# Link to Function to update the UI store
	ui_config[location]["sun_direction_slider"].connect("value_changed", self, "on_edge_blur_slider_value_changed",[location,"sun_direction"])

	vbox.move_child(ui_config[location]["sun_direction_slider"].get_parent(),index)
	# Create a Sun Direction button
	ui_config[location]["sun_direction_button"] = CheckButton.new()
	ui_config[location]["sun_direction_button"].text = "Blur Direction"
	ui_config[location]["sun_direction_button"].connect("toggled",self,"_on_sun_direction_button_pressed",[location])
	ui_config[location]["sun_direction_button"].pressed = false

	vbox.add_child(ui_config[location]["sun_direction_button"])
	vbox.move_child(ui_config[location]["sun_direction_button"],index)

	# Check whether blur direction should be visible
	if not ENABLE_BLUR_DIRECTION:
		ui_config[location]["sun_direction_button"].visible = false
		ui_config[location]["sun_direction_slider"].get_parent().visible = false
	
	# Create a reverse blur alpha button
	ui_config[location]["reverse_alpha_button"] = CheckButton.new()
	ui_config[location]["reverse_alpha_button"].text = "Reverse Blur Alpha"
	ui_config[location]["reverse_alpha_button"].hint_tooltip = "Enable to have the pattern blur to transparent from the edges to the centre."
	ui_config[location]["reverse_alpha_button"].connect("toggled",self,"on_ui_button_changed",[location,"reverse_alpha"])
	ui_config[location]["reverse_alpha_button"].pressed = false
	vbox.add_child(ui_config[location]["reverse_alpha_button"])
	vbox.move_child(ui_config[location]["reverse_alpha_button"],index)

	# Create an activivate edge blur button
	ui_config[location]["is_blur_active_button"] = CheckButton.new()
	ui_config[location]["is_blur_active_button"].text = "Enable Edge Blur"
	ui_config[location]["is_blur_active_button"].connect("toggled",self,"_on_is_blur_active_button_pressed",[location])
	ui_config[location]["is_blur_active_button"].pressed = false
	
	vbox.add_child(ui_config[location]["is_blur_active_button"])
	vbox.move_child(ui_config[location]["is_blur_active_button"],index)

	# Hide the UI
	_on_is_blur_active_button_pressed(false,location)

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

#########################################################################################################
##
## APPLY EDGE BLUR FUNCTIONS
##
#########################################################################################################

# Function to create or set the pattern shape with a pattern not that the patternshape should hold its colour and polypoints so we don't need to pass those
func set_edge_blur_on_pattern(patternshape, edge_blur_config: Dictionary):

	outputlog("set_edge_blur_on_pattern(): " + str(patternshape.get_meta("node_id")),2)

	if get_node_type(patternshape) != "pattern_shapes":
		return
	
	outputlog("edge_blur_config: " + str(edge_blur_config),2)
	combinedshader.set_custom_attributes_on_node(patternshape, edge_blur_config)

	set_data(patternshape.get_meta("node_id"), edge_blur_config)

#########################################################################################################
##
## UI DRIVEN CHANGE FUNCTIONS
##
#########################################################################################################

# Function to capture ui changes in the ui store
func on_ui_button_changed(_ignore_this, location: String, source_type: String):

	outputlog("on_ui_button_changed",2)

	# Get the value from the ui
	var config = get_edge_blur_config_from_ui(location)
	# Remove the custom colour ot allow us to change this independently
	config.erase("colour")

	# Call the ui change function
	on_pattern_impacting_ui_change(location, source_type, config)

# Function to respond when an edge blur slider has changed. Noting all we are doing here is recording the new UI values to a central store.
func on_edge_blur_slider_value_changed(value: float, location: String, source_type: String):

	outputlog("on_edge_blur_slider_value_changed",2)

	# Get the value from the ui
	var config = get_edge_blur_config_from_ui(location)
	# Remove the custom colour ot allow us to change this independently
	config.erase("colour")

	# Call the ui change function
	on_pattern_impacting_ui_change(location, source_type, config)

# Function called when the official palette is directly changed. We want to turn off the edge blur at this point.
func _on_color_changed_in_official_palette(color: Color, location: String, source_type: String):

	outputlog("_on_color_changed_in_official_palette",2)

	# Call the ui change function
	on_pattern_impacting_ui_change(location, source_type, {})

# When a ui change occurs that would impact the ui store or a selected pattern
func on_pattern_impacting_ui_change(location: String, source_type: String, config: Dictionary):

	outputlog("on_pattern_impacting_ui_change",2)

	# Question: Do we need to reapply the shader here?
	set_combined_ui_stored_state("PatternShapeTool", location)

	# Update the selected patterns if this is in the select tool
	if location == "select":
		set_edge_blur_of_selection(source_type, config)

# Function to manage what to do when Sun Direction is pressed
func _on_sun_direction_button_pressed(button_pressed: bool, location: String):

	outputlog("_on_sun_direction_button_pressed",2)

	# Update the UI store
	set_combined_ui_stored_state("PatternShapeTool", location)

	# Set the visibility of the slider based on whether this is pressed or not
	if button_pressed:
		# Set the direction slider to visible
		ui_config[location]["sun_direction_slider"].get_parent().visible = true
	
	else:
		# Set the direction slider to hidden
		ui_config[location]["sun_direction_slider"].get_parent().visible = false

	# If we are in the select tool then we may need to update the pattern
	if location == "select":
		set_edge_blur_of_selection("sun_direction", {})
		# Record the event as a non-reset event
		combinedshader.create_update_custom_history(0.0)

# On show visibility of the edge blur feature
func _on_is_blur_active_button_pressed(button_pressed: bool, location: String):

	outputlog("_on_is_blur_active_button_pressed",2)

	# Update the UI store value
	set_combined_ui_stored_state("PatternShapeTool", location)

	if button_pressed:
		# Set the various edge blur UI elements to visible
		ui_config[location]["reverse_alpha_button"].visible = true
		ui_config[location]["blur_range_label"].visible = true
		ui_config[location]["blur_slider"].get_parent().visible = true
		ui_config[location]["smoothness_label"].visible = true
		ui_config[location]["smoothness_slider"].get_parent().visible = true
		if ENABLE_BLUR_DIRECTION:
			ui_config[location]["sun_direction_button"].visible = true
			if ui_config[location]["sun_direction_button"].pressed:
				ui_config[location]["sun_direction_slider"].get_parent().visible = true
			else:
				ui_config[location]["sun_direction_slider"].get_parent().visible = false
		ui_config[location]["tint_hbox"].visible = true
	
	else:
		# Set the various edge blur UI elements to hidden
		ui_config[location]["reverse_alpha_button"].visible = false
		ui_config[location]["blur_range_label"].visible = false
		ui_config[location]["blur_slider"].get_parent().visible = false
		ui_config[location]["smoothness_label"].visible = false
		ui_config[location]["smoothness_slider"].get_parent().visible = false
		ui_config[location]["sun_direction_button"].visible = false
		ui_config[location]["sun_direction_slider"].get_parent().visible = false
		ui_config[location]["tint_hbox"].visible = false

	var source_control = ui_config[location]["is_blur_active_button"]

	on_ui_button_changed(null, location, "has_edge_blur")
	combinedshader.create_update_custom_history(0.0)



#########################################################################################################
##
## SET UI TO SELECTED NODE VALUES FUNCTIONS
##
#########################################################################################################

# Function to set the colour ui to reflect the values of the passed node, noting that this should generally be a selected node
func set_edgeblur_ui_to_selected_node_values(node: Node2D, tool_type: String):

	var location = "select"

	outputlog("set_edgeblur_ui_to_selected_node_values: " + str(node),2)

	if node == null: return

	var node_id = node.get_meta("node_id")
	outputlog("node_id: " + str(node_id),2)
	var ui_element = ui_config[tool_type][location]

	# Check that this really is a pattern
	if get_node_type(node) != "pattern_shapes": return

	# If the first node is coloured then set the UI to match it but check whether it is already correct
	if customdatamanager.has_data(node_id):
		var data = customdatamanager.get_data(node_id)

		# If the UI is not the same as the current pattern then update it so that it does reflect the node's config
		var colour_config = customdatamanager.get_combined_ui_stored_state(tool_type, location)

		# If there is an edge_blur in the data which is possible to not have
		if data["has_edge_blur"]:
			# Update the UI elements without setting signals
			slider_and_spinbox_change(data["blur_range"], ui_config[location]["blur_slider"], true)
			slider_and_spinbox_change(data["smoothness"], ui_config[location]["smoothness_slider"], true)
			set_property_but_block_signals(ui_config[location]["use_texture_button"], "pressed", not data["use_texture"])
			set_property_but_block_signals(ui_config[location]["reverse_alpha_button"], "pressed", data["reverse_alpha"])

			# Set up the sun direction, check the format to avoid crashes
			if data["shadow_direction"] is Array:
				if Vector2(data["shadow_direction"][0],data["shadow_direction"][1]).length() > 0.0:
					set_property_but_block_signals(ui_config[location]["sun_direction_button"], "pressed", true)
					slider_and_spinbox_change(return_sun_direction_angle_from_array(data["shadow_direction"]), ui_config[location]["sun_direction_slider"], true)
				else:
					set_property_but_block_signals(ui_config[location]["sun_direction_button"], "pressed", false)
					ui_config[location]["sun_direction_slider"].get_parent().visible = false

		# Set the active button, noting we have to do this after setting the UI values. Note that it is possible for the data to be valid.
		set_property_but_block_signals(ui_config[location]["is_blur_active_button"], "pressed", data["has_edge_blur"])

	# If there is no data then we have selected a non-coloured asset and should update the palette items accordingly
	else:
		# Note there is no need to update the colour as DD takes care of this
		set_property_but_block_signals(ui_config[location]["is_blur_active_button"], "pressed", false)
	

	# Update the ui settings
	set_combined_ui_stored_state("PatternShapeTool", location)

# Function to look at the selected items in the select tool and change their colour if they are all of the correct type
func set_edgeblur_ui_to_selection():

	var location = "select"
	var tool_type = "PatternShapeTool"
	
	outputlog("set_edgeblur_ui_to_selection()",2)

	var selected = global.Editor.Tools["SelectTool"].Selected

	# If the Options vboxes are visible then only a single type is selected. This should always be the case when the function is called.
	# If we do not have only one type of asset chosen then return
	if find_select_vbox(tool_type) != null:
		# If the select options is not visible then we have multiple types and we should stop and return
		if not find_select_vbox(tool_type).visible:
			outputlog("Pattern select vbox not visible",2)
			if not check_all_nodes_of_same_type(selected):
				return
		# check that there are non-zero entries in the selected list
		if selected.size() > 0:
			if get_node_type(selected[0]) == "pattern_shapes":
				set_edgeblur_ui_to_selected_node_values(selected[0], tool_type)

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
## UPDATE SELECTED NODE VALUES FUNCTIONS
##
#########################################################################################################

# Update a placed node with new values for edgeblur
func update_placed_node_with_new_edgeblur_values(node, source_type: String, config: Dictionary):

	outputlog("update_placed_node_with_new_edgeblur_values",2)

	var node_id = node.get_meta("node_id")
	
	if not global.World.HasNodeID(node_id): return
	if get_node_type(node) != "pattern_shapes": return

	# If there is no data and the source type is rotation or colour change, then do no more
	if not has_data(node_id) && source_type in ["rotation_slider","custom_colour"]:
		return

	# Get a data record
	var data = customdatamanager.get_data_or_default(node_id)

	# Add or update the history data noting we can call this repeatedly and it will simply update the new state
	combinedshader.add_update_history_data(node_id, "PatternShapeTool", data)

	# Merge the new data into the data, noting we are forcing a change here
	data = customdatamanager.merge_dict(data, config)

	# Add or update the history data noting we can call this repeatedly and it will simply update the new state
	combinedshader.add_update_history_data(node_id, "PatternShapeTool", data)
			
	# Set the values into the edgeblur
	set_edge_blur_on_pattern(node, config)

# Function to update the edgeblur of a selection
func set_edge_blur_of_selection(source_type: String, config: Dictionary):

	var location = "select"

	outputlog("set_edge_blur_of_selection: source_type " + str(source_type),2)
	
	# For each selected node 
	for selected_node in global.Editor.Tools["SelectTool"].Selected:
		# Update some selected nodes with the edge blur values in the ui
		update_placed_node_with_new_edgeblur_values(selected_node, source_type, config)
		
# Function to return the sun direction array from a float between -180 and 180
func return_sun_direction_array(sun_direction: float):

	var vec2 = Vector2.RIGHT.rotated(sun_direction * TAU / 360)

	return [vec2.x,vec2.y]

# Function to return an angle given a shadow direction array
func return_sun_direction_angle_from_array(shadow_direction_array: Array):

	var angle

	angle = Vector2(shadow_direction_array[0],shadow_direction_array[1]).angle_to(Vector2.RIGHT) * 360 / TAU

	if angle < -180:
		angle += 360
	if angle > 180:
		angle -= 360

	return angle

# Function to update the current pattern, note this does not update the blur range or smoothness. This is only called from the main tool
func update_current_shadow_pattern_points():

	outputlog("update_current_shadow_pattern_points",2)
	var location = "main"
	var shadow_direction

	var patternshape = find_activepattern_from_vertices()

	# If the patternshape is valid then create or set a shadow pattern
	if patternshape != null:
		# If the pattern has edgeblur then update it
		if has_data(patternshape.get_meta("node_id")):
			var config = customdatamanager.get_combined_ui_stored_state("PatternShapeTool", location)
			set_edge_blur_on_pattern(patternshape, config)

# Function to set the edge blur on a node just placed
func create_set_edge_blur_on_new_node(node_id):

	outputlog("create_set_edge_blur_on_new_node",2)

	var location = "main"

	# Check the node exists
	if global.World.HasNodeID(node_id):
		# Check that the node is in fact a pattern by checking the existence of the HasOutline property
		if global.World.GetNodeByID(node_id).get("HasOutline") != null:
			var config = customdatamanager.get_combined_ui_stored_state("PatternShapeTool", location)
			set_edge_blur_on_pattern(global.World.GetNodeByID(node_id), config)

# Function to get the combined config from the ui, by retrieving the current colour config and adding it to the stored values
func set_combined_ui_stored_state(tool_type: String, location: String):

	outputlog("set_combined_ui_stored_state: tool_type: " + str(tool_type) + " location: " + str(location),2)
	# Set a default value in case the ui_config check fails
	var config

	# If we have created a ui_config yet 
	config = get_edge_blur_config_from_ui(location)
	
	# Set the type based on the tool_type
	config["type"] = TYPE_LOOKUP[tool_type]
	customdatamanager.set_combined_ui_stored_state(config, tool_type, location)


# Function to return a dictionary of edge blur config from the UI
func get_edge_blur_config_from_ui(location: String):

	outputlog("get_edge_blur_config_from_ui: " + str(location),2)

	var edge_blur_config = {"has_edge_blur": false, "type": "pattern_shapes"}

	# If we have made a the ui then
	if ui_config.has(location):
		# Critically set the edge blur to has_edge_blur if true
		if ui_config[location]["is_blur_active_button"].pressed:

			# Set all the various values
			edge_blur_config["colour"] = ui_config["PatternShapeTool"][location]["custom_color_button"].color.to_html()
			edge_blur_config["blur_range"] = ui_config[location]["blur_slider"].value
			edge_blur_config["smoothness"] = ui_config[location]["smoothness_slider"].value
			edge_blur_config["use_texture"] = not ui_config[location]["use_texture_button"].pressed
			edge_blur_config["has_edge_blur"] = true
			edge_blur_config["reverse_alpha"] = ui_config[location]["reverse_alpha_button"].pressed

			# Calculate the sun direction value
			if ui_config[location]["sun_direction_button"].pressed:
				edge_blur_config["shadow_direction"] = return_sun_direction_array(ui_config[location]["sun_direction_slider"].value)
			else:
				edge_blur_config["shadow_direction"] = [0,0]

	return edge_blur_config


#########################################################################################################
##
## HISTORY RECORD FUNCTIONS FOR UNDO & REDO
##
#########################################################################################################

# Function to capture time outs from slider changes. Note this method is not used in edge blur patterns
func emit_history_event_signal():

	combinedshader.create_update_custom_history(0.0)

#########################################################################################################
##
## START FUNCTION
##
#########################################################################################################

func _init():
	pass

# Main Script
func initialise() -> void:

	outputlog("EdgeBlurPatterns Mod Has been loaded.")
	ui_config = {}

	# Find the custom color buttons for the Patternshape tool
	for location in ["main","select"]:
		find_custom_color_palette("PatternShapeTool", location, "custom_color_button")
	
	# Make the UI for each tool and location
	make_edgeblur_ui("main")
	make_edgeblur_ui("select")


