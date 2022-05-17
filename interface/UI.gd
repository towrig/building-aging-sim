extends Control

var _counter = 0.0
var years_per_tick = 0.1

var aging = false
var is_structure_view = false
var aging_rate = 0.4
var years = 0.0
var latest_saved

onready var history = History.new()
var currently_breaking = {}

export var saving_period = 10

class History extends Reference:
	var object_states = {}
	
	func add_value(body: Node, state: ObjectState, year: int):
		var key = body.get_instance_id()
		if key == null:
			return
		
		if !(key in object_states):
			 object_states[key] = {} #key = year, value = ObjectState[]
		
		if !(year in object_states[key]):
			object_states[key][year] = state
	
	func get_value(body: Node, year: int):
		var key = body.get_instance_id()
		if key == null:
			return null
		if key in object_states:
			if year in object_states[key]:
				return object_states[key][year]
		return null

class ObjectState extends Reference:
	var transform
	var nodes

func _process(delta):
	_counter += delta 
	if (aging_rate < _counter):
		if aging:
			update_years()
			save_states() #saves state every X years defined in saving_period
		elif len(currently_breaking.keys()) != 0:
			check_breaks()
		_counter = 0


# Called when the node enters the scene tree for the first time.
func _ready():
	Globals.connect("break_happened", self, "on_break_happened")
	$AgeOrHumidfy.connect("pressed", self, "on_aging_toggle")
	$ToggleStructureView/CheckBox.connect("pressed", self, "on_structure_toggle")
	$SliderContainer/TimelineSlider.connect("value_changed", self, "aging_rate_change")
	$AgeCurrent.hide()

func on_aging_toggle():
	if aging:
		aging = false
		Globals.stop_physics()
		Globals.emit_signal("toggle_aging", aging_rate, false)
		$AgeCurrent.show()
		$AgeOrHumidfy.set_text("Start aging")
	else:
		aging = true
		Globals.emit_signal("toggle_aging", aging_rate, true)
		$AgeOrHumidfy.set_text("Stop aging")

func on_break_happened(object_id):
	aging = false
	Globals.emit_signal("toggle_aging", aging_rate, false)
	var instance = instance_from_id(object_id)
	currently_breaking[object_id] = instance.translation

func check_breaks():
	for id in currently_breaking.keys():
		var instance = instance_from_id(id)
		var translation_diff = (instance.translation - currently_breaking[id]).length()
		if translation_diff < 0.01:
			#make static
			instance.set_static()
			currently_breaking.erase(id)
		else:
			currently_breaking[id] = instance.translation
	
	if len(currently_breaking) == 0:
		aging = true
		print("BREAK FINISHED")
		Globals.emit_signal("toggle_aging", aging_rate, true)

func on_structure_toggle():
	if is_structure_view:
		is_structure_view = false
		Globals.emit_signal("toggle_structure", false)
	else:
		is_structure_view = true
		Globals.emit_signal("toggle_structure", true)

func aging_rate_change(value):
	if not aging:
		set_world_state(value)
		$AgeCurrent/YearsValue.text = str(value)

func update_years():
	years += years_per_tick
	$AgeInfo/YearsValue.text = str(stepify(years, 0.01))

func save_states():
	var saved_year = int(floor(years))
	if saved_year % saving_period != 0 || saved_year == latest_saved:
		return
	var scene_root = get_tree().root.get_child(1)
	for child in scene_root.get_children():
		if child.has_method("should_break") && child.is_visible(): # is loginstance and is visible
			save_log_state(child, saved_year)
		if (child.has_method("set_width_meters") || child.has_method("set_scale_meters")) && child.is_visible(): #is wall or roof and is visible
			save_normal_state(child, saved_year)
			
	$SliderContainer/TimelineSlider.set_max(saved_year)
	$SliderContainer/TimelineSlider.set_value(saved_year)

func save_log_state(log_body, year):
	if history:
		var state = ObjectState.new()
		state.transform = log_body.get_transform()
		var nodes = []
		for node in log_body.nodeList:
			nodes.append(node.clone())
		state.nodes = nodes
		history.add_value(log_body, state, year)

func save_normal_state(thatch, year):
	if history:
		var state = ObjectState.new()
		state.transform = thatch.get_transform()
		state.nodes = []
		var data_node = {
			"rot" : thatch.rot
		}
		state.nodes.append(data_node)
		history.add_value(thatch, state, year)

func set_world_state(year):
	var scene_root = get_tree().root.get_child(1)
	for child in scene_root.get_children():
		if child.has_method("set_state"):
			var state = history.get_value(child, year)
			child.set_state(state)
