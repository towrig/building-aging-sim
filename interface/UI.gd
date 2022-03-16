extends Control

var _counter = 0.0
var aging = false
var aging_rate = 10.0
var years = 0.0
var history = {}

class ObjectState extends Reference:
	var transform
	var nodes

func _process(delta):
	_counter += aging_rate * delta
	if (1 < _counter) && aging:
		update_years()
		save_state()

# Called when the node enters the scene tree for the first time.
func _ready():
	$AgeOrHumidfy.connect("pressed", self, "on_aging_start")
	$SliderContainer/TimelineSlider.connect("value_changed", self, "aging_rate_change")

func on_aging_start():
	print("ON AGING START")
	aging = true
	Globals.emit_signal("start_aging", aging_rate)

func aging_rate_change(value):
	print(value)

func update_years():
	years += 1.0 / aging_rate
	$AgeInfo/YearsValue.text = str(stepify(years, 0.01))

func save_state():
	#var scene_root = get_tree().root.get_child
	pass
