# Custom Data Manager v1.0.7
class_name CustomDataManager

var global = null

var cloneleveloptionbutton = null
var store_level_list = []
var modmapdata_list = ["ColourObjects", "PathOffset", "EdgeBlurPatterns"]

var copied_data_store = {"objects": [], "paths": [], "pattern_shapes": [], "portals": [], "raw": {}}

const TYPE_LOOKUP = {"ObjectTool": "objects","ScatterTool": "objects", "PathTool": "paths", "PatternShapeTool": "pattern_shapes", "WallTool": "walls", "PortalTool": "portals"}
const TOOL_TYPE_LOOKUP_BY_SELECTABLE = {"1": "WallTool", "2": "PortalTool", "3": "PortalTool", "4": "ObjectTool", "5": "PathTool", "6": "LightTool", "7": "PatternShapeTool", "8": "RoofTool"}

const DEFAULT_COMBINED_DATA = {
	"shader_type": "none",
	"colour": "ffffffff",
	"start_point": 0.0,
	"has_edge_blur": false,
	"path_flip_vertical": false
}
const COMBINED_DATA_STORE = "UchideshiNodeData"

signal apply_custom_data_to_node

# Logging Functions
const ENABLE_LOGGING = true
var logging_level = 2

func outputlog(msg,level=0):
	if ENABLE_LOGGING:
		if level <= logging_level:
			printraw("(%d) <CustomDataManager>: " % OS.get_ticks_msec())
			print(msg)
	else:
		pass

#########################################################################################################
##
## UTILITY FUNCTIONS
##
#########################################################################################################

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

	if node == null or not is_instance_valid(node): return null

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
## COPY LEVEL FUNCTIONS
##
#########################################################################################################

# Function to determine whether a node is on a specific world level
func is_node_on_level(node, level) -> bool:

	outputlog("is_node_on_level",2)
	outputlog("node: " + str(node) + " level: " + str(level),2)

	var type = get_node_type(node)
	if type == null: return false
	if node.get_parent() == null: return false

	# If this is not a pattern shape then the nodes are held in single parent node
	if type != "pattern_shapes":
		if node.get_parent() != null:
			# If this is not a portal, then look for the Level property
			if type != "portals":
				outputlog("is not a portal",2)
				if node.get_parent().has("Level"):
					if node.get_parent().Level == level:
						# If so, then add the drop shadow data to the matching object
						outputlog("return true",2)
						return true
			# If it is a portal, then note that Portals is only a node and doesn't have the Level property, look for its parent
			else:
				# If attached to a wall
				if node.WallID >= 0:
					# Get the wall node and check that it is attached to parent, Walls
					if global.World.GetNodeByID(node.WallID).get_parent() != null:
						# Check that Walls has a Level
						if global.World.GetNodeByID(node.WallID).get_parent().has("Level"):
							# Check that the level matches the required level
							if global.World.GetNodeByID(node.WallID).get_parent().Level == level:
								# If so, then add the drop shadow data to the matching object
								outputlog("return true",2)
								return true
				# If freestanding then it is attached to the Portals node.
				else:
					if node.get_parent().get_parent() != null:
						if node.get_parent().get_parent() == level:
							# If so, then add the drop shadow data to the matching 
							outputlog("return true",2)
							return true

	# If this is a pattern, then they are contained in layer then a node, PatternShapes, but we can reference it directly vis GetShapes()
	else:
		if node.GetShapes():
			if node.GetShapes().has("Level"):
				if node.GetShapes().Level == level:
					# If so, then add the drop shadow data to the matching object
					outputlog("return true",2)
					return true

	outputlog("return false",2)
	return false

