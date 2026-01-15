#########################################################################################################
##
## MODIFY PATH MOD
##
#########################################################################################################
# Version 1.0.5
class_name ModifyPaths

# Dungeondraft mod to add small additional functions to the UI
var script_class = "tool"
var global
var NewHSlider

# Variables
var ui_config = {}

const DEFAULT_HISTORY_RECORD = {"has_data": false, "previous_node_data": {}, "new_node_data": {}}
var history_record = DEFAULT_HISTORY_RECORD.duplicate(true)

const SLIDER_WAIT_TIME = 0.5
var start_point_shader = null
const START_POINT_MODMAPDATA = "PathOffset"

var reference_to_script = null

var customdatamanager
var combinedshader

const PATH_SLIDER_CONFIG = {
	"width": {
		"default": 1.0,
		"min": 0.1,
		"max": 5.0,
		"step": 0.05
	},
	"smoothness": {
		"default": 1.0,
		"min": 0.0,
		"max": 1.0,
		"step": 0.1

	}
}

const END_TYPE_CONFIG = {
	"end_in": {
		"label": "Transition In",
		"fade": "FadeIn",
		"grow_shrink": "Grow"
	},
	"end_out": {
		"label": "Transition Out",
		"fade": "FadeOut",
		"grow_shrink": "Shrink"
	}
}

enum PathChangeType {
	WIDTH_SLIDER,
	SMOOTHNESS_SLIDER,
	END_TYPE,
	FLIP,
	START_POINT_SLIDER,
	START_POINT_BUTTON,
	FADE_DISTANCE_SLIDER
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
			printraw("(%d) <ModifyPaths>: " % OS.get_ticks_msec())
			print(msg)
	else:
		pass

#########################################################################################################
##
## UTILITY FUNCTIONS
##
#########################################################################################################

# Function to set a property on an object but block any signals for it
func set_property_but_block_signals(obj: Object, property: String, value):

	outputlog("set_property_but_block_signals: " + str(obj) + " property: " + str(property) + " value: " + str(value),3)

	obj.set_block_signals(true)
	if obj.get(property) != null:
		obj.set(property,value)
	obj.set_block_signals(false)

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

# Make a button and return it
func make_button(parent_node, icon_path: String, hint_tooltip: String, toggle_mode: bool) -> Button:

	var button = Button.new()
	button.toggle_mode = toggle_mode
	button.icon = load_image_texture(icon_path)
	button.hint_tooltip = hint_tooltip
	parent_node.add_child(button)
	return button


# Function to get the path vbox depending on the location
func get_path_vbox(location: String):
	# Find the vbox based on the location
	match location:
		"select":
			return global.Editor.Toolset.GetToolPanel("SelectTool").pathOptions
		"main":
			return global.Editor.Toolset.GetToolPanel("PathTool").Align
		_:
			return null

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
## HISTORY RECORD FUNCTIONS FOR UNDO & REDO
##
#########################################################################################################

# Make a history record for the current path state
func make_path_history_record(path):

	var node_id = path.get_meta("node_id")
	var history_record = {
		"node_id": node_id,
		"widthscale": find_path_width_scale(path),
		"smoothness": path.Smoothness,
		"FadeIn": path.FadeIn,
		"FadeOut": path.FadeOut,
		"Grow": path.Grow,
		"Shrink": path.Shrink
	}
	# Note that in order for the history function to recognise that a change has occurred, we need to record the flip and start_point values
	if has_data(node_id):
		var data = get_data(node_id)
		if data.has("path_flip_vertical"):
			history_record["path_flip_vertical"] = data["path_flip_vertical"]
		else:
			history_record["path_flip_vertical"] = false
		history_record["start_point"] = data["start_point"]
	else:
		history_record["start_point"] = 0.0
		history_record["path_flip_vertical"] = false
	
	return history_record

# Function to take a node id and store their current status so that we can create a before and after data record
func add_update_history_data(node_id: int, config: Dictionary):

	outputlog("add_update_history_data",2)
	outputlog("config: " + str(config),2)

	history_record["has_data"] = true

