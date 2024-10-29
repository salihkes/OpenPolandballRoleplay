# Main game controller script for OpenPolandballRoleplay
# 
# This script manages core game functionality including:
# - WebSocket client for multiplayer communication
# - Player management (joining, leaving, movement sync)
# - Map loading and terrain generation
# - Chat system
# - Day/night cycle and sky rendering
# - UI management (login, chat, emotions)
# - Part placement and map saving
#
# The script acts as the central hub connecting various game systems
# and handling network communication with the game server.

extends Node

# WebSocket Client for server communication
var websocket_client : WebSocketClient
var current_map_name = "mapparts"

# Resources
var terrain_generator: TerrainGenerator

# Paths to essential nodes
var workspace
var players
var recieved_pck_name
var current_time_hour = 0.0
var base_night_sky_rotation = Basis(Vector3(1.0, 1.0, 1.0).normalized(), 1.2)
var horizontal_angle = 25.0
var is_time_set = false
var chat_message_cooldown = 1.0
var is_chat_allowed = true
var is_new_player = false
var is_tool_active = false
var map_value
var time_game = 14
const GRID_SIZE = 36
const MAX_HEIGHT = 24

const PLAYER_SCENE = preload("res://src/assets/countryball/Debug.tscn")
var prev_cam
var time_val
var is_logged_in = false

# Track placed parts to prevent duplicates
var placed_parts = {}
var received_pck_files = {}  # Dictionary to store received chunks
var chunked_files = {}  # Tracks the chunks of each file

# Called when the node enters the scene tree for the first time.
func _ready():
	self.get_node("LoadingCamera").visible = true
	self.get_node("LoadingCamera").current = true
	current_time_hour = time_game
	workspace = get_node("Workspace")
	players = get_node("Players")

	# Remove the immediate server connection
	if s1sd.get("mapload"):
		map_value = s1sd.get("mapload")
		_load_map()
	_show_login_ui()

# Resouce Functions, you can use them as you need them.

func _generate_landscape():
	var block_scene = load("res://salih1Blox/assets/Block.tscn")
	var water_scene = load("res://salih1Blox/assets/BlockN.tscn")
	var heightmap_texture = load("res://path/to/your/heightmap.png") ##Modify this value please.
	var heightmap = heightmap_texture.get_data()
	terrain_generator = TerrainGenerator.new(workspace, block_scene, water_scene, heightmap)
	terrain_generator.generate()

# Utility Functions

func get_trt_time_as_number_with_dots() -> float:
	var current_timestamp = OS.get_unix_time()
	var trt_time = current_timestamp

	var hour = int(OS.get_datetime_from_unix_time(trt_time).hour)
	var minute = int(OS.get_datetime_from_unix_time(trt_time).minute)

	var minute_fraction = float(minute) / 60.0
	var time_as_number = hour + minute_fraction

	time_val = time_as_number
	return time_as_number


func update_position_bug():
	for player in players.get_children():
		var new_position = player.global_transform.origin
		new_position.x = 1
		player.global_transform.origin = new_position


# WebSocket Functions

func connect_to_server():
	websocket_client = WebSocketClient.new()
	websocket_client.connect("connection_established", self, "_on_websocket_connected")
	websocket_client.connect("data_received", self, "_on_websocket_data_received")
	websocket_client.connect("connection_closed", self, "_on_websocket_disconnected")
	websocket_client.verify_ssl = false
	websocket_client.connect_to_url("wss://skeskin.com:8765")  # Please change this

func _position_occupied(position: Vector3) -> bool:
	for child in workspace.get_children():
		if child is Spatial:
			if child.transform.origin == position:
				return true
	return false


func _is_within_grid_bounds(position: Vector3, cell_size: float) -> bool:
	var grid_size = 10

	var min_x = -grid_size / 2 * cell_size
	var max_x = grid_size / 2 * cell_size
	var min_z = -grid_size / 2 * cell_size
	var max_z = grid_size / 2 * cell_size

	return position.x >= min_x and position.x < max_x and position.z >= min_z and position.z < max_z

