extends Spatial

var camrot_h = 0.0
var camrot_v = 0.0
var cam_v_max = 75
var cam_v_min = -55
var h_sensitivity = 0.1
var v_sensitivity = 0.1
var h_acceleration = 10.0
var v_acceleration = 10.0
var zoom_speed = .25  # Speed of zooming
var target_zoom = 0.0  # Target zoom level
var zoom_acceleration = 1  # Acceleration of zooming
var zoom_min = 0.0  # Minimum zoom level (closest)
var zoom_max = 2.5  # Maximum zoom level (farthest)
var is_dragging = false  # Flag to track whether the mouse is being dragged

func _ready():
	$"h/v/ARVROrigin/ARVRCamera".far = 512
	target_zoom = $"h/v/ARVROrigin/ARVRCamera".translation.z

func _input(event):
	if not get_parent().get("VRMode"):
		if event is InputEventMouseButton:
			if event.button_index == BUTTON_LEFT:
				is_dragging = event.pressed  # Set dragging flag on mouse press/release
			elif event.button_index == BUTTON_WHEEL_UP:
				target_zoom -= zoom_speed
			elif event.button_index == BUTTON_WHEEL_DOWN:
				target_zoom += zoom_speed
				
		elif event is InputEventMouseMotion and is_dragging:
			camrot_h += -event.relative.x * h_sensitivity
			camrot_v += event.relative.y * v_sensitivity
				
		elif event is InputEventKey:
			if event.is_pressed():
				if event.scancode == KEY_I:
					target_zoom -= zoom_speed
				elif event.scancode == KEY_O:
					target_zoom += zoom_speed

func _physics_process(delta):
	if not get_parent().get("VRMode"):
		camrot_v = clamp(camrot_v, cam_v_min, cam_v_max)
		
		# Smooth camera rotation
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

		# Smooth zooming with cap
		target_zoom = clamp(target_zoom, zoom_min, zoom_max)
		$"h/v/ARVROrigin/ARVRCamera".translation.z = lerp(
			$"h/v/ARVROrigin/ARVRCamera".translation.z,
			target_zoom,
			delta * zoom_acceleration
		)
