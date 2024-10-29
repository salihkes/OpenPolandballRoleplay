tool
extends Button

export(PackedScene) var part_scene : PackedScene
var preview_instance : Spatial
var is_active : bool = false
var grid_size : float = 1.0
var workspace : Node
var part_data = {
	"position": Vector3(),
	"rotation": Vector3(),
	"scale": Vector3(1, 1, 1),
	"color": "0, 0, 0",
	"typepart": ""
}
# Settings for scaling, rotation, and color
var min_scale_z : float = 1.0
var max_scale_z : float = 5.0
var rotation_step : float = 90.0
var current_rot : float = 0
var predefined_color : Color = Color(1, 0, 0)  # Red as an example

# Map to track parts in the current session to avoid duplicates
var placed_parts = {}

func _ready():
	workspace = self.get_tree().root.get_node("game/Workspace")
	connect("pressed", self, "_on_button_toggled")

	# Connect all TextureButtons within ColorRect4/GridContainer
	var grid_container = $ColorRect4/GridContainer
	for button in grid_container.get_children():
		if button is TextureButton:
			button.connect("pressed", self, "_on_TextureButton_pressed_new", [button])
			
var move_cooldown_time : float = 0.2  # Cooldown time in seconds
var last_move_time : float = 0  # Track the last movement time

func _unhandled_input(event: InputEvent):
	if is_active and event is InputEventKey:
		if OS.get_ticks_msec() - last_move_time > move_cooldown_time * 1000:
			if event.scancode in [KEY_0, KEY_0]:
				scale_part(Vector3(0, 0, 1))
			elif event.scancode in [KEY_1, KEY_1]:
				scale_part(Vector3(0, 0, -1))
			elif event.scancode == KEY_BACKSPACE:
				rotate_part()
			elif event.scancode == KEY_C:
				color_part()
			else:
				handle_grid_movement(event)
			last_move_time = OS.get_ticks_msec()


func _on_button_toggled():
	get_tree().root.get_node("game").set("toolactive", !get_tree().root.get_node("game").get("toolactive"))
	is_active = !is_active
	self.get_node("ColorRect4").visible =! self.get_node("ColorRect4").visible
	update_button_style()
	
	if is_active:
		create_preview_instance()
	else:
		if preview_instance:
			preview_instance.queue_free()

func update_button_style():
	var style_box = load("res://salih1Blox/Element.tres")
	if is_active:
		style_box.set_border_width_all(2)
		style_box.border_color = Color(0, 1, 0)  # Green outline when active
	else:
		style_box.set_border_width_all(0)  # No border when inactive

	add_stylebox_override("normal", style_box)
	add_stylebox_override("pressed", style_box)
	add_stylebox_override("hover", style_box)

func create_preview_instance():
	if part_scene:
		preview_instance = part_scene.instance()
		preview_instance.get_node("MeshInstance").material_override = create_transparent_material()
		workspace.add_child(preview_instance)

		# Perform the raycast to find the collision point
		var camera = workspace.get_viewport().get_camera()
		var ray_origin = camera.project_ray_origin(get_viewport().get_mouse_position())
		var ray_end = ray_origin + camera.project_ray_normal(get_viewport().get_mouse_position()) * 1000

		var space_state = workspace.get_world().direct_space_state
		var ray_result = space_state.intersect_ray(ray_origin, ray_end)
		print("Ray Result: ", ray_result)

		if ray_result:
			# Use global transform to correctly position the preview instance
			var global_position = ray_result.position
			preview_instance.global_transform.origin = global_position.snapped(Vector3(grid_size, grid_size, grid_size)) + Vector3(0, .05, 0)
			print("Snapped Position: ", preview_instance.global_transform.origin)
		else:
			# If no collision, place the preview at the origin, snapped to the grid
			preview_instance.global_transform.origin = Vector3.ZERO.snapped(Vector3(grid_size, grid_size, grid_size))




