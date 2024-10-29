extends Node

# WebSocket Client for server communication
var websocket : WebSocketClient
var mapname = "mapparts"
# Paths to essential nodes
var workspace
var players
var namee
var ingamehour = 0.0
var baseNightSkyRotation = Basis(Vector3(1.0, 1.0, 1.0).normalized(), 1.2)
var horizontalAngle = 25.0
var timeset = false
var chat_cooldown = 1.0
var can_send_chat = true
var newuser = false
var toolactive = false
var map_value
var heightmap
var timegame = 14
var grid_size = 36
var max_height = 24
const PLAYER_SCENE = preload("res://src/assets/countryball/Debug.tscn")
var prevcam
var timeval
var logon = false
# Track placed parts to prevent duplicates
var placed_parts = {}
var received_pck_files = {}  # Dictionary to store received chunks
var chunked_files = {}  # Tracks the chunks of each file
# Called when the node enters the scene tree for the first time.
func _ready():
	self.get_node("LoadingCamera").visible = true
	self.get_node("LoadingCamera").current = true
	ingamehour = timegame
	workspace = get_node("Workspace")
	players = get_node("Players")
	
	# Remove the immediate server connection
	if s1sd.get("mapload"):
		map_value = s1sd.get("mapload")
		maploader()
	else:
		# Instead of connecting, show the login UI
		show_login_ui()
	
func get_trt_time_as_number_with_dots() -> float:
	# Get the current Unix timestamp
	var current_timestamp = OS.get_unix_time()
	
	# Convert it to UTC+3 (TRT) (Currently not implemented)
	var trt_time = current_timestamp
	
	# Get the hour and minute
	var hour = int(OS.get_datetime_from_unix_time(trt_time).hour)
	var minute = int(OS.get_datetime_from_unix_time(trt_time).minute)
	
	# Convert minute to a fractional part
	var minute_fraction = float(minute) / 60.0
	
	# Combine hour and minute_fraction
	var time_as_number_with_dots = hour + minute_fraction
	
	# Debug Only
	#var time_as_number_with_dots = 14
	
	# For Player Character
	timeval = time_as_number_with_dots
	
	return time_as_number_with_dots
	
func update_position_bug():
	for player in players.get_children():
		var new_position = player.global_transform.origin
		new_position.x = 1
		player.global_transform.origin = new_position

func connecttoserver():
	# Initialize WebSocket connection
	websocket = WebSocketClient.new()
	websocket.connect("connection_established", self, "_on_websocket_connected")
	websocket.connect("data_received", self, "_on_websocket_data_received")
	websocket.connect("connection_closed", self, "_on_websocket_disconnected")
	#var sslcer = load("res://CERTHERE.crt") as X509Certificate
	#websocket.set_trusted_ssl_certificate(sslcer)
	websocket.verify_ssl = false
	websocket.connect_to_url("wss://yourdomain.com:8765") ##Please change this.
	
func heightmapgemerator():
		# Load the heightmap image directly as an Image
		heightmap = Image.new()
		heightmap.load("res://Maps/Example.png")
		heightmap.lock()  # Lock the image for reading

		# Generate the landscape
		generate_landscape()
		
		# Unlock the image after use
		heightmap.unlock()
	
func _on_websocket_connected(protocols):
	print("Connected to WebSocket server")

	# Fetch the username and send join message
	var s1sd = get_node("/root/s1sd")
	var username = str(s1sd.get("username"))
	var password = str(s1sd.get("password"))
	var country = str(s1sd.get("country"))
	if s1sd.commandtosend != null:
		newuser = true
		send_websocket_message(s1sd.commandtosend)
		print(s1sd.commandtosend)
		s1sd.commandtosend = null
		self.get_tree().reload_current_scene()
	else:	
		send_websocket_message({
			"action": "join",
			"username": username,
			"password": password,
			"country": country
		})

func _on_websocket_data_received():
	var message = websocket.get_peer(1).get_packet().get_string_from_utf8()
	_process_incoming_message(message)