# Copy the colour data where required
func _copy_custom_data_to_new_level(source_level_index: int):

	outputlog("_copy_custom_data_to_new_level: " + str(source_level_index),2)

	var count = 0
	var node_id

	# Copy the Dropshadow data into a separate record so we don't iterate over newly created records
	if not global.ModMapData.has(COMBINED_DATA_STORE):
		return
	if not global.ModMapData[COMBINED_DATA_STORE].has("data"):
		return

	var copy_of_custom_data = global.ModMapData[COMBINED_DATA_STORE]["data"].duplicate(true)
	# Get the reference to the level from the index
	var source_level = global.World.TryGetLevel(source_level_index)

	if source_level == null:
		return
		
	var new_level = find_new_level_created()
	if new_level == null:
		outputlog("failed to find new level",2)
		return
	
	# For each node reference in the ds data
	for node_id_string in copy_of_custom_data.keys():
		# Check if the level is the same as the level being copied
		node_id = int(node_id_string.replace("node-id-",""))
		outputlog("node_id_string: " + str(node_id_string),2)
		if global.World.HasNodeID(node_id):
			outputlog("has nodeid: " + str(node_id_string),2)
			# Check if the node is on the source level, ie if we should look to copy their data values to the new level
			if is_node_on_level(global.World.GetNodeByID(node_id), source_level):
				outputlog("node is on the right level: " + str(source_level) + " id: " + str(source_level.ID),2)
				# Look to match the original node to the copied levels node
				add_custom_data_to_new_level(node_id, copy_of_custom_data[node_id_string], new_level)
				count += 1
	
	outputlog("Custom values added to " + str(count) + " nodes on level, " + str(new_level.Label) + ".",0)

# Function to add the custom data to a matched object or path
func add_custom_data_to_new_level(copied_node_id, data: Dictionary, new_level):

	outputlog("add_colour_data_to_new_level",2)
	var new_node = null

	# Find the source node by id
	var copied_node = global.World.GetNodeByID(copied_node_id)
	if copied_node == null:
		return
	
	# The new object should be at the same index in the newly created Level 0
	match data["type"]:
		"objects":
			new_node = new_level.Objects.get_child(copied_node.get_index())
		"paths":
			new_node = new_level.Pathways.get_child(copied_node.get_index())
		"walls":
			new_node = new_level.Walls.get_child(copied_node.get_index())
		"portals":
			# If attached to a wall
			if copied_node.WallID >= 0:
				# Find the wall on the original level
				var copied_wall = global.World.GetNodeByID(copied_node.WallID)
				# Find its equivalent on the new level
				var new_wall = new_level.Walls.get_child(copied_wall.get_index())
				# Set the new node to be the equivalent portal
				new_node = new_wall.get_child(copied_node.get_index())
			# If freestanding then it is attached to the Portals node.
			else:
				new_node = new_level.Portals.get_child(copied_node.get_index())
		# We need to do something special with patterns as they are stored in layers
		"pattern_shapes":
			new_node = new_level.PatternShapes.GetOrMakeLayer(copied_node.GetLayer()).get_child(copied_node.get_index())
		_:
			return
	if new_node == null:
		return

	# Copy the existing drop shadow data from the source object
	var new_data = data.duplicate(true)
	# Add the set data function HERE
	emit_signal("apply_custom_data_to_node", new_node, new_data)

# When create new level is pressed
func _on_create_new_level_pressed():

	outputlog("_on_create_new_level_pressed",2)

	var timer = Timer.new()
	timer.autostart = false
	timer.one_shot = true
	global.Editor.get_node("Windows").add_child(timer)

	# If we are cloning a level, ie selected index is more than zero, then do something but wait a bit first
	if cloneleveloptionbutton.selected > 0:
		timer.start(1.0)
		yield(timer,"timeout")
		_copy_custom_data_to_new_level(cloneleveloptionbutton.selected)
	
	global.Editor.get_node("Windows").remove_child(timer)
	timer.queue_free()

# Find the new level window
func find_new_level_window():

	outputlog("find_new_level_window",2)

	var newlevelwindow = global.Editor.Windows["NewLevel"]
	newlevelwindow.connect("about_to_show", self, "on_new_level_window_opened")

	var valign = newlevelwindow.get_node("Margins").get_node("VAlign")

	# If we have successfully found the Create Level window then connect to the "Create" button 
	if valign != null:
		if valign.get_node("Buttons") != null && valign.get_node("CloneLevel") != null:
			if valign.get_node("Buttons").get_node("OkayButton") != null && valign.get_node("CloneLevel").get_node("CloneLevelOptionButton") != null:
				valign.get_node("Buttons").get_node("OkayButton").connect("pressed", self, "_on_create_new_level_pressed")
				cloneleveloptionbutton = valign.get_node("CloneLevel").get_node("CloneLevelOptionButton")
				valign.get_node("Buttons").get_node("OkayButton").hint_tooltip = "To see override colour effects on new copied level, save and reopen the map."

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
## MIGRATE LEGACY MODMAPDATA FUNCTIONS
##
#########################################################################################################

