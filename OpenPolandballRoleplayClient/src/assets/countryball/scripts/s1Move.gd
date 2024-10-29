# Player movement and interaction controller for OpenPolandballRoleplay
# 
# This script manages player-specific functionality including:
# - Local and remote player movement
# - Camera control and perspective
# - Noclip mode toggling
# - Animation state management
# - Network position synchronization
# - Player customization (accessories, emotions)
# - Flag texture application
# - Player identification
#
# The script handles both local player input processing and
# remote player state updates received from the server.

extends KinematicBody

# Player identification and state
var username: String = ""
var current_emotion: String = "neutral"
var noclip_mode: bool = false

# Movement variables
var input_vec: Vector3 = Vector3()
var velocity: Vector3 = Vector3()
var vert_velocity: float = 0.0

# Accessory variables
var current_accessories: Array = []
var prevaccessories = null

# Movement constants
const JUMP_FORCE: float = 10.0
const GRAVITY: float = 85.0
const ANGULAR_ACCEL: float = 7.0

# Node references
var anim_player: AnimationPlayer
var accessories_node: Node

func _ready() -> void:
	anim_player = $AnimationPlayer
	accessories_node = $Pivot/Accessory

func _physics_process(delta: float) -> void:
	if not _is_local_player():
		return
		
	_update_camera()
	_handle_movement(delta)
	_sync_multiplayer()

func _is_local_player() -> bool:
	return username == str(
		get_tree().root.get_node("s1sd").get("username")
	)

func _update_camera() -> void:
	var game_node = self.get_tree().root.get_node("game")
	game_node.prev_cam = $Camroot/h/v/ARVROrigin/ARVRCamera

func _handle_movement(delta: float) -> void:
	var h_rot = $Camroot/h.global_transform.basis.get_euler().y
	
	# Calculate input vector based on current heading
	input_vec = Vector3(
		Input.get_action_strength("right") - 
			Input.get_action_strength("left"),
		0,
		Input.get_action_strength("down") - 
			Input.get_action_strength("up")
	).rotated(Vector3.UP, h_rot)

	_update_rotation(delta)
	
	if noclip_mode:
		_handle_noclip_movement(delta)
	else:
		_handle_normal_movement(delta)
	
	_update_animation()

func _update_rotation(delta: float) -> void:
	if _has_movement_input():
		$Pivot.rotation.y = lerp_angle(
			$Pivot.rotation.y,
			atan2(-input_vec.x, -input_vec.z),
			delta * ANGULAR_ACCEL
		)

func _has_movement_input() -> bool:
	return (
		Input.is_action_pressed("down") or
		Input.is_action_pressed("up") or
		Input.is_action_pressed("left") or
		Input.is_action_pressed("right")
	)

func _handle_noclip_movement(delta: float) -> void:
	velocity = input_vec
	velocity.y = (
		Input.get_action_strength("noclip_up") - 
		Input.get_action_strength("noclip_down")
	)
	translate(velocity * delta * 10)

func _handle_normal_movement(delta: float) -> void:
	velocity = input_vec
	
	# Apply gravity and handle jumping
	if not is_on_floor():
		vert_velocity -= GRAVITY * delta
	else:
		vert_velocity = 0.0
		if Input.is_action_pressed("Jump"):
			vert_velocity = JUMP_FORCE
			
	move_and_slide(
		velocity + Vector3.UP * vert_velocity, 
		Vector3.UP
	)

func _update_animation() -> void:
	var anim_name = "Idle" if input_vec == Vector3() else "Walk"
	anim_player.play(anim_name)

func _sync_multiplayer() -> void:
	get_node("/root/game").send_websocket_message({
		"action": "update_player",
		"username": username,
		"transform": global_transform,
		"InputVector": input_vec,
		"rotation": {
			"x": $Pivot.rotation.x,
			"y": $Pivot.rotation.y,
			"z": $Pivot.rotation.z
		},
		"emotion": current_emotion,
		"accessories": current_accessories
	})

# Noclip mode controls
func enable_noclip() -> void:
	noclip_mode = true
	vert_velocity = 0.0

func disable_noclip() -> void:
	noclip_mode = false

# Remote player update handling
func update_player(
	tr: Transform, 
	input_vector: Vector3, 
	rotation: Dictionary
) -> void:
	global_transform = tr
	$Pivot.rotation = Vector3(
		rotation["x"], 
		rotation["y"], 
		rotation["z"]
	)
	input_vec = input_vector
	_update_animation()

# Accessory management
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
				self.get_node("Pivot/Accessory").add_child(accessory_instance)
				print("Accessory '%s' applied to player" % accessory_name)
			else:
				print("Failed to load accessory: %s" % accessory_name)

# Flag texture handling
func apply_flag(flag_data: String) -> void:
	if flag_data.empty():
		return
		
	var byte_array = Marshalls.base64_to_raw(flag_data)
	var image = Image.new()
	
	if image.load_png_from_buffer(byte_array) != OK:
		push_warning("Failed to load flag PNG from buffer")
		return

	var texture = ImageTexture.new()
	texture.create_from_image(image)
	
	var cube = $Pivot/Skin/Armature/Skeleton/Cube
	var orig_mat = cube.get_surface_material(0)
	
	if orig_mat is SpatialMaterial:
		var new_mat = orig_mat.duplicate()
		new_mat.albedo_texture = texture
		cube.set_surface_material(0, new_mat)