func _on_websocket_disconnected(code, reason, was_clean):
	print("Disconnected from WebSocket server")

func _process(delta):
	if timeset:
		pass
	else:
		updatetime(get_trt_time_as_number_with_dots())
	if websocket:
		websocket.poll()
	# Cooldown timer update
	if not can_send_chat:
		chat_cooldown -= delta
		if chat_cooldown <= 0:
			can_send_chat = true
			chat_cooldown = 1.0

func _input(event):
	# Detect if the "send_chat" action is pressed (which you've mapped to Enter key)
	if event.is_action_pressed("send_chat"):
		var line_edit = get_node("PlayerGUI/LineEdit")
		var message = line_edit.text.strip_edges() # Remove leading/trailing spaces
		if message != "":
			_on_chat_message_entered(message)
			line_edit.clear() # Clear the input field
			line_edit.release_focus()

func _on_chat_message_entered(message):
	if can_send_chat:
		send_chat_message(message)
		can_send_chat = false

func send_chat_message(message):
	var username = get_node("/root/s1sd").get("username")
	send_websocket_message({"action": "send_chat", "username": username, "message": message})

func display_chat_message(username, message):
	# Update the global chat display
	var vbox = get_node("PlayerGUI/ColorRect/ScrollContainer/VBoxContainer")
	var example_label = vbox.get_node("ExampleLabel")

	var new_label = example_label.duplicate()
	new_label.text = username + ":" + message
	new_label.visible = true

	vbox.add_child(new_label)

	# Update the specific player's chat bubble
	if players.has_node(username):
		
		var player_instance = players.get_node(username)
		var chat_label = player_instance.get_node("Pivot/ChatBox/Viewport/Label")
		chat_label.text = message

		var chat_box = player_instance.get_node("Pivot/ChatBox")
		chat_box.visible = true
		
		if message == "!noclip":
			if player_instance.get("noclipMode") == false:
				player_instance.enable_noclip()
			else:
				player_instance.disable_noclip()

		# Hide the chat box after 10 seconds
		var timer = Timer.new()
		timer.wait_time = 10.0
		timer.one_shot = true
		timer.connect("timeout", chat_box, "hide")
		player_instance.add_child(timer)
		timer.start()

func _process_incoming_message(message):
	var data = JSON.parse(message).result
	if data.has("action"):
		match data["action"]:
			"auth_success":
				print("Authentication successful")
				# Request all existing players' states from the server
				send_websocket_message({"action": "request_all_players"})
				# Request all placed parts from the server
				send_websocket_message({"action": "request_parts"})
				# Initialize the rest of the game environment
				get_node("Sky_texture").call("set_time_of_day", ingamehour, get_node("DirectionalLight"), deg2rad(horizontalAngle))
				
				# Rotate our night sky so our milkyway isn't on our horizon
				_set_sky_rotation()
				
			"auth_failed":
				print("Authentication failed: %s" % data.get("reason"))
			"player_joined":
				handle_player_joined(data["player"])
				send_flag_to_all_players()
			"player_left":
				handle_player_left(data["username"])
			"update_remote_player":
				update_remote_player(data["username"], parse_transform_string(data["transform"]), parse_vector3(data["InputVector"]), data["rotation"])
				apply_emotion(data["username"], data["emotion"])
				apply_hat(data["username"], data["accessories"])
			"receive_flag":
				apply_flag(data["username"], data["flag_data"])
			"all_players":
				handle_all_players(data["players"])
			"receive_chat":
				display_chat_message(data["username"], data["message"])
			"place_part_confirmation":
				handle_part_placement_confirmation(data)
			"remove_part_confirmation":
				handle_remove_part_confirmation(data)
			"receive_pck_name":
				receive_pck_complete(data["file_name"])

func receive_pck_complete(file_name):
	var path = "user://" + file_name
	namee = file_name
	var file = File.new()
	load_tscn_files_from_pck(file_name)