# Function to migrate legacy modmapdata
func migrate_legacy_modmapdata():

	outputlog("migrate_legacy_modmapdata",2)

	var new_data: Dictionary
	var node_id

	# Check each of the possible source of data
	for modmapdata in modmapdata_list:
		# If the record type exists
		if global.ModMapData.has(modmapdata):
			# Check that it has a data element (which it should do if it exists but stops a crash if it doesn't)
			if global.ModMapData[modmapdata].has("data"):
				# Look at each node string in this srouce
				for node_id_string in global.ModMapData[modmapdata]["data"].keys():
					# Create a node_id from this
					node_id = int(node_id_string.replace("node-id-",""))
					# If there is no record in the combined data record, use the default value
					if not has_data(node_id):
						new_data = DEFAULT_COMBINED_DATA.duplicate(true)
					# Otherwise get that data
					else:
						new_data = get_data(node_id)
					# Merge the just found data with the existing data
					new_data = merge_dict(new_data, get_data_by_modmap(node_id, modmapdata))
					# Update the data record to reflect this
					set_data(node_id, new_data)
				# Empty the data set of the legacy data
				global.ModMapData[modmapdata]["data"].clear()

#########################################################################################################
##
## READ & WRITE MODMAPDATA FUNCTIONS
##
#########################################################################################################

# Function to implement all of the stored colour configurations. if type_list is empty then process all types
func apply_custom_data_to_map(type_list: Array = [], delay: float = 0.0):

	outputlog("apply_custom_data_to_map: type: " + str(type_list) + " delay: " + str(delay),0)	
	
	# Make a timer to
	var timer = Timer.new()
	timer.autostart = false
	timer.one_shot = true
	global.Editor.get_node("Windows").add_child(timer)

	# Wait a couple of seconds to ensure everything has been drawn, the delay value has been set.
	if delay > 0.0:
		timer.start(delay)
		yield(timer,"timeout")

	var custom_data
	var node_id

	if not global.ModMapData.has(COMBINED_DATA_STORE):
		return
	if not global.ModMapData[COMBINED_DATA_STORE].has("data"):
		return

	# Look at each record in the stored data
	for node_id_string in global.ModMapData[COMBINED_DATA_STORE]["data"].keys():
		# Purge malformed data entries
		if not "node-id-" in node_id_string:
			global.ModMapData[COMBINED_DATA_STORE]["data"].erase(node_id_string)
			continue

		node_id = int(node_id_string.replace("node-id-",""))
		
		# If there is matching node in the map
		if global.World.HasNodeID(node_id):
			# Retrieve the colour data
			custom_data = get_data(node_id)

			# Check if we have are doing everything or if the current data type is one of the requested values
			if type_list.size() == 0 || custom_data["type"] in type_list:
				# Set the custom data action
				emit_signal("apply_custom_data_to_node", global.World.GetNodeByID(node_id), custom_data)

		# If the node in question has been deleted then purge the relevant colour data from the record
		else:
			erase_data(node_id)
	
	global.Editor.get_node("Windows").remove_child(timer)
	timer.queue_free()


# Function to set data to the consolidated data set
func set_data(node_id: int, data: Dictionary):

	outputlog("set_data",2)
	var config_data

	if data.has("path_data"):
		data.erase("path_data")

	# These should be made already but if not, then create the holding dictionaries
	if not global.ModMapData.has(COMBINED_DATA_STORE):
		global.ModMapData[COMBINED_DATA_STORE] = {}
	if not global.ModMapData[COMBINED_DATA_STORE].has("data"):
		global.ModMapData[COMBINED_DATA_STORE]["data"] = {}
	outputlog("new data: " + str(data),2)
	# If there is already a data record, then merge the data with the new data overwriting the current data
	if has_data(node_id):
		config_data = get_data(node_id).duplicate(true)
	# Otherwise use the default data record and overwrite that one
	else:
		config_data = DEFAULT_COMBINED_DATA.duplicate(true)

	# Merge the new data into the existing data overwriting where needed
	config_data = merge_dict(config_data,data)
	outputlog("complete config_data: " + str(config_data),2)

	# Set the type if it hasn't been defined, which it should be really.
	if not config_data.has("type"):
		config_data["type"] = get_node_type(global.World.GetNodeByID(node_id))

	# If the resulting config is just the detault one. Noting that type doesn't exist in the default data
	if is_data_default(config_data):
		outputlog("Default data: " + str(config_data),2)
		# If there is data and this is default then delete it
		if has_data(node_id):
			outputlog("Default data so delete record: " + str(node_id),2)
			erase_data(node_id)
		
		# Nothing more to do so return
		return

	# If there is no current record for that node_id then create one, noting that the initial load from the map file means the dictionary key is interpreted as a string so need to check that
	if not has_data(node_id):
		outputlog("Create new record: " + "node-id-"+str(node_id),2)
		global.ModMapData[COMBINED_DATA_STORE]["data"]["node-id-"+str(node_id)] = {}

	global.ModMapData[COMBINED_DATA_STORE]["data"]["node-id-"+str(node_id)] = config_data.duplicate(true)