	# Add the node id reference to the history record
	var node_id_string = "node-id-" + str(node_id)
	# If there is no existing record for that node, then create a record, ie do not update if there is an existing record
	if not history_record["previous_node_data"].has(node_id_string):
		history_record["previous_node_data"][node_id_string] = config.duplicate(true)

	# Make the new node data record
	history_record["new_node_data"][node_id_string] = config.duplicate(true)

# Function to reset the history data back to default values
func clear_history_data():

	history_record = DEFAULT_HISTORY_RECORD.duplicate(true)

# Create custom history record, called when a colour preset is selected, the color picker is closed, or a slider timer finishes
func create_update_custom_history():

	var record_script
	outputlog("create_update_custom_history",2)

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
	record_script = reference_to_script.InstanceReference("library/custom_history_record_path_change.gd")

	# If this is null for any reason then return to avoid a crash
	if record_script == null:
		outputlog("record_script is null",2)
		# As the data is invalid, clear the data
		clear_history_data()
		return

	record_script.combinedshader = combinedshader
	record_script.customdatamanager = customdatamanager
	record_script.previous_node_data = history_record["previous_node_data"].duplicate(true)
	record_script.new_node_data = history_record["new_node_data"].duplicate(true)

	outputlog("previous_node_data\n" + JSON.print(record_script.previous_node_data,"\t"),2)
	outputlog("new_node_data\n" + JSON.print(record_script.new_node_data,"\t"),2)

	# If this is a new action then create a new custom record
	var record = global.Editor.History.CreateCustomRecord(record_script)

	# Reset the history record
	clear_history_data()	


# Function called when a slider times out
func emit_history_event_signal():

	outputlog("emit_history_event_signal",2)

	combinedshader.create_update_custom_history()

#########################################################################################################
##
## CHANGE PATH OPTIONS IN SELECT TOOL FUNCTIONS
##
#########################################################################################################

	
# Function to make the width slider UI for paths
func make_modify_path_ui():

	outputlog("make_modify_path_ui",0)

	var path_vbox = get_path_vbox("select")

	if not ui_config.has("path_changer"):
		ui_config["path_changer"] = {}
	
	# Make the sliders
	for type in ["width","smoothness"]:
		ui_config["path_changer"][type] = {}
		# Make width label
		ui_config["path_changer"][type]["label"] = Label.new()
		ui_config["path_changer"][type]["label"].text = str(type).capitalize()
		path_vbox.add_child(ui_config["path_changer"][type]["label"])

		# Make the slider
		ui_config["path_changer"][type]["slider"] = NewHSlider.new(path_vbox, PATH_SLIDER_CONFIG[type]["default"], PATH_SLIDER_CONFIG[type]["min"], PATH_SLIDER_CONFIG[type]["max"], PATH_SLIDER_CONFIG[type]["step"])

		# Connect to value change
		ui_config["path_changer"][type]["slider"].connect("value_changed", self, "on_path_slider_change",["select",type])
		ui_config["path_changer"][type]["slider"].connect("emit_history_event_signal", self, "emit_history_event_signal")


	# Make the end type modification buttons
	for end_type in ["end_in","end_out"]:
		ui_config["path_changer"][end_type] = {}
		# Make Dropdown for Transition in
		ui_config["path_changer"][end_type]["hbox"] = HBoxContainer.new()
		ui_config["path_changer"][end_type]["label"] = Label.new()
		ui_config["path_changer"][end_type]["label"].text = END_TYPE_CONFIG[end_type]["label"]
		ui_config["path_changer"][end_type]["hbox"].add_child(ui_config["path_changer"][end_type]["label"])
		outputlog("added label")
		ui_config["path_changer"][end_type]["button"] = OptionButton.new()
		ui_config["path_changer"][end_type]["button"].size_flags_horizontal = 3
		ui_config["path_changer"][end_type]["button"].add_item("None")
		ui_config["path_changer"][end_type]["button"].add_item(END_TYPE_CONFIG[end_type]["fade"])
		ui_config["path_changer"][end_type]["button"].add_item(END_TYPE_CONFIG[end_type]["grow_shrink"])
		ui_config["path_changer"][end_type]["button"].connect("item_selected", self, "_on_path_options_changed", ["select"])
		ui_config["path_changer"][end_type]["hbox"].add_child(ui_config["path_changer"][end_type]["button"])
		path_vbox.add_child(ui_config["path_changer"][end_type]["hbox"])