# Chat and Player Functions

func _on_websocket_connected(protocols):
	print("Connected to WebSocket server")

	var s1sd = get_node("/root/s1sd")
	var username = str(s1sd.get("username"))
	var password = str(s1sd.get("password"))
	var country = str(s1sd.get("country"))

	if s1sd.commandtosend != null:
		is_new_player = true
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
	var message = websocket_client.get_peer(1).get_packet().get_string_from_utf8()
	_process_incoming_message(message)


func _on_websocket_disconnected(code, reason, was_clean):
	print("Disconnected from WebSocket server")


func _process(delta):
	if is_time_set:
		pass
	else:
		_update_time(get_trt_time_as_number_with_dots())

	if websocket_client:
		websocket_client.poll()

	# Chat cooldown timer
	if not is_chat_allowed:
		chat_message_cooldown -= delta
		if chat_message_cooldown <= 0:
			is_chat_allowed = true
			chat_message_cooldown = 1.0


func _input(event):
	# Detect if the "send_chat" action is pressed
	if event.is_action_pressed("send_chat"):
		var line_edit = get_node("PlayerGUI/LineEdit")
		var message = line_edit.text.strip_edges()

		if message != "":
			_on_chat_message_entered(message)
			line_edit.clear()
			line_edit.release_focus()


func _on_chat_message_entered(message):
	if is_chat_allowed:
		_send_chat_message(message)
		is_chat_allowed = false


func _send_chat_message(message):
	var username = get_node("/root/s1sd").get("username")
	send_websocket_message({"action": "send_chat", "username": username, "message": message})


func _display_chat_message(username, message):
	var vbox = get_node("PlayerGUI/ColorRect/ScrollContainer/VBoxContainer")
	var example_label = vbox.get_node("ExampleLabel")

	var new_label = example_label.duplicate()
	new_label.text = username + ": " + message
	new_label.visible = true

	vbox.add_child(new_label)

	# Update specific player's chat bubble
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
	if not data.has("action"):
		return
		
	match data["action"]:
		"auth_success":
			_handle_auth_success()
		"auth_failed":
			_handle_auth_failed(
				data.get("reason")
			)
		"player_joined":
			_handle_player_joined(data["player"])
			_broadcast_flag_to_players()
		"player_left":
			_handle_player_left(data["username"])
		"update_remote_player":
			_handle_player_update(data)
			if data.has("accessories"):
				_apply_player_customization(
					data["username"],
					"",  # flag_data
					"",  # emotion
					data["accessories"]
				)
		"receive_flag":
			_handle_flag_update(data)
		"all_players":
			_handle_all_players(data["players"])
		"receive_chat":
			_display_chat_message(data["username"], data["message"])
		"place_part_confirmation":
			_handle_part_placement_confirmation(data)
		"remove_part_confirmation":
			_handle_remove_part_confirmation(data)

# New helper functions to break down the message handling
func _handle_auth_success():
	print("Authentication successful")
	send_websocket_message({"action": "request_all_players"})
	send_websocket_message({"action": "request_parts"})
	get_node("Sky_texture").call("set_time_of_day", 
		current_time_hour, 
		get_node("DirectionalLight"), 
		deg2rad(horizontal_angle)
	)
	_set_sky_rotation()

func _handle_auth_failed(reason):
	print("Authentication failed: %s" % reason)

func _handle_player_update(data):
	_update_remote_player(
		data["username"], 
		_parse_transform_string(data["transform"]), 
		_parse_vector3(data["InputVector"]), 
		data["rotation"]
	)
	_apply_player_customization(
		data["username"],
		"",  # flag_data not included in update
		data["emotion"],
		data.get("accessories", [])  # Get accessories array, default to empty array
	)

func _handle_flag_update(data):
	_apply_player_customization(
		data["username"],
		data["flag_data"],
		"",  # emotion not included
		[]   # accessories not included
	)

# Map and File Functions