func maploader():
	print("loading map")
	# Add this code within the _ready() function or as appropriate
	var pck_path = "user://" + map_value + ".pck"
	var tscn_path = "res://DynamicMaps/" + map_value + "/Main.tscn"

	if File.new().file_exists(pck_path):
		print("Map Found")
		if ProjectSettings.load_resource_pack(pck_path):
			var scene = ResourceLoader.load(tscn_path)
			if scene:
				var instance = scene.instance()
				get_node("Workspace").add_child(instance)
				print("Successfully added map to workspace")
			else:
				print("Failed to load scene at %s" % tscn_path)
		else:
			print("Failed to load resource pack: %s" % pck_path)
		connecttoserver()
	else:
		print("Request taken")
		var http_request = HTTPRequest.new()
		add_child(http_request)
		http_request.download_file = pck_path
		http_request.connect("request_completed", self, "_on_request_completed")
		var error = http_request.request("https://polandballroleplay.com/Haritalar/" + map_value + ".pck")
		if error != OK:
			print("Failed to initiate HTTP request. Error: %d" % error)
			
# This function is called when the HTTP request is completed
func _on_request_completed(result, response_code, headers, body):
	if response_code == 200:
		var pck_name = map_value + ".pck"
		var save_path = "user://" + pck_name
		
		# Save the received data to a file
		var file = File.new()
		if file.open(save_path, File.WRITE) == OK:
			file.store_buffer(body)
			file.close()
			print("Saved PCK file to: %s" % save_path)
			
			# Load the PCK file after saving
			if ProjectSettings.load_resource_pack(save_path):
				print("Successfully loaded resource pack: %s" % pck_name)
				load_tscn_files_from_pck(pck_name)
			else:
				print("Failed to load resource pack: %s" % pck_name)
		else:
			print("Failed to save PCK file: %s" % save_path)
	else:
		# Handle error
		print("Failed to retrieve PCK name. Response code: %d" % response_code)
	connecttoserver()


# Function to load the TSCN files from the PCK
func load_tscn_files_from_pck(pck_name):
	var path = "res://DynamicMaps/" + pck_name.replace(".pck", "") + ".tscn"
	print('Generated path: %s' % path)
	
	# Check if the file exists
	var file_exists = ResourceLoader.exists(path)
	print('File exists: %s' % file_exists)
	
	# Attempt to load the scene
	var scene = load(path)
	if scene:
		var instance = scene.instance()
		get_node("Workspace").add_child(instance)
		print("Successfully added %s to workspace" % pck_name)
	else:
		print("Failed to load scene at %s" % path)


func handle_player_joined(player_data):
	var username = player_data["username"]
	if not players.has_node(username):
		if newuser:
			pass
		else:
			var player_instance = PLAYER_SCENE.instance()
			player_instance.name = username
			player_instance.username = username
			# Set the player's username label
			var username_label = player_instance.get_node("Pivot/PlayerName/Viewport/Label")
			username_label.text = username

			# Debugging: Print the transform string
			print("Received transform string for player '%s': %s" % [username, player_data["transform"]])

			# Parse the transform and apply it
			var parsed_transform = parse_transform_string(player_data["transform"])
			if parsed_transform:
				player_instance.transform = parsed_transform
			else:
				print("Failed to parse transform for player '%s'." % username)

			players.add_child(player_instance)

			# Apply the flag for the new player
			apply_flag(username, player_data.get("flag_data", ""))
		newuser = false

func handle_all_players(players_data):
	for player_data in players_data:
		handle_player_joined(player_data)

	# Ensure all flags are applied for existing players
	send_flag_to_all_players()

func handle_player_left(username):
	if players.has_node(username):
		players.get_node(username).queue_free()

func update_remote_player(username, tr, input_vector, rotation):
	if players.has_node(username):
		var player = players.get_node(username)
		player.update_player(tr, input_vector, rotation)

