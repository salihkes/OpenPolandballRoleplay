extends SpotLight


# Declare member variables here. Examples:
# var a = 2
# var b = "text"


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	var time = self.get_parent().get_parent().get_parent().get_parent().get("timeval")
	if time > 6 and time < 17:
		self.light_energy = 0.5
	elif time == 7 or time == 18:
		self.light_energy = 0.25
	else:
		self.light_energy = 0.1
