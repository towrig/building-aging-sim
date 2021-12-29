extends Control


func on_aging_start():
	print("ON AGING START")
	Globals.emit_signal("start_aging", 0.5)
	pass

# Called when the node enters the scene tree for the first time.
func _ready():
	$AgeOrHumidfy.connect("pressed", self, "on_aging_start")
