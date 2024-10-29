extends ScrollContainer

# Called when the node enters the scene tree for the first time.
func _ready():
	# Get the VBoxContainer node (replace 'VBoxContainer' with your actual VBoxContainer's name if necessary)
	var vbox = self.get_node("VBoxContainer")

	# Loop through all the children of the VBoxContainer
	for child in vbox.get_children():
		if child is Button:
			# Connect the button's "pressed" signal to a method in this script
			# Pass the button itself as a parameter to the method
			child.connect("pressed", self, "_on_button_pressed", [child])

# This method is called when a button is pressed
func _on_button_pressed(button: Button):
	self.get_tree().root.get_node("game").send_websocket_message({
		"action": "set_hat",
		"hat_name": button.text,
		"username": s1sd.username
	})