func _load_map():
	get_node("Workspace/StaticBody").queue_free()
	print("Loading map")
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
	else:
		print("Request taken")
		var http_request = HTTPRequest.new()
		add_child(http_request)
		http_request.download_file = pck_path
		http_request.connect("request_completed", self, "_on_request_completed")
		var error = http_request.request("https://polandballroleplay.com/Haritalar/" + map_value + ".pck")
		if error != OK:
			print("Failed to initiate HTTP request. Error: %d" % error)


func _on_request_completed(result, response_code, headers, body):
	if response_code == 200:
		var pck_name = map_value + ".pck"
		var save_path = "user://" + pck_name

		var file = File.new()
		if file.open(save_path, File.WRITE) == OK:
			file.store_buffer(body)
			file.close()
			print("Saved PCK file to: %s" % save_path)

			if ProjectSettings.load_resource_pack(save_path):
				print("Successfully loaded resource pack: %s" % pck_name)
				_load_tscn_files_from_pck(pck_name)
			else:
				print("Failed to load resource pack: %s" % pck_name)
		else:
			print("Failed to save PCK file: %s" % save_path)
	connect_to_server()


func _load_tscn_files_from_pck(pck_name):
	var path = "res://DynamicMaps/" + pck_name.replace(".pck", "") + ".tscn"
	print('Generated path: %s' % path)

	var file_exists = ResourceLoader.exists(path)
	print('File exists: %s' % file_exists)

	var scene = load(path)
	if scene:
		var instance = scene.instance()
		get_node("Workspace").add_child(instance)
		print("Successfully added %s to workspace" % pck_name)
	else:
		print("Failed to load scene at %s" % path)

# Player Handling Functions

# Player management functions handle the creation, updating, and removal of
# remote players in the multiplayer environment.

func _handle_player_joined(player_data):
	var username = player_data["username"]
	
	if not players.has_node(username):
		if is_new_player:
			return
			
		var player_instance = PLAYER_SCENE.instance()
		player_instance.name = username
		player_instance.username = username
		
		# Set player identification
		var username_label = player_instance.get_node(
			"Pivot/PlayerName/Viewport/Label"
		)
		username_label.text = username
		
		# Apply transform if valid, otherwise use default
		var transform_str = player_data["transform"]
		var parsed_transform = _parse_transform_string(transform_str)
		if parsed_transform:
			player_instance.transform = parsed_transform
		else:
			push_warning(
				"Failed to parse transform for player '%s'" % username
			)
		
		players.add_child(player_instance)
		_apply_player_customization(
			username,
			player_data.get("flag_data", ""),
			"",  # emotion not included in join data
			[]  # accessories not included in join data
		)
		
	is_new_player = false


func _handle_player_left(username):
	if players.has_node(username):
		players.get_node(username).queue_free()


func _update_remote_player(username, transform, input_vec, rotation):
	var player = players.get_node(username)
	if player:
		player.update_player(transform, input_vec, rotation)


func _apply_player_customization(
	username: String, 
	flag_data: String, 
	emotion_data: String, 
	accessories: Array  # Changed from String to Array
) -> void:
	var player = players.get_node(username)
	if not player:
		return
		
	if flag_data:
		player.apply_flag(flag_data)
	if emotion_data:
		player.set("current_emotion", emotion_data)
	if accessories:
		player.apply_accessories(accessories)


func _handle_all_players(players_data):
	for player_data in players_data:
		_handle_player_joined(player_data)

	# Ensure all flags are applied for existing players
	_broadcast_flag_to_players()


func _broadcast_flag_to_players():
	var flag_data = get_node("/root/s1sd").get("country")
	
	for player in players.get_children():
		send_websocket_message({
			"action": "send_flag",
			"username": player.name,
			"flag_data": flag_data
		})


# Message and Transform Parsing Functions

func send_websocket_message(message):
	if websocket_client.get_connection_status() == WebSocketClient.CONNECTION_CONNECTED:
		websocket_client.get_peer(1).put_packet(to_json(message).to_utf8())


