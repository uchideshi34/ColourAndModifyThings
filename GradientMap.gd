class_name GradientMap

var colour_points_vbox = null
var colour_points_scroll = null
var colour_points_list = []
var tool_panel = null
var gradient: Gradient
var gradient_texture: GradientTexture
var gradient_display = null
var display_details_button = null
var gradient_texrect = null
var tool_type: String
var location: String
var levels_slider = null
var levels_hbox = null

var PresetsDropdown
var presetsdropdown

const SHOW_MOVE_BUTTONS = false
const SLIDER_WAIT_TIME = 1.0
const LEVELS_SLIDER_STEP = 0.001
const MIN_X_SIZE_FOR_DETAILS = 150

var global = null

# Logging Functions
const ENABLE_LOGGING = true
var logging_level = 0
var gradientpresets_log_level = 0

#########################################################################################################
##
## UTILITY FUNCTIONS
##
#########################################################################################################

func outputlog(msg,level=0):
	if ENABLE_LOGGING:
		if level <= logging_level:
			printraw("(%d) <GradientMap>: " % OS.get_ticks_msec())
			print(msg)
	else:
		pass

# Signal emitted when any parameter of the gradient has changed
signal gradient_changed
# Signal emitted when a history event for undo redo should be registered, ie when a slider timer completes, a colour preset is chosed or the colour picker popup is closed.
signal record_history
# Signal emitted when the colour picker is activated or deactivated
signal colour_picker_activated

# Init functions - not requiring any parameters. Note this is mostly ui creation
func _init():

	# Make a scroll container and add a vbox to it
	colour_points_scroll = ScrollContainer.new()
	colour_points_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	colour_points_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	colour_points_vbox = VBoxContainer.new()
	colour_points_scroll.add_child(colour_points_vbox)
	colour_points_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	colour_points_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	colour_points_scroll.rect_min_size = Vector2(0,256)
	

	# Make the gradient display hbox which contains the gradient colour rect and display details button
	gradient_display = HBoxContainer.new()
	display_details_button = Button.new()
	display_details_button.toggle_mode = true
	display_details_button.pressed = true
	display_details_button.hint_tooltip = "Toggle to show/hide the controls for the gradient map."
	display_details_button.connect("toggled", self, "_on_display_details_toggled")
	gradient_display.add_child(display_details_button)

	var label = Label.new()
	label.text = "Gradient"
	gradient_display.add_child(label)
	gradient = Gradient.new()

	gradient_texrect = TextureRect.new()
	gradient_display.add_child(gradient_texrect)
	gradient_texrect.size_flags_horizontal = 3
	gradient_texrect.size_flags_vertical = 1
	gradient_texrect.expand = true
	gradient_texture = GradientTexture.new()
	gradient_texture.gradient = gradient
	gradient_texrect.texture = gradient_texture
	gradient_texrect.rect_min_size = Vector2(53,53)

	_on_display_details_toggled(true)


# Set up all the initial functions. Noting that we can't do this with _init() as we can't pass global
func initial_setup():

	#Make the gradient overall levels slider
	levels_hbox = HBoxContainer.new()
	levels_slider = tool_panel.CreateRange("new_levels_slider_gradient", 0.0, 1.0, LEVELS_SLIDER_STEP, 0.0, 1.0)
	levels_slider.minSlider.connect("value_changed",self,"_on_levels_slider_value_changed")
	levels_slider.maxSlider.connect("value_changed",self,"_on_levels_slider_value_changed")
	tool_panel.Align.remove_child(levels_slider)
	var label = Label.new()
	label.text = "Levels"
	levels_hbox.add_child(label)
	levels_hbox.add_child(levels_slider)

	# Create presets class and ui
	PresetsDropdown = ResourceLoader.load(global.Root + "PresetsDropdown.gd", "GDScript", true)
	presetsdropdown = PresetsDropdown.new()
	presetsdropdown.gradientpresets_log_level = gradientpresets_log_level

	presetsdropdown.global = global
	presetsdropdown.unique_id = "uchideshi34.ColourObjectsAndPaths"
	presetsdropdown.make_presets_ui(null, 0)
	presetsdropdown.connect("request_save_current_preset_values", self, "save_current_preset_values")
	presetsdropdown.connect("load_preset_values", self, "load_preset_values_into_ui")
	# Load the current preset data file
	presetsdropdown._load_scatter_preset_config_file()

	# Update the icon for the display noting that we couldn't do this in _init as the global value had not been set
	display_details_button.icon = load_image_texture("icons/eye-icon.png")

	presetsdropdown.make_presets_import_and_export_ui(tool_panel.Align, -1)


