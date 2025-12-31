extends Reference

# Custom History Record for Colour Objects and Paths actions
var previous_node_data: Dictionary
var new_node_data: Dictionary

# Logging Functions
const ENABLE_LOGGING = false
const LOGGING_LEVEL = 0

func outputlog(msg,level=0):
	if ENABLE_LOGGING:
		if level <= LOGGING_LEVEL:
			printraw("(%d) <ModifyPathsHistory>: " % OS.get_ticks_msec())
			print(msg)
	else:
		pass

# Function to update the path values based on a dictionary
func set_path_values(path,history_record):

	outputlog("set_path_values: " + str(history_record),2)

	path.SetWidthScale(history_record["widthscale"])
	path.Smoothness = history_record["smoothness"]
	path.FadeIn = history_record["FadeIn"]
	path.FadeOut = history_record["FadeOut"]
	path.Grow = history_record["Grow"]
	path.Shrink = history_record["Shrink"]
	path.Smooth()
	path.UpdateGradient()

# Function to update the paths based on a a records dictionary
func update_paths_from_record(records: Dictionary):

	var path
	# For each entry in the history record, set everything back to the previous version
	for node_id_string in records.keys():
		if Global.World.HasNodeID(int(records[node_id_string]["node_id"])):
			path = Global.World.GetNodeByID(int(records[node_id_string]["node_id"]))
			set_path_values(path,records[node_id_string])

func undo():

	outputlog("undo",2)

	update_paths_from_record(previous_node_data)
		
func redo():

	outputlog("redo",2)

	update_paths_from_record(new_node_data)


		