func _parse_transform_string(transform_string):
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


func _parse_vector3(vector_string):
	var values = vector_string.strip_edges("()").split(", ")

	if values.size() == 3:
		return Vector3(values[0].to_float(), values[1].to_float(), values[2].to_float())
	else:
		return Vector3()


# Part Placement Handling Functions

func _handle_part_placement_confirmation(part_data):
	var part_key = _generate_part_key(part_data)

	if not placed_parts.has(part_key):
		placed_parts[part_key] = true
		workspace.get_parent().get_node("PlayerGUI/Backpack/BuildTools").place_part_on_confirmation(part_data)


func _handle_remove_part_confirmation(part_data):
	var part_key = _generate_part_key(part_data)

	for child in get_node("Workspace").get_children():
		if child is Spatial:
			if str(child.transform.origin) == part_key:
				child.queue_free()


func _generate_part_key(part_data) -> String:
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


# Sky Rotation and Lighting Functions

func _set_sky_rotation():
	var rot = Basis(Vector3(0.0, 1.0, 0.0), deg2rad(horizontal_angle)) * Basis(Vector3(1.0, 0.0, 0.0), (current_time_hour * PI / 12.0))
	rot *= base_night_sky_rotation
	get_node("Sky_texture").call("set_rotate_night_sky", rot)


func _on_sky_texture_sky_updated():
	var sky_texture_viewport = get_node("Sky_texture") as Viewport

	if sky_texture_viewport == null:
		print("Error: Sky_texture Viewport not found.")
		return

	var main_viewport = get_viewport()
	if main_viewport == null:
		print("Error: Main Viewport is null.")
		return

	var camera = main_viewport.get_camera()
	if camera == null:
		print("Error: Camera not found in main viewport.")
		return

	var environment = camera.environment
	if environment == null:
		print("Error: Camera environment is null.")
		return

	sky_texture_viewport.call("copy_to_environment", environment)


func _update_time(hour: float):
	if is_logged_in == true:
		if prev_cam == null:
			return
			
		current_time_hour = hour
		var anim_player = get_node("AnimationPlayer")
		anim_player.set_current_animation("ShadersNew")

		if anim_player.current_animation_position >= current_time_hour:
			is_time_set = true
			anim_player.stop(false)
			
			prev_cam.current = true
			$LoadingUI.visible = false
			$PlayerGUI.visible = true
		else:
			anim_player.play("ShadersNew")

		get_node("Sky_texture").call("set_time_of_day", current_time_hour, get_node("DirectionalLight"), deg2rad(horizontal_angle))
		_set_sky_rotation()
		self.get_node("LoadingCamera").visible = false

		var directional_light = get_node("DirectionalLight")
		var directional_light_night = get_node("DirectionalLightNight")

		if current_time_hour >= 19 or current_time_hour < 6:
			directional_light.visible = false
			directional_light_night.visible = true
		elif current_time_hour >= 5 and current_time_hour < 20:
			directional_light.visible = true
			directional_light_night.visible = false
		else:
			directional_light.visible = false
			directional_light_night.visible = false
	else:
		current_time_hour = hour
		var anim_player = get_node("AnimationPlayer")
		anim_player.set_current_animation("ShadersNew")

		if anim_player.current_animation_position >= current_time_hour - 1:
			anim_player.stop(false)
		else:
			_on_sky_texture_sky_updated()
			anim_player.play("ShadersNew")

		get_node("Sky_texture").call("set_time_of_day", anim_player.current_animation_position, get_node("DirectionalLight"), deg2rad(horizontal_angle))
		_set_sky_rotation()

		var directional_light = get_node("DirectionalLight")
		var directional_light_night = get_node("DirectionalLightNight")

		if current_time_hour >= 19 or current_time_hour < 6:
			directional_light.visible = false
			directional_light_night.visible = true
		elif current_time_hour >= 5 and current_time_hour < 20:
			directional_light.visible = true
			directional_light_night.visible = false
		else:
				directional_light.visible = false
				directional_light_night.visible = false