# Is the data the default set, ie compare but remove the type key
func is_data_default(config_data, ignore_colour: bool = false):

	if config_data["colour"] != Color.white.to_html() && not ignore_colour:
		return false
	
	if config_data["shader_type"] != "none":
		return false
	
	if config_data["has_edge_blur"]:
		return false
	
	if config_data["start_point"] > 0.00001:
		return false
	
	if config_data["path_flip_vertical"]:
		return false
	
	if config_data.has("fade_distance") && config_data["type"] == "paths":
		if not is_equal_approx(config_data["fade_distance"],0.1):
			return false
	
	return true

# Function to check if there is a data entry with this node id
func has_data(node_id) -> bool:

	outputlog("has_data: " + str(node_id),3)

	# Error checking if the holding structures have not been created.
	if not global.ModMapData.has(COMBINED_DATA_STORE):
		outputlog("no COMBINED_DATA_STORE",3)
		return false
	if not global.ModMapData[COMBINED_DATA_STORE].has("data"):
		outputlog("no COMBINED_DATA_STORE['data']",3)
		return false

	if global.ModMapData[COMBINED_DATA_STORE]["data"].has("node-id-"+str(node_id)):
		outputlog("has_data: true",3)
		return true
	else:
		return false

# Function to erase data with a specific node id
func erase_data(node_id: int):

	outputlog("erase_data: " + str(node_id),2)

	if has_data(node_id):
		global.ModMapData[COMBINED_DATA_STORE]["data"].erase("node-id-"+str(node_id))


# Function to get the colour data from the modmapdata structure
func get_data(node_id):

	if has_data(node_id):
		var data = global.ModMapData[COMBINED_DATA_STORE]["data"]["node-id-"+str(node_id)]
		# If this is a pattern or a wall then take the colour from the node's in built colour value
		if global.World.HasNodeID(node_id):
			if data["type"] in ["pattern_shapes","walls"]:
				data["colour"] = get_dd_colour(global.World.GetNodeByID(node_id), data["type"])
		convert_data_from_colourised_to_normalised(data)
		return data
	else:
		return null

# Function to get data for this node from the data store or return the default config if not. Used for creating history records.
func get_data_or_default(node_id: int) -> Dictionary:

	if has_data(node_id):
		return get_data(node_id)
	else:
		return DEFAULT_COMBINED_DATA.duplicate(true)

# Function to return the colour string from the patternshape
func get_pattern_colour(patternshape):

	if patternshape != null:
		var definition = patternshape.Save(true)
		if definition != null:
			if definition.has("color"):
				return definition["color"]
	
	return null

# Function to return the custom colour of a node
func get_dd_colour(node, type) -> String:

	match type:
		"pattern_shapes":
			if get_pattern_colour(node) != null:
				return get_pattern_colour(node)
		"walls":
			return node.Color.to_html()

	return Color.white.to_html()

# Function to return the shader type value from a set of booleans
func get_shader_type(make_saturated: bool, make_normalised: bool, make_white: bool, make_gradient: bool):

	if make_saturated:
		return "saturation"
	if make_normalised:
		return "normalised"
	if make_white:
		return "white"
	if make_gradient:
		return "gradient"

	return "none"

