extends Spatial


# Declare member variables here. Examples:
# var a = 2
# var b = "text"
var ingamehour = 0.0
var baseNightSkyRotation = Basis(Vector3(1.0, 1.0, 1.0).normalized(), 1.2)
var horizontalAngle = 25.0
var timeset = false
# Called when the node enters the scene tree for the first time.
func _ready():
		# Init our time of day
	get_node("Sky_texture").call("set_time_of_day", ingamehour, get_node("DirectionalLight"), deg2rad(horizontalAngle))

	# Rotate our night sky so our milkyway isn't on our horizon
	_set_sky_rotation()
	updatetime(18)

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
	ingamehour = hour
	var animPlayer = get_node("AnimationPlayer")
	animPlayer.set_current_animation("ShadersNew")
	if animPlayer.current_animation_position >= ingamehour:
		timeset = true
		animPlayer.stop(false)
	else:
		animPlayer.play("ShadersNew")
	get_node("Sky_texture").call("set_time_of_day", ingamehour, get_node("DirectionalLight"), deg2rad(horizontalAngle))
	_set_sky_rotation()