func apply_flag(username, flag_data):
	if players.has_node(username):
		var player = players.get_node(username)
		player.apply_flag(flag_data)
		
func apply_emotion(username, emotiondata):
	if players.has_node(username):
		var player = players.get_node(username)
		player.set("current_emotion", emotiondata)
		
func apply_hat(username, hatdata):
	if players.has_node(username):
		var player = players.get_node(username)
		player.apply_accessories(hatdata)

func send_flag_to_all_players():
	var s1sd = get_node("/root/s1sd")
	var flag_data = s1sd.get("country")
	for player_name in players.get_children():
		send_websocket_message({
			"action": "send_flag",
			"username": player_name.name,
			"flag_data": flag_data
		})

func send_websocket_message(message):
	if websocket.get_connection_status() == WebSocketClient.CONNECTION_CONNECTED:
		websocket.get_peer(1).put_packet(to_json(message).to_utf8())

func parse_transform_string(transform_string):
	var transform_values = transform_string.split(" - ")
	if transform_values.size() != 2:
		print("Error: Incorrect format, expected 2 parts separated by ' - '")
		return null
	
	var basis_values = transform_values[0].split(", ")
	var origin_values = transform_values[1].split(", ")
	
	if basis_values.size() != 9:
		print("Error: Incorrect basis format, expected 9 values")
		return null
	
	if origin_values.size() != 3:
		print("Error: Incorrect origin format, expected 3 values")
		return null
	
	var basis = Basis(
		Vector3(basis_values[0].to_float(), basis_values[1].to_float(), basis_values[2].to_float()),
		Vector3(basis_values[3].to_float(), basis_values[4].to_float(), basis_values[5].to_float()),
		Vector3(basis_values[6].to_float(), basis_values[7].to_float(), basis_values[8].to_float())
	)
	
	var origin = Vector3(
		origin_values[0].to_float(),
		origin_values[1].to_float(),
		origin_values[2].to_float()
	)
	return Transform(basis, origin)

func parse_vector3(vector_string):
	# Assume vector_string is in the format "(x, y, z)"
	var values = vector_string.strip_edges("()").split(", ")
	if values.size() == 3:
		return Vector3(values[0].to_float(), values[1].to_float(), values[2].to_float())
	else:
		return Vector3()  # Return a default Vector3 if parsing fails

func handle_part_placement_confirmation(part_data):
	# Prevent duplicates by checking against already placed parts
	var part_key = generate_part_key(part_data)
	if not placed_parts.has(part_key):
		placed_parts[part_key] = true
		workspace.get_parent().get_node("PlayerGUI/Backpack/BuildTools").place_part_on_confirmation(part_data)

func handle_remove_part_confirmation(part_data):
	var part_key = generate_part_key(part_data)
	
	# Iterate through all children in the workspace
	for child in get_node("Workspace").get_children():
		# Check if the child's position matches the part_key position
		if child is Spatial:
			# Check if the child's position matches the part_key position
			if str(child.transform.origin) == part_key:
				# Remove the matching child node
				child.queue_free()

