extends Spatial

var camrot_h = 0.0
var camrot_v = 0.0
var cam_v_max = 75
var cam_v_min = -55
var h_sensitivity = 0.1
var v_sensitivity = 0.1
var h_acceleration = 10.0
var v_acceleration = 10.0
var move_speed = 10.0
var move_acceleration = 5.0
var velocity = Vector3.ZERO
var MouseFree = true

func _ready():
	# Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	$"h/v/ARVROrigin/ARVRCamera".far = 512

func _input(event):
	if not get_parent().get("VRMode"):
		if event is InputEventMouseMotion:
			camrot_h += -event.relative.x * h_sensitivity
			camrot_v += event.relative.y * v_sensitivity

func _physics_process(delta):
	if not get_parent().get("VRMode"):
		camrot_v = clamp(camrot_v, cam_v_min, cam_v_max)

		$"h".rotation_degrees = Vector3(
			$"h".rotation_degrees.x,
			lerp($"h".rotation_degrees.y, camrot_h, delta * h_acceleration),
			$"h".rotation_degrees.z
		)

		$"h/v".rotation_degrees = Vector3(
			lerp($"h/v".rotation_degrees.x, camrot_v, delta * v_acceleration),
			$"h/v".rotation_degrees.y,
			$"h/v".rotation_degrees.z
		)

		# Movement input handling
		var input_dir = Vector3.ZERO
		if Input.is_action_pressed("free_camera"):
			if not MouseFree:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				MouseFree = true
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				MouseFree = false
		if Input.is_action_pressed("up"):  # W key
			input_dir -= $"h".transform.basis.z
		if Input.is_action_pressed("down"):  # S key
			input_dir += $"h".transform.basis.z
		if Input.is_action_pressed("left"):  # A key
			input_dir -= $"h".transform.basis.x
		if Input.is_action_pressed("right"):  # D key
			input_dir += $"h".transform.basis.x
		if Input.is_action_pressed("ui_page_up"):  # Q key
			input_dir -= $"h".transform.basis.y
		if Input.is_action_pressed("ui_page_down"):  # E key
			input_dir += $"h".transform.basis.y

		input_dir = input_dir.normalized()

		velocity = lerp(velocity, input_dir * move_speed, delta * move_acceleration)
		translate(velocity * delta)