	ui_config["path_changer"]["select_tool_path_vbox"] = path_vbox

# Function to capture actions on slider change. All this does is start or extend the slide change timer
func on_path_slider_change(value, location: String, slider_type: String):

	outputlog("on_path_slider_change",2)

	var lookup = {
		"width": PathChangeType.WIDTH_SLIDER,
		"smoothness": PathChangeType.SMOOTHNESS_SLIDER
	}

	# Update the combined ui stored state. Noting this achieves little in this context, as none of those values have changed.
	update_combined_ui_stored_state(location)

	if location == "select":
		# Update any selected paths with the new values
		update_selected_paths_with_new_values(lookup[slider_type])

# Find the width scale of a path
func find_path_width_scale(path) -> float:

	var path_dictionary: Dictionary
	var path_texture
	var texture_height

	if not global.World.HasNodeID(path.get_meta("node_id")):
		return -1.0

	# Get the path metadata - surely there is a better way to do this
	path_dictionary = path.Save(true)
	path_texture = ResourceLoader.load(path_dictionary["texture"])
	texture_height = path_texture.get_height()

	return path_dictionary["width"] / texture_height

# Set transition options UI based on the path properties
func set_ends_option_buttons_in_ui(path):

	if path.FadeIn == false && path.Grow == false:
		ui_config["path_changer"]["end_in"]["button"].selected = 0
	if path.FadeIn:
		ui_config["path_changer"]["end_in"]["button"].selected = 1
	if path.Grow:
		ui_config["path_changer"]["end_in"]["button"].selected = 2
	
	if path.FadeOut == false && path.Shrink == false:
		ui_config["path_changer"]["end_out"]["button"].selected = 0
	if path.FadeOut:
		ui_config["path_changer"]["end_out"]["button"].selected = 1
	if path.Shrink:
		ui_config["path_changer"]["end_out"]["button"].selected = 2

# Function to manage what to do if the path options have been changed in the select tool or the slider timer has timed out
func _on_path_options_changed(index: int, location: String):

	outputlog("_on_path_options_changed",2)

	# Update the combined ui stored state. Noting this achieves little in this context, as none of those values have changed.
	update_combined_ui_stored_state(location)

	# If a fade option has been set, then made the fade distance slider visible
	show_hide_fade_distance_slider(location)

	if location == "select":
		# Update any selected paths with the new values
		update_selected_paths_with_new_values(PathChangeType.END_TYPE)

# function to set the end types in the path to those in the select tool ui
func set_path_end_types_to_values_in_selecttool_ui(path):

	outputlog("set_path_end_types_to_values_in_selecttool_ui",2)

	var indexes = get_path_end_type_indexes_from_select_ui()

	for end_type in ["end_in","end_out"]:
		set_path_end_types(path, indexes[end_type], END_TYPE_CONFIG[end_type])
	
	# If we have se the grow and shrink to false then refresh the points
	if not path.Grow && not path.Shrink:
		# Trigger the GrowShrink algorithm to refresh based on the current values
		path.GrowShrinkEnds(max(int(path.GlobalEditPoints.size() * 0.5),1))
		
# Function to return and index and end_type_data record from the select ui
func get_path_end_type_indexes_from_select_ui():

	return {
		"end_in": ui_config["path_changer"]["end_in"]["button"].selected,
		"end_out": ui_config["path_changer"]["end_out"]["button"].selected
	}

# set the path end types
func set_path_end_types(path, index: int, end_type_data: Dictionary):

	outputlog("set_path_end_types: index: " + str(index) + " end_type_data: " + str(end_type_data),2)

	for property in [end_type_data["fade"],end_type_data["grow_shrink"]]:
		path.set(property,false)

	match index:
		1:
			path.set(end_type_data["fade"],true)
		2:
			path.set(end_type_data["grow_shrink"],true)


#########################################################################################################
##
## FADE DISTANCE CHANGE FUNCTIONS
##
#########################################################################################################

# Make the fade distance ui
func make_fade_distance_ui():