func generate_landscape():
	# Preload the block scene to reuse instances
	var block_scene = load("res://salih1Blox/assets/Block.tscn")
	var water_scene = load("res://salih1Blox/assets/BlockN.tscn")
	var cell_width = 3.0  # Width of the grid cell
	var cell_height = 3.0  # Height of the grid cell
	var grid_offset = Vector3(-grid_size / 2 * cell_width, 0, -grid_size / 2 * cell_width)  # Center on (0,0,0)
	var colors = {
		"grass": Color("4b974b"),
		"rock": Color("635f62"),
		"sand": Color("fdea8d"),
		"soil": Color("a05f35"),
		"water": Color("2154b9"),
		"blackish": Color("1a1a1a")
	}
	
	# Precompute positions and heights
	var positions = []
	for x in range(grid_size):
		for z in range(grid_size):
			var height = get_height_from_heightmap(x, z, max_height)
			positions.append({ "x": x, "z": z, "height": height })

	# Batch process terrain generation
	for pos in positions:
		var x = pos["x"]
		var z = pos["z"]
		var height = pos["height"]

		for y in range(int(height) + 1):  # Add +1 to include the topmost part
			var grid_position = Vector3(x * cell_width, y * cell_height, z * cell_width) + grid_offset
			var snapped_position = snap_to_grid(grid_position, cell_width, cell_height)

			# Reuse instances
			var part_instance = block_scene.instance()
			part_instance.transform.origin = snapped_position

			# Assign color based on height for realistic terrain
			var predefined_color
			if y == 0:
				predefined_color = colors["blackish"]
			elif y < 1:
				predefined_color = colors["soil"]
			elif y < 2:
				predefined_color = colors["sand"]
			elif y < 3:
				predefined_color = colors["grass"]
			else:
				predefined_color = colors["rock"]
			
			color_part(part_instance, predefined_color)
			workspace.add_child(part_instance, false)  # Use `false` to avoid immediate scene update

		# Fill empty spaces below height 2 with water
		if height < 2:
			for water_level in range(int(height) + 1, 2):  # Fill up to height 2
				var water_position = Vector3(x * cell_width, water_level * cell_height, z * cell_width) + grid_offset
				var water_instance = water_scene.instance()
				water_instance.transform.origin = snap_to_grid(water_position, cell_width, cell_height)
				
				# Color the water block
				color_part(water_instance, colors["water"])

				workspace.add_child(water_instance, false)

	# Defer the scene update until all nodes are added
	workspace.call_deferred("propagate_call", "queue_sort")


func expand_water():
	var directions = [
		Vector3(1, 0, 0),  # Right
		Vector3(-1, 0, 0),  # Left
		Vector3(0, 0, 1),  # Forward
		Vector3(0, 0, -1)  # Backward
	]
	
	for child in workspace.get_children():
		# Check if the block is a water block by checking its color or source scene
		if is_water_block(child):
			var water_position = child.transform.origin
			for direction in directions:
				var neighbor_position = water_position + direction * 3  # Move to the neighboring grid position

				# Check if the neighbor_position is within grid boundaries
				if is_within_grid_bounds(neighbor_position, 3):
					if not position_occupied(neighbor_position):  # Check if the neighboring position is not occupied
						var new_water_instance = load("res://salih1Blox/assets/BlockN.tscn").instance()
						new_water_instance.transform.origin = snap_to_grid(neighbor_position, 3.0, 3.0)
						
						# Color the water block
						color_part(new_water_instance, Color("2154b9"))

						workspace.add_child(new_water_instance)

func position_occupied(position: Vector3) -> bool:
	for child in workspace.get_children():
		# Check if the child is a Spatial node
		if child is Spatial:
			if child.transform.origin == position:
				return true
	return false

# Function to determine if a block is a water block based on color or source scene
func is_water_block(block) -> bool:
	# Alternatively, you can check if the block was instantiated from the water block scene
	return block.filename == "res://salih1Blox/assets/BlockN.tscn"

	return false

# Function to check if a position is within the grid boundaries
func is_within_grid_bounds(position: Vector3, cell_size: float) -> bool:
	var grid_size = 10  # Adjust this value to your actual grid size

	# Calculate the grid limits based on cell size
	var min_x = -grid_size / 2 * cell_size
	var max_x = grid_size / 2 * cell_size
	var min_z = -grid_size / 2 * cell_size
	var max_z = grid_size / 2 * cell_size

	return position.x >= min_x and position.x < max_x and position.z >= min_z and position.z < max_z

func snap_to_grid(position: Vector3, cell_width: float, cell_height: float) -> Vector3:
	return Vector3(
		round(position.x / cell_width) * cell_width,
		round(position.y / cell_height) * cell_height,
		round(position.z / cell_width) * cell_width
	)