# Function to convert Colour data to new format which includes "shader_type"
func convert_colour_data_to_new_struct(data: Dictionary) -> Dictionary:

	if data.has("make_white"):
		# Directly set colourised as we are reusing the get_shader_type function which does not include it. Noting this gets reset to "normalised" later.
		if data["make_colourised"]:
			data["shader_type"] == "colourised"
		else:
			data["shader_type"] = get_shader_type(false, data["make_normalised"], data["make_white"], false)
		data.erase("make_colourised")
		data.erase("make_normalised")
		data.erase("make_white")
	
	return data

# Function to convert colourised to normalised
func convert_data_from_colourised_to_normalised(data: Dictionary):

	if data["shader_type"] == "colourised":
		data["shader_type"] = "normalised"
		data["levels"] = [0.0,0.0,1.0]

# Function to get the colour data from the modmapdata structure
func get_data_by_modmap(node_id, modmapdata: String):

	var data = {}

	outputlog("get_data_by_modmap: " + str(modmapdata),2)

	if has_data_by_modmap(node_id, modmapdata):
		data = global.ModMapData[modmapdata]["data"]["node-id-"+str(node_id)]
		# Conversion from old data storage structure
		if modmapdata == "ColourObjects":
			data = convert_colour_data_to_new_struct(data)
		
			# If this is a pattern or a wall then take the colour from the node's in built colour value
			if global.World.HasNodeID(node_id):
				if data["type"] in ["pattern_shapes","walls"]:
					data["colour"] = get_dd_colour(global.World.GetNodeByID(node_id), data["type"])
			
			convert_colour_data_to_new_struct(data)
		elif modmapdata == "EdgeBlurPatterns":
			data["has_edge_blur"] = true
			data = migrate_edge_blur_pattern_colour_to_standard_dd_colour(node_id, data)
		return data
	else:
		return null


# Function to look at a legacy edge blur pattern data record and if it has a custom colour change that to the new structure, i.e. set the standard DD colour for that node
func migrate_edge_blur_pattern_colour_to_standard_dd_colour(node_id: int, config: Dictionary):

	outputlog("migrate_edge_blur_pattern_colour_to_standard_dd_colour",2)

	var node

	# Check that the node exists
	if global.World.HasNodeID(node_id):
		node = global.World.GetNodeByID(node_id)
		# CHeck that it has a colour record, which it always should do
		if config.has("colour"):
			# If the colour in the config is not the same as the colour stored in the DD record
			if config["colour"] != get_dd_colour(node, "pattern_shapes"):
				outputlog("migrating edge blur node colour data: " + str(node_id) + " setting dd colour: " + str(config["colour"]),2)
				# Set the options which importantly set the value in the DD data object
				node.SetOptions(node._Texture, Color(config["colour"]), node._Rotation)
				config["colour"] = "ffffffff"
	
	return config



# Function to check if there is a data entry with this node id
func has_data_by_modmap(node_id, modmapdata: String) -> bool:

	if not global.ModMapData.has(modmapdata):
		return false
	
	if not global.ModMapData[modmapdata].has("data"):
		return false

	if global.ModMapData[modmapdata]["data"].has("node-id-"+str(node_id)):
		return true
	else:
		return false


#########################################################################################################
##
## COPY AND PASTE SUPPORT FUNCTIONS
##
#########################################################################################################