#########################################################################################################
##
## PRESETS FUNCTIONS
##
#########################################################################################################

# Respond to a request from the presets to call the presetsdropdown with the current UI's values so it will save the data
func save_current_preset_values():

	var gradient_data = get_gradient_data()

	presetsdropdown.save_current_preset_values(gradient_data)

# Respond to a request from the presets dropdown to load the data into the gradient map
func load_preset_values_into_ui(gradient_data: Dictionary):

	set_gradient_values(gradient_data)


#########################################################################################################
##
## UTILITY FUNCTIONS
##
#########################################################################################################

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
			outputlog("Error in find_select_grid_menu: vbox section not found. " + tool_name)
			return null

#########################################################################################################
##
## UI CREATION FUNCTIONS
##
#########################################################################################################

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

# Function to start or reset the slider timer. Once the timer completes we call a function to emit the record history event.
func start_slider_timer(value: float, timer: Timer):

	if timer.is_stopped():
		timer.start()
	else:
		timer.wait_time = SLIDER_WAIT_TIME

# Function to make a new point at the end of the list
func make_new_colourpoint(offset: float = 1.0, color: Color = Color.white):

	outputlog("make_new_colourpoint",2)

	outputlog("offset: " + str(offset) + " color: " + str(color.to_html()),2)

	var hbox = HBoxContainer.new()
	colour_points_vbox.add_child(hbox)

	# Make the colour button and configure it
	var colourbutton = tool_panel.CreateColorButton(str(randi()),false, "ffffffff", [])
	colourbutton.rect_min_size = Vector2(53,53)
	colourbutton.size_flags_horizontal = 1
	colourbutton.get_parent().size_flags_horizontal = 1
	tool_panel.Align.remove_child(colourbutton.get_parent())
	hbox.add_child(colourbutton.get_parent())
	hbox.set_meta("colourbutton", colourbutton)
	colourbutton.connect("pressed", self, "_on_colour_button_activated", [true])
	colourbutton.get_popup().connect("popup_hide", self, "_on_colour_button_activated", [false])
	
	# Make the slider
	var slider = make_hslider(hbox, 1.0, 0.0, 1.0, 0.001)
	hbox.set_meta("slider", slider)
	slider.set_meta("previous_value", -1.0)
	
	# Make the move up button
	var up_button = Button.new()
	up_button.icon = ResourceLoader.load("res://ui/icons/misc/up.png")
	up_button.hint_tooltip = "Move colour point up."
	up_button.connect("pressed", self, "move_colourpoint", [hbox,"up"])
	hbox.add_child(up_button)
	up_button.visible = SHOW_MOVE_BUTTONS

	# Make the move down button
	var down_button = Button.new()
	down_button.icon = ResourceLoader.load("res://ui/icons/misc/down.png")
	down_button.hint_tooltip = "Move colour point down."
	down_button.connect("pressed", self, "move_colourpoint", [hbox,"down"])
	hbox.add_child(down_button)
	down_button.visible = SHOW_MOVE_BUTTONS

	# Make the move down button
	var add_above_button = Button.new()
	add_above_button.icon = ResourceLoader.load("res://ui/icons/buttons/add.png")
	add_above_button.hint_tooltip = "Add new colour point above."
	add_above_button.connect("pressed", self, "add_colourpoint", [hbox])
	hbox.add_child(add_above_button)

	# Make the move down button
	var delete_button = Button.new()
	delete_button.icon = load_image_texture("icons/trash-icon.png")
	delete_button.hint_tooltip = "Delete this colour point."
	delete_button.connect("pressed", self, "delete_colourpoint", [hbox])
	hbox.add_child(delete_button)

	gradient.add_point(1.0,Color.white)
	hbox.set_meta("gradient_index", gradient.get_point_count()-1)

	slider.connect("value_changed", self, "on_slider_value_changed", [hbox])
	colourbutton.get_picker().connect("color_changed", self, "refresh_gradient")
	colourbutton.get_popup().connect("popup_hide", self, "emit_history_event_signal")

	slider.value = clamp(offset,0.0,1.0)
	colourbutton.color = color

	return hbox

#########################################################################################################
##
## CORE COLOUR POINT FUNCTIONS
##
#########################################################################################################