	outputlog("make_fade_distance_ui")

	if not ui_config.has("fade_distance"):
		ui_config["fade_distance"] = {}

	for location in ["select","main"]:
		make_fade_distance_ui_in_location(location)

# make the fade distance ui in location
func make_fade_distance_ui_in_location(location: String):

	outputlog("make_fade_distance_ui_in_location: " + str(location))

	ui_config["fade_distance"][location] = {}

	var vbox = get_path_vbox(location)
	
	var label = Label.new()
	label.text = "Fade Dist"

	# Make the core slider
	ui_config["fade_distance"][location]["slider"] = NewHSlider.new(vbox, 10, 1, 49, 1)
	ui_config["fade_distance"][location]["slider"].connect("value_changed", self, "on_fade_distance_slider_changed", [location])
	ui_config["fade_distance"][location]["slider"].connect("emit_history_event_signal", self, "emit_history_event_signal")
	ui_config["fade_distance"][location]["slider"].hbox.add_child(label)
	ui_config["fade_distance"][location]["slider"].hbox.move_child(label,0)
	ui_config["fade_distance"][location]["slider"].hbox.visible = false
	ui_config["fade_distance"][location]["slider"].spinbox.suffix = "%"

# Function to show or hide the fade slider based on location
func show_hide_fade_distance_slider(location: String):

	if location == "select" && (ui_config["path_changer"]["end_in"]["button"].selected == 1 || ui_config["path_changer"]["end_out"]["button"].selected == 1) || location == "main" && (global.Editor.Tools["PathTool"].Controls["TransitionIn"].selected == 1 || global.Editor.Tools["PathTool"].Controls["TransitionOut"].selected == 1):
		ui_config["fade_distance"][location]["slider"].hbox.visible = true
	else:
		ui_config["fade_distance"][location]["slider"].hbox.visible = false

# On fade distance updated
func on_fade_distance_slider_changed(value: float, location: String):

	# Update the combined ui stored state. Noting this achieves little in this context, as none of those values have changed.
	update_combined_ui_stored_state(location)

	if location == "select":
		# Update any selected paths with the new values
		update_selected_paths_with_new_values(PathChangeType.FADE_DISTANCE_SLIDER)

#########################################################################################################
##
## FLIP PATH TEXTURE VERTICALLY FUNCTIONS
##
#########################################################################################################

# Make the ui button to flip the texture vertically
func make_flip_path_texture_vertically_ui():

	if not ui_config.has("flip_vertical"):
		ui_config["flip_vertical"] = {}

	for location in ["select","main"]:
		make_flip_path_texture_vertically_ui_in_location(location)

# Function to make the ui for the start point of a path
func make_flip_path_texture_vertically_ui_in_location(location):

	outputlog("make_flip_path_texture_vertically_ui_in_location",2)

	var vbox = get_path_vbox(location)
	
	if not ui_config["flip_vertical"].has(location):
		ui_config["flip_vertical"][location] = {}

	# Make the randomise button
	var button = Button.new()
	button.text = "Flip Texture Vertically"
	button.hint_tooltip = "Press to flip the texture of the path vertically."

	# Set the toggle mode if in main or link to the pressed signal if in select mode
	button.toggle_mode = true
	button.connect("toggled", self, "on_flip_vertical_button_toggled",[location])

	ui_config["flip_vertical"][location]["button"] = button
	vbox.add_child(ui_config["flip_vertical"][location]["button"])

# Function to respond to a flip horizontal press
func on_flip_vertical_button_toggled(button_pressed: bool, location: String):

	outputlog("on_flip_vertical_button_toggled: " + str(button_pressed),2)

	# Update the ui store
	update_combined_ui_stored_state(location)

	if location == "select":
		# Update selected paths
		update_selected_paths_with_new_values(PathChangeType.FLIP)

#########################################################################################################
##
## GENERAL PATH CHANGE FUNCTIONS
##
#########################################################################################################


# Set the combined ui store from current values in the ui
func update_combined_ui_stored_state(location: String):

	outputlog("update_combined_ui_stored_state",2)