# Function to apply stored colours to pasted nodes
func apply_custom_data_to_pasted_nodes():

	if not global.Editor.ActiveToolName == "SelectTool":
		return
	if not global.Editor.Tools["SelectTool"].HasPastable:
		return

	outputlog("apply_custom_data_to_pasted_nodes", 1)
	var node
	var list = {"objects": [], "paths": [], "portals": [], "pattern_shapes": [], "walls": []}
	var new_node_id

	# If the stored copy data is the same as the data held in the clipboard then the store is valid
	if is_the_same(JSON.parse(OS.get_clipboard()).result, copied_data_store["raw"]):
		# Count the number of valid records in the copied_data_store so we can estimate the node_ids that have just been created
		var count_pastable_nodes = 0
		# Check each type which we will take from the list array
		for type in list.keys():
			# Correct paths to pathways as that is the raw data key
			if type == "paths":
				type = "pathways"
			# If there is any of that type in the copy payload
			if copied_data_store["raw"].has(type):
				# Count how many of that type
				count_pastable_nodes += copied_data_store["raw"][type].size()
		
		# Look at all of the nodes that have just been created and categorise them into objects and paths in a list
		# Note we are counting back from the next node id using the number of pastable nodes found earlier
		for node_id in range(global.World.nextNodeID - count_pastable_nodes,global.World.nextNodeID,1):
			# Check whether the node exists in case it as been deleted
			if not global.World.HasNodeID(node_id):
				continue
			# Get the node, noting this can't be null but double check anyway
			node = global.World.GetNodeByID(node_id)
			if node != null:
				# Determine what type of node it is and add the id to the right list
				var ntype = get_node_type(node)
				if ntype != null and list.has(ntype):
					list[ntype].append(node_id)

		outputlog(JSON.print(list,'\t',2))
		outputlog(JSON.print(copied_data_store,'\t',2))
		
		# For each of objects and paths
		for type in list.keys():
			# For each record in
			if copied_data_store.has(type):
				for copy_record in copied_data_store[type]:
					# Get the node id which is the same order (hopefully!)
					if copy_record.has("index"):
						if copy_record["index"] < list[type].size():
							new_node_id = list[type][copy_record["index"]]
							if global.World.HasNodeID(new_node_id):
								# Set the type record in case it doesn't exist (which it should)
								copy_record["type"] = type
								# If the data is default then we don't want to apply anything noting that we created default records for all the non-custom assets, so check before emitting the signal
								if not is_data_default(copy_record):
									# Emit the signal to tell the main script to apply custom values to the node
									emit_signal("apply_custom_data_to_node", global.World.GetNodeByID(new_node_id), copy_record)
	else:
		outputlog("stored copy data does not match clipboard values",2)
		outputlog(JSON.print(OS.get_clipboard(),"\t"),2)
		outputlog(JSON.print(copied_data_store["raw"],"\t"),2)

# Function to store the colour data for eligible nodes copied to the clipboard
func store_copy_data():

	outputlog("store_copy_data",2)

	var type
	var data = {}
	var count = {"objects": 0, "paths": 0, "portals": 0, "pattern_shapes": 0, "walls": 0}
	var selectable_type

	# If there is nothing to copy then return
	if global.Editor.Tools["SelectTool"].Selected.size() == 0:
		return

	copied_data_store["objects"] = []
	copied_data_store["paths"] = []
	copied_data_store["pattern_shapes"] = []
	copied_data_store["portals"] = []
	copied_data_store["walls"] = []

	copied_data_store["raw"] = JSON.parse(global.Editor.Tools["SelectTool"].Serialize(true)).result

	# For each node, sort them into objects and paths
	for selected_node in global.Editor.Tools["SelectTool"].Selected:

		# Get the selectable type
		selectable_type = global.Editor.Tools["SelectTool"].GetSelectableType(selected_node)
		outputlog("selectable_type: " + str(selectable_type),2)
		# Guard: skip unknown selectable types (e.g. 0 for partially constructed nodes)
		if not TOOL_TYPE_LOOKUP_BY_SELECTABLE.has(str(selectable_type)):
			continue
		var tool_key = TOOL_TYPE_LOOKUP_BY_SELECTABLE[str(selectable_type)]
		if not TYPE_LOOKUP.has(tool_key):
			continue
		outputlog("TOOL_TYPE_LOOKUP_BY_SELECTABLE[selectable_type]: " + str(tool_key),2)
		outputlog("type: " + str(TYPE_LOOKUP[tool_key]),2)
		# 2nd order lookup to get the type
		type = TYPE_LOOKUP[tool_key]
		
		# Look for any stored data or simply use default data, if this does not have custom data
		if not selected_node.has_meta("node_id"):
			continue
		if has_data(selected_node.get_meta("node_id")):
			data = get_data(selected_node.get_meta("node_id")).duplicate(true)
		else:
			data = DEFAULT_COMBINED_DATA
		
		data["index"] = count[type]
		data["type"] = type
			
		copied_data_store[type].append(data.duplicate(true))
			
		# Keep an index count of each type
		count[type] += 1
	
	outputlog(JSON.print(copied_data_store,"\t"),2)