# Delete a colour point provided there are more than two
func delete_colourpoint(hbox):

	outputlog("delete_colourpoint",3)

	# If we have at least two colour points then we can delete one
	if colour_points_vbox.get_child_count() > 2:
		colour_points_vbox.remove_child(hbox)
		hbox.queue_free()
		refresh_gradient(null)

# Create a new colour point above the current one
func add_colourpoint(hbox):

	outputlog("add_colourpoint",3)

	var new_hbox = make_new_colourpoint()
	colour_points_vbox.move_child(new_hbox, hbox.get_index())
	new_hbox.get_meta("slider").value = hbox.get_meta("slider").value
	refresh_gradient(null)

# Function to move colour point. noting that we are forcing a change in the value so the gradient will refresh
func move_colourpoint(hbox: HBoxContainer, direction: String):

	if direction == "up":
		# If we have actually moved then set the level to be the same as the one above
		if hbox.get_index() > 0:
			outputlog(hbox.get_parent().get_child(hbox.get_index()-1))
			# Check that this really is another colourpoint
			if hbox.get_parent().get_child(hbox.get_index()-1).has_meta("slider"):
				hbox.get_meta("slider").value = hbox.get_parent().get_child(hbox.get_index()-1).get_meta("slider").value

		hbox.get_parent().move_child(hbox, max(hbox.get_index()-1,0))
	else:
		# If we have actually moved then set the level to be the same as the one above
		if hbox.get_index() < hbox.get_parent().get_child_count()-1:
			# Check that this really is another colourpoint

			if hbox.get_parent().get_child(hbox.get_index()+1).has_meta("slider"):
				hbox.get_meta("slider").value = hbox.get_parent().get_child(hbox.get_index()+1).get_meta("slider").value
		hbox.get_parent().move_child(hbox, min(hbox.get_index()+1,hbox.get_parent().get_child_count()-1))

# Function to update when the slider value changes
func on_slider_value_changed(value: float, hbox):

	outputlog("on_slider_value_changed",3)

	var max_value = 1.0
	var min_value = 0.0
	var clamp_value

	if hbox.get_index() > 0:
		min_value = colour_points_vbox.get_child(hbox.get_index()-1).get_meta("slider").value + hbox.get_meta("slider").step
	if hbox.get_index() < colour_points_vbox.get_child_count()-1:
		max_value = colour_points_vbox.get_child(hbox.get_index()+1).get_meta("slider").value - hbox.get_meta("slider").step
	clamp_value = clamp(value, min_value, max_value)

	slider_change(clamp_value, hbox.get_meta("slider"), true)
	slider_change(clamp_value, hbox.get_meta("slider").get_meta("spinbox"), true)

	if not is_equal_approx(hbox.get_meta("slider").get_meta("previous_value"),clamp_value):
		hbox.get_meta("slider").set_meta("previous_value", clamp_value)
		refresh_gradient(null)
	

# Look through all the colour points and update the gradient to reflect their values
func refresh_gradient(ignore_this):

	outputlog("refresh_gradient",3)

	var hbox
	gradient = Gradient.new()

	if gradient.get_point_count() > colour_points_vbox.get_children().size():
		for _i in gradient.get_point_count() - colour_points_vbox.get_children().size():
			gradient.remove_point(0)
	for _i in colour_points_vbox.get_children().size():
		hbox = colour_points_vbox.get_children()[_i]
		if _i < gradient.get_point_count():
			gradient.set_offset(_i, hbox.get_meta("slider").value)
			gradient.set_color(_i, hbox.get_meta("colourbutton").color)
		else:
			gradient.add_point(hbox.get_meta("slider").value, hbox.get_meta("colourbutton").color)
	
	outputlog("gradient.colors: " + str(gradient.colors),3)
	outputlog("gradient.offsets: " + str(gradient.offsets),3)

	gradient_texrect.texture.gradient = gradient

	# If the gradient location has been initialised then emit a signal on change
	if tool_type != "" && location != "":
		outputlog("emit_signal gradient_changed",3)
		self.emit_signal("gradient_changed", tool_type, location)
	
	# Change the levels slider to reflect the new values
	# Find the min and max values in the colour points
	slider_change(colour_points_vbox.get_child(0).get_meta("slider").value, levels_slider.minSlider, true)
	slider_change(colour_points_vbox.get_child(colour_points_vbox.get_child_count()-1).get_meta("slider").value, levels_slider.maxSlider, true)


# Look through all the colour points and update the gradient to reflect their values
func reset():

	outputlog("reset_gradient",3)
	var reset_data = {"colours": ["ff000000","ffffffff"], "offsets": [0.0,1.0]}

	set_gradient_values(reset_data)