	var config = get_path_config_from_ui(location)
	customdatamanager.set_combined_ui_stored_state(config, "PathTool", location)

# Function to get the path config values from the ui
func get_path_config_from_ui(location: String):

	outputlog("get_path_config_from_ui: " + str(location),2)

	return {
		"start_point": ui_config["path_start_point"][location]["slider"].value,
		"path_flip_vertical": ui_config["flip_vertical"][location]["button"].pressed,
		"fade_distance": ui_config["fade_distance"][location]["slider"].value,
		"type": "paths"
	}


#########################################################################################################
##
## UPDATE SELECTED NODE VALUES FUNCTIONS
##
#########################################################################################################

# Update this placed path with new values
func update_placed_paths_with_new_values(path: Node2D, change_type: int, location: String):

	outputlog("update_placed_paths_with_new_values",2)

	if get_node_type(path) != "paths": return
	if not global.World.HasNodeID(path.get_meta("node_id")): return

	var config = customdatamanager.get_data_or_default(path.get_meta("node_id"))

	combinedshader.add_update_history_data(path.get_meta("node_id"), "PathTool", {})

	# configure which type of change it is. Note we could probably just change everything.
	match change_type:
		PathChangeType.END_TYPE:
			set_path_end_types_to_values_in_selecttool_ui(path)
		PathChangeType.WIDTH_SLIDER:
			# Set the standard DD path attributes
			path.SetWidthScale(ui_config["path_changer"]["width"]["slider"].value)
		PathChangeType.SMOOTHNESS_SLIDER:
			path.Smoothness = ui_config["path_changer"]["smoothness"]["slider"].value
		PathChangeType.START_POINT_BUTTON:
			# Set the start point to a random number between 0 and 1
			config["start_point"] = randf()
			# Update the UI to reflect this
			customdatamanager.set_combined_ui_stored_state(config, "PathTool", location)
		PathChangeType.START_POINT_SLIDER:
			# Set the start point the value of the start point slider
			config["start_point"] = ui_config["path_start_point"][location]["slider"].value
			# Update the UI to reflect this
			customdatamanager.set_combined_ui_stored_state(config, "PathTool", location)
		PathChangeType.FLIP:
			config["path_flip_vertical"] = ui_config["flip_vertical"][location]["button"].pressed
		PathChangeType.FADE_DISTANCE_SLIDER:
			config["fade_distance"] = ui_config["fade_distance"][location]["slider"].value
			# Update the UI to reflect this
			customdatamanager.set_combined_ui_stored_state(config, "PathTool", location)

		
	# If the universal shader is active or if this is a new flip action or a start point change, we then need to run the shader again to propagate any changes
	if not customdatamanager.is_data_default(config) || not change_type in [PathChangeType.END_TYPE,PathChangeType.WIDTH_SLIDER,PathChangeType.SMOOTHNESS_SLIDER]:
		combinedshader.set_custom_attributes_on_node(path, config)
		set_data(path.get_meta("node_id"), config)
	
	outputlog("path: Grow: " + str(path.Grow) + " Shrink: " + str(path.Shrink))
	# Just to be sure, we call these functions
	path.UpdateGradient()
	path.Smooth()

	# Record the new changed state for the history
	combinedshader.add_update_history_data(path.get_meta("node_id"), "PathTool", {})

# Function to update selected paths with new values
func update_selected_paths_with_new_values(change_type):

	outputlog("update_selected_paths_with_new_values: " + str(change_type),2)

	var location = "select"

	# Check that pathoptions are visible which it should be as you can't call the function any other way
	if global.Editor.ActiveToolName != "SelectTool" || not global.Editor.Toolset.GetToolPanel("SelectTool").pathOptions.visible:
		return

	# For each path in the selected list
	for path in global.Editor.Tools["SelectTool"].Selected:
		# Record the current state, noting this is only required at this point in the code, to ensure the initial state is recorded
		update_placed_paths_with_new_values(path, change_type, location)