# UI Handling Functions

# Show the login UI and hide the main game UI
func _show_login_ui():
	$LoginUI.visible = true
	$PlayerGUI.visible = false


# Handle the Play button press to start the game
func _on_PlayButton_pressed():
	is_logged_in = true
	var username_field = $LoginUI/UsernameInput
	var password_field = $LoginUI/PasswordInput
	var country_field = $LoginUI/CountryInput

	# Ensure both username and password are provided
	if username_field.text.strip_edges() != "" and password_field.text.strip_edges() != "":
		# Update s1sd with the provided credentials
		var s1sd = get_node("/root/s1sd")
		s1sd.set_player_name(username_field.text.strip_edges())
		s1sd.set_password(password_field.text.strip_edges())
		s1sd.set_country(country_field.text.strip_edges())

		# Hide login UI and show loading screen
		$LoginUI.visible = false
		$LoadingUI.visible = true

		# Connect to server after setting the time
		_update_time(get_trt_time_as_number_with_dots())
		connect_to_server()
	else:
		# Show an error message if the fields are empty
		print("Please enter both username and password")
		# Optionally display this error in the UI
		# $LoginUI/ErrorLabel.text = "Please enter both username and password"


# Button Actions for UI visibility and emotions

func _on_TextureButton_pressed():
	var line_edit = get_node("PlayerGUI/LineEdit")
	var message = line_edit.text.strip_edges()

	if message != "":
		_on_chat_message_entered(message)
		line_edit.clear()
		line_edit.release_focus()


func _on_TextureButton2_pressed():
	$PlayerGUI/ColorRect.visible = !$PlayerGUI/ColorRect.visible


func _on_TextureButton3_pressed():
	$PlayerGUI/ColorRect3.visible = !$PlayerGUI/ColorRect3.visible


func _on_TextureButton4_pressed():
	$PlayerGUI/ColorRect4.visible = !$PlayerGUI/ColorRect4.visible


func _on_TextureButton5_pressed():
	self.get_node("PlayerGUI/TextureRect/EmotionWheel").visible = !self.get_node("PlayerGUI/TextureRect/EmotionWheel").visible


func _on_Neutral_pressed():
	if players.has_node(get_node("/root/s1sd").get("username")):
		players.get_node(get_node("/root/s1sd").get("username")).set("current_emotion", "neutral")


func _on_Happy_pressed():
	if players.has_node(get_node("/root/s1sd").get("username")):
		players.get_node(get_node("/root/s1sd").get("username")).set("current_emotion", "happy")


func _on_Sad_pressed():
	if players.has_node(get_node("/root/s1sd").get("username")):
		players.get_node(get_node("/root/s1sd").get("username")).set("current_emotion", "sad")


func _on_Angry_pressed():
	if players.has_node(get_node("/root/s1sd").get("username")):
		players.get_node(get_node("/root/s1sd").get("username")).set("current_emotion", "angry")


# Map Saving Function

func _on_button_pressed():
	for part in workspace.get_children():
		if part is Spatial:
			var part_data = {
				"position": part.transform.origin,
				"rotation": part.transform.basis.get_euler(),
				"scale": part.transform.basis.get_scale(),
				"typepart": part.filename
			}

			# Retrieve and store the color of the part
			var color_str = ""
			var mesh_instance = part.get_node("MeshInstance")
			if mesh_instance:
				var material = mesh_instance.material_override as SpatialMaterial
				if material:
					color_str = str(material.albedo_color)

			# Send part data to the server
			send_websocket_message({
				"action": "place_part",
				"position": str(part_data["position"]),
				"rotation": str(part_data["rotation"]),
				"scale": str(part_data["scale"]),
				"color": color_str,
				"typepart": str(part_data["typepart"])
			})

	# Once all parts are sent, save the map
	send_websocket_message({
		"action": "save_map",
		"map_name": current_map_name,
		"username": get_node("/root/s1sd").get("username")
	})