# Function to set the gradient values based on a data dictionary
func set_gradient_values(gradient_data: Dictionary):

	outputlog("set_gradient_values",2)

	# Check the data is a valid format
	if not is_valid_gradient_data(gradient_data):
		return

	# If the new gradient data has more entries than the current version then remove those colour points
	if colour_points_vbox.get_children().size() > gradient_data["colours"].size():
		for _i in colour_points_vbox.get_children().size() - gradient_data["colours"].size():
			delete_colourpoint(colour_points_vbox.get_child(_i))

	# For each record in the data
	for _i in gradient_data["colours"].size():
		# Update the values of the existing points
		if _i < colour_points_vbox.get_children().size():
			colour_points_vbox.get_child(_i).get_meta("slider").value = gradient_data["offsets"][_i]
			colour_points_vbox.get_child(_i).get_meta("colourbutton").color = Color(gradient_data["colours"][_i])
		# Otherwise add points
		else:
			make_new_colourpoint(gradient_data["offsets"][_i], Color(gradient_data["colours"][_i]))

	refresh_gradient(null)

# Function to check the validity of the gradient data
func is_valid_gradient_data(gradient_data: Dictionary):

	# Error checking on the gradient_data
	if not gradient_data.has("colours") || not gradient_data.has("offsets"):
		return false
	if gradient_data["colours"].size() != gradient_data["offsets"].size():
		return false
	if gradient_data["colours"].size() < 2:
		return false
	outputlog("is_valid_gradient_data: true",2)
	return true


#########################################################################################################
##
## CORE UI CHANGE FUNCTIONS
##
#########################################################################################################

# Function implement levels change
func _on_levels_slider_value_changed(value: float):

	var max_level = 1.0
	var min_level = 0.0
	var max_in_gradients = 1.0
	var min_in_gradients = 0.0
	var dist = 0.0
	var new_value

	outputlog("_on_levels_slider_value_changed",2)

	max_level = levels_slider.MaxRange.value
	min_level = levels_slider.MinRange.value

	# Check and see if we have squeezed the slider past when we could fit all the colour points within
	max_level = clamp(max_level,min_level + LEVELS_SLIDER_STEP * (colour_points_vbox.get_child_count()-1),1.0)
	# If we have then set the max level of the slider and return as this should drive another change
	if not is_equal_approx(max_level,levels_slider.MaxRange.value):
		levels_slider.maxSlider.value = max_level
		return

	# Find the min and max values of the colourpoints
	if colour_points_vbox.get_child_count() < 2:
		return
	
	# Find the min and max values in the colour points
	min_in_gradients = colour_points_vbox.get_child(0).get_meta("slider").value
	max_in_gradients = colour_points_vbox.get_child(colour_points_vbox.get_child_count()-1).get_meta("slider").value

	# For each colour point
	for colour_point in colour_points_vbox.get_children():
		# If avoid divide by zero (which shouldn't occur anyway)
		if not is_equal_approx(min_in_gradients,max_in_gradients):
			dist = (colour_point.get_meta("slider").value - min_in_gradients) / (max_in_gradients - min_in_gradients)
		else:
			dist = 0.0
		
		# Set the new slider values suppressing signals
		new_value = stepify(lerp(min_level, max_level, dist), LEVELS_SLIDER_STEP)

		# If this isn't the first point
		if colour_point.get_index() > 0:
			# If the value is the same as the previous lower values
			if new_value == colour_points_vbox.get_child(colour_point.get_index()-1).get_meta("slider").value:
				# Bump it up one step
				new_value =+ LEVELS_SLIDER_STEP

		# Check whether there is enough space for the remaining points
		var remaining_points = colour_points_vbox.get_child_count() - colour_point.get_index() - 1
		# If there isn't enough space for the remaining points
		if (remaining_points - 1) * LEVELS_SLIDER_STEP + new_value >= max_level:
			# Move new_value down by enough steps
			new_value = stepify(max_level - (remaining_points - 1) * LEVELS_SLIDER_STEP, LEVELS_SLIDER_STEP)

		# Set the slider values
		slider_change(new_value, colour_point.get_meta("slider"), true)
		slider_change(new_value, colour_point.get_meta("slider").get_meta("spinbox"), true)

	# Refresh the gradient to propagate the new values
	refresh_gradient(null)