	# Make a history record for this if this is a button driven change. Noting that a slider timeout will deal with slider records
	if not change_type in [PathChangeType.WIDTH_SLIDER, PathChangeType.SMOOTHNESS_SLIDER, PathChangeType.START_POINT_SLIDER, PathChangeType.FADE_DISTANCE_SLIDER]:
		outputlog("create immediately",2)
		# Create an actual history record
		combinedshader.create_update_custom_history()
	# Otherwise kick off a timer on the right slider
	else:
		start_timer_by_change_type(change_type)
		
# Start the time based on change_type
func start_timer_by_change_type(change_type: int):

	var newhslider = null

	match change_type:
		PathChangeType.WIDTH_SLIDER:
			newhslider = ui_config["path_changer"]["width"]["slider"]
		PathChangeType.SMOOTHNESS_SLIDER:
			newhslider = ui_config["path_changer"]["smoothness"]["slider"]
		PathChangeType.START_POINT_SLIDER:
			newhslider = ui_config["path_start_point"]["select"]["slider"]
		PathChangeType.FADE_DISTANCE_SLIDER:
			newhslider = ui_config["fade_distance"]["select"]["slider"]
	
	newhslider.start_slider_timer()



#########################################################################################################
##
## SET UI TO SELECTED NODE VALUES FUNCTIONS
##
#########################################################################################################

# Function to set the path ui to the selection, noting we always suppress signals
func set_path_ui_to_selection():

	# If there are any selected paths
	if global.Editor.Tools["SelectTool"].Selected.size() > 0:
		# Take the first one
		var path = global.Editor.Tools["SelectTool"].Selected[0]
		# Check it really is a path
		if get_node_type(path) == "paths":
			# Set all the various values into the ui
			set_start_point_path_ui_to_selected_path(path)
			set_flip_vertical_ui_to_selected_path(path)
			ui_config["path_changer"]["width"]["slider"].slider_and_spinbox_change(find_path_width_scale(path), true)
			ui_config["path_changer"]["smoothness"]["slider"].slider_and_spinbox_change(path.Smoothness, true)
			set_ends_option_buttons_in_ui(path)
			update_combined_ui_stored_state("select")
	
	show_hide_fade_distance_slider("select")

# Function to set the start point ui to selection
func set_start_point_path_ui_to_selected_path(path):

	outputlog("set_start_point_path_ui_to_selected_path",2)
	var value = 0.0

	var node_id = path.get_meta("node_id")
	if has_data(node_id):
		var data = get_data(node_id)
		value = data["start_point"]
		
	ui_config["path_start_point"]["select"]["slider"].slider_and_spinbox_change(value, true)

# Function to set the start point ui to selection
func set_flip_vertical_ui_to_selected_path(path):

	outputlog("set_flip_vertical_ui_to_selected_path",2)
	var pressed = false

	var node_id = path.get_meta("node_id")
	if has_data(node_id):
		var data = get_data(node_id)
		pressed = data["path_flip_vertical"]
	set_property_but_block_signals(ui_config["flip_vertical"]["select"]["button"],"pressed",pressed)

#########################################################################################################
##
## CUSTOM START POINT PATH FUNCTIONS
##
#########################################################################################################

# Function to create the ui for setting the path start point
func make_start_point_path_ui():

	var vbox
	var hbox
	var button

	if not ui_config.has("path_start_point"):
		ui_config["path_start_point"] = {}

	for location in ["select","main"]:
		make_start_point_path_ui_in_location(location)

# Function to make the ui for the start point of a path
func make_start_point_path_ui_in_location(location):

	outputlog("make_start_point_path_ui_in_location",1)

	ui_config["path_start_point"][location] = {}

	var vbox = get_path_vbox(location)
	
	var hbox = HBoxContainer.new()
	var label = Label.new()
	label.text = "Offset"
	hbox.add_child(label)

	# Make the core slider
	ui_config["path_start_point"][location]["slider"] = NewHSlider.new(hbox, 0.0, 0.0, 1.0, 0.001)
	ui_config["path_start_point"][location]["slider"].connect("value_changed", self, "on_start_point_slider_changed", [location])
	ui_config["path_start_point"][location]["slider"].connect("emit_history_event_signal", self, "emit_history_event_signal")
	vbox.add_child(hbox)

