extends MeshInstance

var last_click_time = 0.0
var double_click_threshold = 0.3  # Reduced threshold to make double-click more responsive
var original_material : Material = null  # To store the original material

# Called when the node is added to the scene
func _ready():
	pass
	
func _process(delta):
	setsize()

func setsize():
	# Ensure the node has a parent
	if get_parent():
		# Get the parent's Z scale
		var parent_z_scale = get_parent().transform.basis.get_scale().z

		# Access the existing material of the mesh
		var material = get_surface_material(0) as SpatialMaterial

		if material:
			# Adjust the UV scale's Y axis based on the parent's Z scale
			var current_uv_scale = material.uv1_scale
			material.uv1_scale = Vector3(current_uv_scale.x, parent_z_scale, current_uv_scale.z)


func _on_Area_input_event(camera, event, position, normal, shape_idx):
	if get_tree().root.get_node("game").get("toolactive"):
		get_tree().root.get_node("game").call("expand_water")
		if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and event.is_pressed():	
			var current_time = OS.get_ticks_msec() / 1000.0  # Get time in seconds
			if current_time - last_click_time <= double_click_threshold:
				self.get_parent().get_parent().get_node("RemoveP").play()
				get_parent().queue_free()  # Remove the parent node
				get_tree().root.get_node("game").call("send_websocket_message",{
					"action": "remove_part",
					"position": self.get_parent().translation
				})
			# Update the last click time
			last_click_time = current_time
			
# Handle mouse entering the area (hovering)
func _on_Area_mouse_entered():
	# Check if toolactive is true before applying the outline
	if get_tree().root.get_node("game").get("toolactive"):
		original_material = get_surface_material(0)
		var outline_material = original_material.duplicate() as SpatialMaterial
		outline_material.emission_enabled = true
		outline_material.emission = Color(1, 0, 0)  # Set to red
		outline_material.emission_energy = 1.0
		set_surface_material(0, outline_material)

# Handle mouse exiting the area (stopping hover)
func _on_Area_mouse_exited():
	# Reset to original material
	if original_material:
		set_surface_material(0, original_material)
