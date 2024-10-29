extends KinematicBody

var username = ""
var InputVector = Vector3()
var Velocity = Vector3()
var VerticalVelocity = 0.0
var JumpMagnitude = 10.0
var Gravity = 85.0
var AngularAcceleration = 7
var noclipMode = false
var current_emotion = "neutral"
var animationPlayer
var current_accessories
var accessories_to_send
var prevaccessories

func _ready():
	animationPlayer = $AnimationPlayer

func _physics_process(delta):
	# Only process input for the local player
	if username == str(get_tree().root.get_node("s1sd").get("username")):
		self.get_tree().root.get_node("game").prevcam = $Camroot/h/v/ARVROrigin/ARVRCamera
		var HRot = $Camroot/h.global_transform.basis.get_euler().y
		InputVector = Vector3(
			Input.get_action_strength("right") - Input.get_action_strength("left"), 
			0, 
			Input.get_action_strength("down") - Input.get_action_strength("up")
		).rotated(Vector3.UP, HRot)

		if Input.is_action_pressed("down") or Input.is_action_pressed("up") or Input.is_action_pressed("left") or Input.is_action_pressed("right"):
			$Pivot.rotation.y = lerp_angle($Pivot.rotation.y, atan2(-InputVector.x, -InputVector.z), delta * AngularAcceleration)

		# Noclip mode movement (free movement without gravity or collision)
		if noclipMode:
			Velocity = InputVector
			# Free movement in the direction of the camera
			Velocity.y = Input.get_action_strength("noclip_up") - Input.get_action_strength("noclip_down")  # Allows vertical movement (e.g., noclip_up to ascend, noclip_down to descend)
			translate(Velocity * delta * 10)  # Adjust speed as needed

			# Play animations
			if InputVector == Vector3():
				animationPlayer.play("Idle")
			else:
				animationPlayer.play("Walk")
		else:
			# Regular movement with gravity
			Velocity = InputVector
			move_and_slide(Velocity + Vector3.UP * VerticalVelocity, Vector3.UP)

			if InputVector == Vector3():
				animationPlayer.play("Idle")
			else:
				animationPlayer.play("Walk")

			# Gravity handling
			if not is_on_floor():
				VerticalVelocity -= Gravity * delta
			else:
				VerticalVelocity = 0.0
			if is_on_floor() and Input.is_action_pressed("Jump"):
				VerticalVelocity = JumpMagnitude

		# Multiplayer sync - Send updates to the server
		if current_accessories != null:
			accessories_to_send = current_accessories.slice(0, 3)  # Limit to 3 accessories

		get_node("/root/game").send_websocket_message({
			"action": "update_player",
			"username": username,
			"transform": global_transform,
			"InputVector": InputVector,
			"rotation": {
				"x": $Pivot.rotation.x,
				"y": $Pivot.rotation.y,
				"z": $Pivot.rotation.z
			},
			"emotion": current_emotion,  # Pass the player's current emotion state
			"accessories": accessories_to_send  # Send the processed accessories
		})

func enable_noclip():
	noclipMode = true
	VerticalVelocity = 0.0  # Reset vertical velocity when entering noclip

func disable_noclip():
	noclipMode = false

func update_player(tr, input_vector, rotation):
	global_transform = tr
	$Pivot.rotation = Vector3(rotation["x"], rotation["y"], rotation["z"])
	InputVector = input_vector

	# Apply movement animations
	if InputVector == Vector3():
		animationPlayer.play("Idle")
	else:
		animationPlayer.play("Walk")

func apply_accessories(accessories):
	if accessories != prevaccessories:
		prevaccessories = accessories
		# Remove all existing accessories before applying new ones
		if self.get_node("Pivot/Accessory") != null:
			for child in self.get_node("Pivot/Accessory").get_children():
				child.queue_free()

		# Load and attach accessories based on the received names
		for accessory_name in accessories:
			var accessory_path = "res://src/assets/accessories/" + accessory_name + ".tscn"
			var accessory_scene = ResourceLoader.load(accessory_path)
			
			if accessory_scene:
				var accessory_instance = accessory_scene.instance()
				
				# Attach the accessory to the appropriate node (assuming $Accessories is a node under your player)
				self.get_node("Pivot/Accessory").add_child(accessory_instance)
				# Positioning logic (e.g., head, hand) can be applied here if necessary
				print("Accessory '%s' applied to player" % accessory_name)
			else:
				print("Failed to load accessory: %s" % accessory_name)


func apply_flag(flag_data):
	# Decode the base64 string to a PoolByteArray
	var byte_array = Marshalls.base64_to_raw(flag_data)

	# Load the flag texture from the received flag data
	var image = Image.new()
	var error = image.load_png_from_buffer(byte_array)
	
	if error != OK:
		print("Failed to load PNG from buffer with error code: ", error)
		return

	var texture = ImageTexture.new()
	texture.create_from_image(image)
	
	var original_mat = $Pivot/Skin/Armature/Skeleton/Cube.get_surface_material(0)
	if original_mat is SpatialMaterial:
		var new_mat = original_mat.duplicate()
		new_mat.albedo_texture = texture
		$Pivot/Skin/Armature/Skeleton/Cube.set_surface_material(0, new_mat)