	# Make the randomise button
	var button = Button.new()
	button.icon = load_image_texture("icons/dice-icon.png")
	button.hint_tooltip = "Press to randomise the start point of a path."

	# Set the toggle mode if in main or link to the pressed signal if in select mode
	if location == "main":
		button.toggle_mode = true
	else:
		button.connect("pressed", self, "on_random_start_point_for_path_button_pressed",["select"])

	ui_config["path_start_point"][location]["random_button"] = button
	hbox.add_child(ui_config["path_start_point"][location]["random_button"])

# When the start point slider is changed
func on_start_point_slider_changed(value: float, location: String):

	# Update the UI store
	update_combined_ui_stored_state(location)

	# If in the select tool
	if location == "select":
		update_selected_paths_with_new_values(PathChangeType.START_POINT_SLIDER)
	# If in the main tool
	else:
		# Set the random button toggle to false as we have set the value manually
		ui_config["path_start_point"][location]["random_button"].pressed = false

# Function to set the active path custom values
func set_active_path_custom_values():

	outputlog("set_active_path_custom_values",2)

	var active_path = global.Editor.Tools["PathTool"].ActivePath

	if active_path == null:
		outputlog("active_path is null",2)
		return
	
	# If this is a random start point activated and the active path doesn't already have a start_point
	if ui_config["path_start_point"]["main"]["random_button"].pressed:

		set_random_start_point_in_ui()
	
	# Get the config from the ui
	var config = customdatamanager.get_combined_ui_stored_state("PathTool","main")

	# Apply it to the active path
	combinedshader.set_custom_attributes_on_node(active_path, config)
	
# Update the main ui with a random start point
func set_random_start_point_in_ui():

	outputlog("set_random_start_point_in_ui",2)

	var config = customdatamanager.get_combined_ui_stored_state("PathTool","main")
	config["start_point"] = randf()
	ui_config["path_start_point"]["main"]["slider"].slider_and_spinbox_change(config["start_point"], true)
	customdatamanager.set_combined_ui_stored_state(config, "PathTool","main")

# Function to implement a random start point for a selected path or paths
func on_random_start_point_for_path_button_pressed(location: String):

	outputlog("on_random_start_point_for_path_button_pressed",2)

	if location == "select":
		# Update the ui state
		update_combined_ui_stored_state("select")

		# Update the selected paths to new values
		update_selected_paths_with_new_values(PathChangeType.START_POINT_BUTTON)
	
		# Update the ui to reflect the first path selected
		if global.Editor.Tools["SelectTool"].Selected.size() > 0:
			set_start_point_path_ui_to_selected_path(global.Editor.Tools["SelectTool"].Selected[0])

#########################################################################################################
##
## DATA FUNCTIONS
##
#########################################################################################################

# Function to respond to a data driven change from the customdatamanager to set the path values
func set_path_with_custom_attributes(node, config: Dictionary):

	if not customdatamanager.is_data_default(config):
		if get_node_type(node) == "paths":
			combinedshader.set_custom_attributes_on_node(node, config)

# Function to get the node data
func get_data(node_id: int):

	return customdatamanager.get_data(node_id)

# Function to check whether there is node data
func has_data(node_id: int):

	return customdatamanager.has_data(node_id)

# Function to update the modmap data stored in the map file
func set_data(node_id: int, data: Dictionary):

	customdatamanager.set_data(node_id, data)

#########################################################################################################
##
## START FUNCTION
##
#########################################################################################################

func _init():

	pass

# Register the signals from the main end type option buttons
func register_signals_from_end_type():

	for transitiontype in ["TransitionIn","TransitionOut"]:
		global.Editor.Tools["PathTool"].Controls[transitiontype].connect("item_selected", self, "_on_path_options_changed",["main"])


# Main Script
func initialise() -> void:

	outputlog("Modify Path Mod Has been loaded.")

	randomize()
	NewHSlider = ResourceLoader.load(global.Root + "NewHSlider.gd", "GDScript", true)

	make_modify_path_ui()

	make_start_point_path_ui()

	make_fade_distance_ui()

	make_flip_path_texture_vertically_ui()

	register_signals_from_end_type()
	