func create_transparent_material() -> SpatialMaterial:
	var material = SpatialMaterial.new()
	material.albedo_color = Color(1, 1, 1, 0.5)  # 128 transparency
	material.flags_transparent = true
	return material
	
func parse_vector3(vector_string: String) -> Vector3:
	# Check that the string starts with '(' and ends with ')'
	if not vector_string.begins_with("(") or not vector_string.ends_with(")"):
		print("Invalid format, returning default Vector3(1, 1, 1)")
		return Vector3(1, 1, 1)

	# Manually remove the leading '(' and trailing ')' characters
	var stripped_string = vector_string.substr(1, vector_string.length() - 2)
	
	# Now split the stripped string by commas, then strip extra spaces
	var values = stripped_string.split(",")
	
	if values.size() == 3:
		# Convert the parsed values to floats and create a Vector3
		return Vector3(values[0].strip_edges().to_float(), values[1].strip_edges().to_float(), values[2].strip_edges().to_float())
	else:
		print("Failed to parse vector, returning default Vector3(1, 1, 1)")
		return Vector3(1, 1, 1)  # Return a default Vector3 if parsing fails

func send_part_placement(part_data):
	var game = workspace.get_parent()
	var color_str = ""

	# Get the albedo color of the first material
	if preview_instance and preview_instance.has_node("MeshInstance"):
		var mesh_instance = preview_instance.get_node("MeshInstance")
		if mesh_instance.material_override:
			color_str = str(mesh_instance.material_override.albedo_color)
		elif mesh_instance.get_surface_material(0):
			color_str = str(mesh_instance.get_surface_material(0).albedo_color)

	game.send_websocket_message({
		"action": "place_part",
		"position": str(part_data["position"]),
		"rotation": str(part_data["rotation"]),
		"scale": str(part_data["scale"]),
		"color": color_str,
		"typepart": str(part_data["typepart"])
	})
	
func vector3_to_string(vector: Vector3) -> String:
	return "(" + str(vector.x) + ", " + str(vector.y) + ", " + str(vector.z) + ")"

func place_part_on_confirmation(part_data):
	if not is_duplicate(part_data):
		$AddP.play()
		if part_data.has("typepart"):
			var new_part = load(part_data["typepart"]).instance()
			new_part.translation = parse_vector3(part_data["position"])
			new_part.rotation_degrees = parse_vector3(part_data["rotation"])
			new_part.scale = parse_vector3(part_data["scale"])
			
			# Apply the color if it exists in the part_data
			if part_data.has("color") and new_part.has_node("MeshInstance"):
				var mesh_instance = new_part.get_node("MeshInstance")
				
				# Parse the color string into individual float components
				var color_values = part_data["color"].split(",")
				if color_values.size() == 4:
					var color = Color(color_values[0].to_float(), color_values[1].to_float(), color_values[2].to_float(), color_values[3].to_float())
					
					# Create a new material with the desired color
					var material = load("res://salih1Blox/brick.tres").duplicate()
					material.albedo_color = color
					
					# Apply this material to the MeshInstance
					mesh_instance.material_override = material
					mesh_instance.setsize()

			workspace.add_child(new_part)

			# Add to the placed parts map to avoid duplicates
			placed_parts[generate_part_key(part_data)] = true



func is_duplicate(part_data) -> bool:
	return placed_parts.has(generate_part_key(part_data))

func generate_part_key(part_data) -> String:
	var position_str = str(part_data["position"])
	var rotation_str =  str(part_data["rotation"])
	var scale_str =  str(part_data["scale"])
	var typepart_str =  str(part_data["typepart"])
	return position_str + "|" + rotation_str + "|" + scale_str

func scale_part(scale_change: Vector3):
	if preview_instance:
		var new_scale = preview_instance.scale + scale_change
		new_scale.z = clamp(new_scale.z, min_scale_z, max_scale_z)
		preview_instance.scale = new_scale

