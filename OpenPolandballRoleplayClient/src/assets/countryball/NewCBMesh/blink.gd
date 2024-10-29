extends Spatial

# Meshes for open and blinking eye states.
var open_eye_mesh : ArrayMesh
var blinking_eye_mesh : ArrayMesh
var open_eye_happy : ArrayMesh
var open_eye_sad : ArrayMesh
var open_eye_angry : ArrayMesh
# Node path for the MeshInstance you want to change the mesh of.
var target_node_path = "Armature002/Skeleton3/Cube002"
var target_mesh : MeshInstance

# Blinking control variables.
var blink_interval = 1.0 # Time in seconds between blinks.
var time_since_last_blink = 0.0
var is_eye_open = true

# Called when the node enters the scene tree for the first time.
func _ready():
	target_mesh = get_node(target_node_path) as MeshInstance

	# Load the mesh resources
	open_eye_mesh = load("res://src/assets/countryball/emotions/OpenEye.tres") as ArrayMesh
	open_eye_happy = load("res://src/assets/countryball/emotions/HappyEye.tres") as ArrayMesh
	open_eye_angry= load("res://src/assets/countryball/emotions/AngryEye.tres") as ArrayMesh
	open_eye_sad = load("res://src/assets/countryball/emotions/SadEye.tres") as ArrayMesh
	blinking_eye_mesh = load("res://src/assets/countryball/emotions/BlinkingEye.tres") as ArrayMesh

	# Check if meshes were loaded successfully
	if open_eye_mesh == null or blinking_eye_mesh == null:
		printerr("Failed to load meshes. Please check the paths.")
		return

	# Initially set to open eye mesh.
	target_mesh.mesh = open_eye_mesh

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	time_since_last_blink += delta

	if time_since_last_blink >= blink_interval:
		# Reset timer
		time_since_last_blink = 0.0

		# Toggle eye state
		if is_eye_open:
			target_mesh.mesh = blinking_eye_mesh
			is_eye_open = false
		else:
			if get_parent().get_parent().get("current_emotion") == "happy":
				target_mesh.mesh = open_eye_happy
			elif get_parent().get_parent().get("current_emotion") == "angry":
				target_mesh.mesh = open_eye_angry
			elif get_parent().get_parent().get("current_emotion") == "sad":
				target_mesh.mesh = open_eye_sad
			else:
				target_mesh.mesh = open_eye_mesh
			is_eye_open = true
