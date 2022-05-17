tool
extends RigidBody

export(Vector3) var scale_meters = Vector3(2.0, 1.0, 0.5) setget set_scale_meters # times 4.0 to get units 

var _counter = 0.0
var _tickrate = 1.0
var rendered = false
var aging = false
var aging_rate = 0.0
var rot = 0.0

func set_scale_meters(new_vec):
	scale_meters = new_vec
	rendered = false

func render():
	$Mesh.scale = scale_meters * 4.0
	var box_shape = BoxShape.new()
	box_shape.set_extents(Vector3(scale_meters.x*3.0, scale_meters.y*3.9, scale_meters.z*4.0))
	$CollisionShape.shape = box_shape
	rendered = true

func _ready():
	Globals.connect("toggle_aging", self, "on_aging_toggle")
	_tickrate = Globals.tickrate
	if not rendered:
		render()

func _process(delta):
	if Engine.editor_hint and not rendered:
		render()
	
	_counter += delta
	if (aging_rate < _counter) :
		if aging:
			age()
		_counter = 0

func age():
	rot = calc_rot()
	$Mesh.get_active_material(0).set_shader_param("humidity", rot)

func calc_rot():
	var current = rot
	return current + 0.002

func set_state(state):
	if state == null:
		hide()
	else:
		set_transform(state.transform)
		var new_nodes = []
		var data = state.nodes[0]
		rot = data["rot"]
		$Mesh.get_active_material(0).set_shader_param("humidity", rot)
		show()
		rendered = true

func on_aging_toggle(rate, value):
	aging = value
	aging_rate = rate

func _on_body_shape_entered(body_id, body, body_shape_index, local_shape_index):
	#do something 
	pass

func _on_body_shape_exited(body_id, body, body_shape_index, local_shape_index):
	#do something
	pass