func get_height_from_heightmap(x: int, z: int, max_height: float) -> float:
	# Normalize x and z to the heightmap dimensions
	var img_x = int((float(x) / grid_size) * heightmap.get_width())
	var img_z = int((float(z) / grid_size) * heightmap.get_height())

	# Get the pixel value at (img_x, img_z)
	var pixel_value = heightmap.get_pixel(img_x, img_z).r  # Assuming a grayscale image, use the red channel

	# Calculate height based on pixel value
	return pixel_value * max_height

func color_part(part_instance, predefined_color):
	if part_instance:
		var mesh_instance = part_instance.get_node("MeshInstance")
		if mesh_instance:
			var material = SpatialMaterial.new()
			material.albedo_color = predefined_color
			mesh_instance.material_override = material


func generate_part_key(part_data) -> String:
	print(part_data)
	var key = part_data["position"]
	if part_data.has("rotation"):
		key += "|" + str(part_data["rotation"])
	if part_data.has("scale"):
		key += "|" + str(part_data["scale"])
	if part_data.has("color"):
		key += "|" + str(part_data["color"])
	if part_data.has("typepart"):
		key += "|" + str(part_data["typepart"])
	return key

func _set_sky_rotation():
	var rot = Basis(Vector3(0.0, 1.0, 0.0), deg2rad(horizontalAngle)) * Basis(Vector3(1.0, 0.0, 0.0), (ingamehour * PI / 12.0))
	rot *= baseNightSkyRotation
	get_node("Sky_texture").call("set_rotate_night_sky", rot)

func _on_Sky_texture_sky_updated():
	var skyTextureViewport = get_node("Sky_texture") as Viewport
	if skyTextureViewport == null:
		print("Error: Sky_texture Viewport not found.")
		return
	
	var mainViewport = get_viewport()
	if mainViewport == null:
		print("Error: Main Viewport is null.")
		return
	
	var camera = mainViewport.get_camera()
	if camera == null:
		print("Error: Camera not found in main viewport.")
		return
	
	var environment = camera.environment
	if environment == null:
		print("Error: Camera environment is null.")
		return
	
	skyTextureViewport.call("copy_to_environment", environment)

func updatetime(hour: float):
	if logon == true:
		ingamehour = hour
		var animPlayer = get_node("AnimationPlayer")
		animPlayer.set_current_animation("ShadersNew")
		
		if animPlayer.current_animation_position >= ingamehour:
			timeset = true
			animPlayer.stop(false)
			prevcam.current = true
			$LoadingUI.visible = false
			$PlayerGUI.visible = true
		else:
			animPlayer.play("ShadersNew")
			
		get_node("Sky_texture").call("set_time_of_day", ingamehour, get_node("DirectionalLight"), deg2rad(horizontalAngle))
		_set_sky_rotation()
		self.get_node("LoadingCamera").visible = false

		var directionallight = get_node("DirectionalLight")
		var directionallightnight = get_node("DirectionalLightNight")
		if ingamehour >= 19 or ingamehour < 6:
			directionallight.visible = false
			directionallightnight.visible = true
		elif ingamehour >= 5 and ingamehour < 20:
			directionallight.visible = true
			directionallightnight.visible = false
		else:
			directionallight.visible = false
			directionallightnight.visible = false
	else:
		ingamehour = hour
		var animPlayer = get_node("AnimationPlayer")
		animPlayer.set_current_animation("ShadersNew")
		
		if animPlayer.current_animation_position >= ingamehour - 1:
			animPlayer.stop(false)
		else:
			_on_Sky_texture_sky_updated()
			animPlayer.play("ShadersNew")
			
		get_node("Sky_texture").call("set_time_of_day", animPlayer.current_animation_position, get_node("DirectionalLight"), deg2rad(horizontalAngle))
		_set_sky_rotation()

		var directionallight = get_node("DirectionalLight")
		var directionallightnight = get_node("DirectionalLightNight")
		if ingamehour >= 19 or ingamehour < 6:
			directionallight.visible = false
			directionallightnight.visible = true
		elif ingamehour >= 5 and ingamehour < 20:
			directionallight.visible = true
			directionallightnight.visible = false
		else:
			directionallight.visible = false
			directionallightnight.visible = false


