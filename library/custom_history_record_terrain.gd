extends Reference

# Custom History Record for terrain colours
# v1.0.0
var type = "terraincolours"
var level_node = null
var previous_terrain_data: Array
var new_terrain_data: Array
var colourterrain = null

# Logging functions
const ENABLE_LOGGING = true
const LOGGING_LEVEL = 0

func outputlog(msg,level=0):
	if ENABLE_LOGGING:
		if level <= LOGGING_LEVEL:
			printraw("(%d) <ColourTerrainHistory>: " % OS.get_ticks_msec())
			print(msg)
	else:
		pass

func update_terrain(data_list):

	# If the level node is valid
	if level_node in Global.World.levels:
		for index in 8:
			colourterrain.set_terrain_colour(index, data_list[index],false)
	
	colourterrain.refresh_terrain_ui_from_stored_values()

func undo():

	outputlog("undo: " + str(previous_terrain_data),2)
	update_terrain(previous_terrain_data)

func redo():

	outputlog("redo: " + str(new_terrain_data),2)
	update_terrain(new_terrain_data)