func rotate_part():
	if preview_instance:
		current_rot +=  rotation_step
		preview_instance.rotation_degrees.y += current_rot
		preview_instance.rotation_degrees.y = wrapf(preview_instance.rotation_degrees.y, 0, 360)

func color_part():
	if preview_instance:
		var mesh_instance = preview_instance.get_node("MeshInstance")
		if mesh_instance:
			var material = SpatialMaterial.new()
			material.albedo_color = predefined_color
			mesh_instance.material_override = material

func clamp(value: float, min_value: float, max_value: float) -> float:
	return min(max(value, min_value), max_value)

func handle_grid_movement(event: InputEventKey):
	var camera = workspace.get_viewport().get_camera()  # Assuming this gets the relevant camera
	var direction = Vector3()

	# Get the camera's forward (Z-axis) and right (X-axis) vectors, ignoring the Y component
	var forward = -camera.global_transform.basis.z
	forward.y = 0  # Zero out the Y component
	forward = forward.normalized()

	var right = camera.global_transform.basis.x
	right.y = 0  # Zero out the Y component
	right = right.normalized()

	if event.scancode == KEY_UP:
		direction += forward * grid_size
	elif event.scancode == KEY_DOWN:
		direction -= forward * grid_size
	elif event.scancode == KEY_LEFT:
		direction -= right * grid_size
	elif event.scancode == KEY_RIGHT:
		direction += right * grid_size
	elif event.scancode == KEY_PAGEUP:
		direction.y += grid_size  # Optional: adjust the Y axis
	elif event.scancode == KEY_PAGEDOWN:
		direction.y -= grid_size  # Optional: adjust the Y axis
	elif event.scancode == KEY_E:
		# Capture the position, rotation, and scale directly from the preview instance
		part_data["position"] = preview_instance.translation
		part_data["rotation"] = preview_instance.rotation_degrees
		part_data["scale"] = preview_instance.scale
		part_data["typepart"] = part_scene.resource_path
		# Get the color of the MeshInstance, leave old value if exists, otherwise default to (0, 0, 0)
		var color_str = part_data["color"]  # Retain old color by default
		if preview_instance and preview_instance.has_node("MeshInstance"):
			var mesh_instance = preview_instance.get_node("MeshInstance")
			if mesh_instance.material_override:
				color_str = str(mesh_instance.material_override.albedo_color)
			elif mesh_instance.get_surface_material(0):
				color_str = str(mesh_instance.get_surface_material(0).albedo_color)
		
		part_data["color"] = color_str
		
		# Send the updated part_data
		send_part_placement(part_data)

	move_preview_instance(direction)





func move_preview_instance(direction: Vector3):
	if preview_instance:
		var new_position = preview_instance.translation + direction
		new_position = new_position.snapped(Vector3(grid_size, grid_size, grid_size))
		preview_instance.translation = new_position



func _on_TextureButton_pressed():
	print("Depreached")

func _on_TextureButton_pressed_new(texture_button: TextureButton):
	if preview_instance and preview_instance.has_node("MeshInstance"):
		var mesh_instance = preview_instance.get_node("MeshInstance")
		
		# Get the modulate color from the passed TextureButton
		var new_color = texture_button.modulate
		print("New color selected:", new_color)

		if not mesh_instance.material_override or mesh_instance.material_override.albedo_color != new_color:
			if mesh_instance.material_override:
				mesh_instance.material_override.albedo_color = new_color
			elif mesh_instance.get_surface_material(0):
				var material = mesh_instance.get_surface_material(0)
				material.albedo_color = new_color
				mesh_instance.set_surface_material(0, material)

		# Update part_data with the new color
		part_data = {
			"position": preview_instance.translation,
			"rotation": preview_instance.rotation_degrees,
			"scale": preview_instance.scale,
			"color": new_color,
			"typepart": preview_instance.filename
		}