# Function to show or hide the gradient details and controls
func _on_display_details_toggled(button_pressed: bool):

	if button_pressed:
		colour_points_scroll.visible = true
		levels_hbox.visible = true
		gradient_display.rect_min_size = Vector2(MIN_X_SIZE_FOR_DETAILS,0)
	else:
		colour_points_scroll.visible = false
		levels_hbox.visible = false
		gradient_display.rect_min_size = Vector2.ZERO

# Takes the ui of the gradient map and relocates it to the new area
func move_location(new_tool_type: String, new_location: String, show_ui: bool):
	
	# If we are already in the right place then do nothing
	if new_tool_type == tool_type && new_location == location:
		return

	outputlog("move_location: tool_type: " + str(new_tool_type) + " location: " + str(new_location),2)
	tool_type = new_tool_type
	location = new_location

	var current_vbox = colour_points_scroll.get_parent()
	var find_text = ["CUSTOM COLOR","CUSTOM_COLOR","TRANSITION_IN","TRANSITION IN","COLOR","FILL"]

	var new_vbox

	# Set up the tool panel and vbox values
	if location == "main":
		new_vbox = global.Editor.Toolset.GetToolPanel(tool_type).Align
	else:
		new_vbox = find_select_vbox(tool_type)
		if new_vbox == null:
			return

	var new_index = max(0,new_vbox.get_child_count()-1)
	# Look through all the children and when we find a label or button with the right text then store that index
	for thing in new_vbox.get_children():
		if thing is Label || thing is Button:
			if thing.text.to_upper() in find_text:
				new_index = thing.get_index()
		if thing is HBoxContainer:
			if thing.get_children().size() > 0:
				if thing.get_child(0) is Label:
					if thing.get_child(0).text.to_upper() in find_text:
						new_index = thing.get_index()
	
	if current_vbox != null:
		current_vbox.remove_child(colour_points_scroll)
		current_vbox.remove_child(gradient_display)
		current_vbox.remove_child(levels_hbox)
		current_vbox.remove_child(presetsdropdown.ui_hbox)

	new_vbox.add_child(colour_points_scroll)
	new_vbox.move_child(colour_points_scroll,new_index)

	# NOTE - moving the levels rangeslider seems to trigger a signal so suppress the connected signals while this happens
	levels_slider.minSlider.set_block_signals(true)
	levels_slider.maxSlider.set_block_signals(true)
	new_vbox.add_child(levels_hbox)
	new_vbox.move_child(levels_hbox,new_index)

	# NOTE - undo the signal suppression
	levels_slider.minSlider.set_block_signals(false)
	levels_slider.maxSlider.set_block_signals(false)

	new_vbox.add_child(gradient_display)
	new_vbox.move_child(gradient_display,new_index)

	new_vbox.add_child(presetsdropdown.ui_hbox)
	new_vbox.move_child(presetsdropdown.ui_hbox,new_index)

	# Hide or show the ui
	if show_ui:
		show()
	else:
		hide()
	
	outputlog("move_location: complete",2)

# Function to hide the gradient map UI
func hide():

	outputlog("hide",2)

	gradient_display.visible = false
	colour_points_scroll.visible = false
	presetsdropdown.ui_hbox.visible = false
	levels_hbox.visible = false

# Function to show the gradient map UI
func show():

	outputlog("show",2)

	gradient_display.visible = true
	colour_points_scroll.visible = display_details_button.pressed
	presetsdropdown.ui_hbox.visible = true
	levels_hbox.visible = display_details_button.pressed


#########################################################################################################
##
## DATA RETRIEVAL FUNCTIONS
##
#########################################################################################################

# Function to return a dictionary of the gradient data in a readable format
func get_gradient_data(debug: bool = true):

	var gradient_data = {"colours": [], "offsets": []}

	if debug:
		outputlog("get_gradient_data",2)

	for _i in gradient.get_point_count():
		gradient_data["colours"].append(gradient.get_color(_i).to_html())
		gradient_data["offsets"].append(gradient.get_offset(_i))
	
	if debug:
		outputlog("gradient_data: " + str(gradient_data),2)

	return gradient_data


#########################################################################################################
##
## HISTORY FUNCTIONS
##
#########################################################################################################
	
# Function called when a record history event should be emitted
func emit_history_event_signal():

	self.emit_signal("record_history", null, tool_type, location)

# Function to emit when the colour button is activated
func _on_colour_button_activated(is_active: bool):

	outputlog("_on_colour_button_activated: " + str(is_active),2)

	self.emit_signal("colour_picker_activated", is_active, tool_type, location)