# Function to register an action for copy keys used in the select tool
func register_copy_keys_action():

	var event = InputEventKey.new()

	event.scancode = KEY_C
	event.control = true

	if not InputMap.has_action("copy_keys_pressed"):
		InputMap.add_action("copy_keys_pressed",0.5)
		InputMap.action_add_event("copy_keys_pressed", event)

# Function to register an action for copy keys used in the select tool
func register_paste_keys_action():

	var event = InputEventKey.new()

	event.scancode = KEY_V
	event.control = true

	if not InputMap.has_action("paste_keys_pressed"):
		InputMap.add_action("paste_keys_pressed",0.5)
		InputMap.action_add_event("paste_keys_pressed", event)

#########################################################################################################
##
## STORE UI CONFIG FUNCTIONS
##
#########################################################################################################

# Function to set the combined ui stored state, noting that config should always include type
func set_combined_ui_stored_state(config: Dictionary, tool_type: String, location: String):

	var worldui = global.WorldUI
	var combined_ui = {}

	outputlog("set_combined_ui_stored_state",2)

	# If there is no current record for the world ui
	if not worldui.has_meta("combined_ui_state"):
		worldui.set_meta("combined_ui_state",{})
	
	combined_ui = worldui.get_meta("combined_ui_state").duplicate(true)
	# If there is no key for this tool_type then created one
	if not combined_ui.has(tool_type):
		combined_ui[tool_type] = {}
	
	# If there is no key for this location, then create one with the default config values
	if not combined_ui[tool_type].has(location):
		combined_ui[tool_type][location] = DEFAULT_COMBINED_DATA.duplicate(true)
	
	if not config.has("type"):
		outputlog("error: no type found in config: " + str(config),2)

	# Remove unneeded records
	config = remove_unnecessary_colour_keys(config)
	config = remove_unnecessary_edgeblur_keys(config)

	# Merge the current value with the new config overwriting its values
	combined_ui = merge_dict(combined_ui, {tool_type: {location: config}})

	worldui.set_meta("combined_ui_state",combined_ui.duplicate(true))
	outputlog("combined_ui_state: " + str(JSON.print(combined_ui,"\t")),2)

# Remove any unneeded colour keys, for example, gradient, levels, etc.
func remove_unnecessary_colour_keys(combined_ui: Dictionary) -> Dictionary:

	var new_config = combined_ui.duplicate(true)

	# If this is not a gradient value then remove the gradient elements
	if new_config["shader_type"] != "gradient":
		new_config.erase("gradient")
		new_config.erase("red_config")
	
	# If this is not a normalised entry then we don't need "levels" or "levels" default_brightness
	if new_config["shader_type"] != "normalised":
		new_config.erase("levels")
		new_config.erase("levels_default_brightness")

	return new_config

# Remove any unneeded colour keys, for example, gradient, levels, etc.
func remove_unnecessary_edgeblur_keys(combined_ui: Dictionary) -> Dictionary:

	var new_config = combined_ui.duplicate(true)

	# If this is not a gradient value then remove the gradient elements
	if not new_config["has_edge_blur"]:
		new_config.erase("blur_range")
		new_config.erase("smoothness")
		new_config.erase("use_texture")
		new_config.erase("reverse_alpha")
		new_config.erase("shadow_direction")
	
	return new_config
	
# Function to retrieve the combined ui value from its stored location
func get_combined_ui_stored_state(tool_type: String, location: String):

	var worldui = global.WorldUI
	var config = {}
	var combined_ui = {}

	outputlog("get_combined_ui_stored_state",2)

	# If there is no current record for the world ui
	if not worldui.has_meta("combined_ui_state"):
		outputlog("worldui combined_ui_state not set",2)
		config = DEFAULT_COMBINED_DATA.duplicate(true)
		return config
	outputlog("worldui combined_ui_state: " + str(worldui.get_meta("combined_ui_state")),2)
	combined_ui = worldui.get_meta("combined_ui_state").duplicate(true)

	# If there is no key for this tool_type then create one
	if not combined_ui.has(tool_type):
		config = DEFAULT_COMBINED_DATA.duplicate(true)
		return config
	
	# If there is no key for this location, then create one with the default config values
	if not combined_ui[tool_type].has(location):
		config = DEFAULT_COMBINED_DATA.duplicate(true)
		return config
	
	config = combined_ui[tool_type][location].duplicate(true)

	return config