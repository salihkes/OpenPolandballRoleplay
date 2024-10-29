extends ScrollContainer

# Path to the node we're monitoring for changes
var players_path: NodePath = "root/game/Players"
var vbox_container: VBoxContainer = null
var example_label: Label = null

# Maximum size limits
var max_height = 600  # Adjust as needed
var max_width = 400  # Adjust as needed

func get_trt_time_as_number_with_dots() -> float:
	# Get the current Unix timestamp
	var current_timestamp = OS.get_unix_time()
	
	# Convert it to UTC+3 (TRT)
	var trt_time = current_timestamp + 3 * 3600
	
	# Get the hour and minute
	var hour = int(OS.get_datetime_from_unix_time(trt_time).hour)
	var minute = int(OS.get_datetime_from_unix_time(trt_time).minute)
	
	# Convert minute to a fractional part
	var minute_fraction = float(minute) / 60.0
	
	# Combine hour and minute_fraction
	var time_as_number_with_dots = hour + minute_fraction
	
	return time_as_number_with_dots


func _ready():
	# Get references to the VBoxContainer and ExampleLabel
	vbox_container = $VBoxContainer
	example_label = vbox_container.get_node("ExampleLabel")
	
	# Set ExampleLabel to invisible since we use it as a template
	example_label.visible = false
	# Start monitoring the Players node for changes
	var players_node = self.get_tree().root.get_node("game/Players")
	players_node.connect("tree_exiting", self, "_on_players_updated")
	players_node.connect("child_entered_tree", self, "_on_players_updated")
	players_node.connect("child_exiting_tree", self, "_on_players_updated")
	
	# Detect changes immediately when the script is loaded
	_on_players_updated()

# Called whenever a change is detected in the Players node
func _on_players_updated(_unused_arg = null):
	# Clear the VBoxContainer (except for the template label)
	for i in range(1, vbox_container.get_child_count()):
		vbox_container.get_child(i).queue_free()
	
	# Get the updated list of players
	if self.get_tree():
		var players_node = self.get_tree().root.get_node("game/Players")
		
		for player in players_node.get_children():
			# Duplicate the ExampleLabel
			var new_label = example_label.duplicate()
			
			# Set the label text to the player's name (or any other property)
			new_label.text = player.name
			
			# Determine the font color based on the character count using match
			var char_count = new_label.text.length()
			match char_count:
				1:
					new_label.modulate = Color(0.0, 0.0, 0.5)  # Dark blue
				2:
					new_label.modulate = Color(0.18, 0.65, 0.18)  # Light green
				3:
					new_label.modulate = Color(0.0, 0.39, 0.0)  # Dark green
				4:
					new_label.modulate = Color(0.0, 0.0, 1.0)  # Blue
				5:
					new_label.modulate = Color(0.0, 0.0, 0.75)  # Medium blue
				6:
					new_label.modulate = Color(0.13, 0.55, 0.13)
				7:
					new_label.modulate = Color(1.0, 0.65, 0.0)  # Orange
				8:
					new_label.modulate = Color(1.0, 0.55, 0.0)  # Darker orange
				9:
					new_label.modulate = Color(1.0, 0.45, 0.0)  # Deep orange
				10:
					new_label.modulate = Color(1.0, 1.0, 0.0)  # Yellow
				11:
					new_label.modulate = Color(0.85, 0.85, 0.0)  # Gold
				12:
					new_label.modulate = Color(1.0, 0.0, 0.0)  # Red
				_:
					new_label.modulate = Color(0.5, 0.5, 0.5)  # Gray (default)
			
			# Make the label visible
			new_label.visible = true
			
			# Add the label to the VBoxContainer
			vbox_container.add_child(new_label)
			
			# Resize the VBoxContainer and ScrollContainer
			_resize_container()

# Function to resize the VBoxContainer and ScrollContainer
func _resize_container():
	# Calculate the new size based on the number of children
	var new_height = vbox_container.get_minimum_size().y + vbox_container.get_child_count() * example_label.rect_min_size.y
	var new_width = max(vbox_container.get_minimum_size().x, example_label.rect_min_size.x)
	
	# Cap the size to prevent it from growing indefinitely
	if new_height > max_height:
		new_height = max_height
	if new_width > max_width:
		new_width = max_width
	
	# Apply the new size to VBoxContainer
	vbox_container.rect_min_size = Vector2(new_width, new_height)
	vbox_container.rect_size = Vector2(new_width, new_height)
	
	# Apply the new size to the ScrollContainer
	rect_min_size = Vector2(new_width, new_height)
	rect_size = Vector2(new_width, new_height)
