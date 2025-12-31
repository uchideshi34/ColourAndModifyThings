extends Reference

# Custom History Record for combined shader
# v1.0.0
var type = "combinedshader"
var combinedshader = null
var customdatamanager = null
var previous_node_data: Dictionary
var new_node_data: Dictionary


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

# Function to update the nodes 
func update_nodes_to_data_dictionary(data: Dictionary):

	var config: Dictionary
	var node_id: int
	var node: Node2D

	combinedshader.outputlog("update_nodes_to_data_dictionary: " + str(data),2)

	# For each entry in the history record
	for node_id_string in data.keys():
		# Get the node id from the string
		node_id = int(node_id_string.replace("node-id-",""))
		if Global.World.HasNodeID(node_id):
			node = Global.World.GetNodeByID(node_id)
			if node != null:
				config = data[node_id_string]
				# Set the colour of the node
				combinedshader.set_custom_attributes_on_node(node, config)
				
				# Set the path data for the node
				if config["type"] == "paths" && config.has("path_data"):
					set_path_values(node, config["path_data"])
				
				# Update the data
				customdatamanager.set_data(node_id, config)

func undo():

	combinedshader.outputlog("undo: " + str(previous_node_data),2)

	update_nodes_to_data_dictionary(previous_node_data)

func redo():

	combinedshader.outputlog("redo: " + str(new_node_data),2)

	update_nodes_to_data_dictionary(new_node_data)