# Save the map if owned by the player
func _on_Button_pressed():
	# Iterate through all parts in the workspace
	for part in workspace.get_children():
		if part is Spatial:  # Ensure the part is a Spatial node
			var part_data = {
				"position": part.transform.origin,
				"rotation": part.transform.basis.get_euler(),  # Use get_euler() for rotation in Euler angles
				"scale": part.transform.basis.get_scale(),
				"typepart": part.filename
			}

			# Retrieve the color of the part
			var color_str = ""
			var mesh_instance = part.get_node("MeshInstance")
			if mesh_instance:
				var material = mesh_instance.material_override as SpatialMaterial
				if material:
					color_str = str(material.albedo_color)  # Convert the color to a string
			print(part_data)
			# Send the data for this part
			send_websocket_message({
				"action": "place_part",
				"position": str(part_data["position"]),
				"rotation": str(part_data["rotation"]),
				"scale": str(part_data["scale"]),
				"color": color_str,
				"typepart": str(part_data["typepart"])
			})

	# After sending all parts, proceed with saving the map
	send_websocket_message({
		"action": "save_map",
		"map_name": mapname,
		"username": s1sd.username
	})

func _on_TextureButton_pressed():
	var line_edit = get_node("PlayerGUI/LineEdit")
	var message = line_edit.text.strip_edges() # Remove leading/trailing spaces
	if message != "":
		_on_chat_message_entered(message)
		line_edit.clear() # Clear the input field
		line_edit.release_focus()


func _on_TextureButton2_pressed():
	get_node("PlayerGUI/ColorRect").visible = !get_node("PlayerGUI/ColorRect").visible


func _on_TextureButton3_pressed():
	get_node("PlayerGUI/ColorRect3").visible = !get_node("PlayerGUI/ColorRect3").visible


func _on_TextureButton5_pressed():
	self.get_node("PlayerGUI/TextureRect/EmotionWheel").visible = !self.get_node("PlayerGUI/TextureRect/EmotionWheel").visible

func _on_TextureButton4_pressed():
	get_node("PlayerGUI/ColorRect4").visible = !get_node("PlayerGUI/ColorRect4").visible

func _on_Neutral_pressed():
	if players.has_node(s1sd.username):
		players.get_node(s1sd.username).set("current_emotion", "neutral")

func _on_Happy_pressed():
	if players.has_node(s1sd.username):
		players.get_node(s1sd.username).set("current_emotion", "happy")


func _on_Sad_pressed():
	if players.has_node(s1sd.username):
		players.get_node(s1sd.username).set("current_emotion", "sad")


func _on_Angry_pressed():
	if players.has_node(s1sd.username):
		players.get_node(s1sd.username).set("current_emotion", "angry")

# New function to show login UI
func show_login_ui():
	$LoginUI.visible = true
	$PlayerGUI.visible = false

# New function to handle the Play button press
func _on_PlayButton_pressed():
	logon = true
	var username_field = $LoginUI/UsernameInput
	var password_field = $LoginUI/PasswordInput
	var country_field = $LoginUI/CountryInput

	if username_field.text.strip_edges() != "" and password_field.text.strip_edges() != "":
		# Update s1sd with the credentials
		var s1sd = get_node("/root/s1sd")
		s1sd.set_player_name(username_field.text.strip_edges())
		s1sd.set_password(password_field.text.strip_edges())
		s1sd.set_country(country_field.text.strip_edges())
		
		# Hide login UI
		$LoginUI.visible = false
		$LoadingUI.visible = true
		# Now connect to server
		updatetime(get_trt_time_as_number_with_dots())
		connecttoserver()
	else:
		# Show error message if fields are empty
		print("Please enter both username and password")
		# Optionally show this in the UI:
		# $LoginUI/ErrorLabel.text = "Please enter both username and password"
