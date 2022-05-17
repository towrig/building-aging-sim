tool
extends RigidBody

export(NodePath) var attached_to
export(float) var width_meters = 0.5 setget set_width_meters

var area

var _counter = 0.0
var rendered = false
var aging = false
var aging_rate = 0.0
var rot = 0.0
var has_fallen = false

var collisions = []

func _ready():
	friction = 1.0
	Globals.connect("toggle_aging", self, "on_aging_toggle")
	set_contact_monitor(true)
	set_max_contacts_reported(10)
	set_static()
	render()

func _process(delta):
	if Engine.editor_hint and not rendered:
		render()
	
	_counter += delta
	if (aging_rate < _counter) :
		if aging:
			age()
		_counter = 0

func set_width_meters(new_width):
	width_meters = new_width
	rendered = false

func render():
	$MeshInstance.scale.x = width_meters * 2.0
	rendered = true

func age():
	rot = calc_rot()
	$MeshInstance.get_active_material(0).set_shader_param("humidity", rot)

func calc_rot(): # 40 years to look destroyed, 100 years to completely disintegrate.
	return rot + 0.002

func set_static():
	set_mode(1)
	if area != null:
		return
	var collider = Area.new()
	var cs = CollisionShape.new()
	var cs_shape = $CollisionShape.shape.duplicate()
	cs.shape = cs_shape
	collider.add_child(cs)
	area = collider
	add_child(area)
	collider.connect("body_shape_entered", self, "_on_Area_shape_entered")
	collider.connect("body_shape_exited", self, "_on_Area_shape_exited")

func unset_static():
	if area != null:
	#	remove_child(area)
		set_mode(0)
	#	has_fallen = true

func set_state(state):
	if state == null:
		hide()
	else:
		set_transform(state.transform)
		var new_nodes = []
		var data = state.nodes[0]
		rot = data["rot"]
		$MeshInstance.get_active_material(0).set_shader_param("humidity", rot)
		show()
		rendered = true

# returns weight / amount of supporting points
func get_force_per_collision():
	return 1.0

func get_collision_body_position():
	return to_global(Vector3.ZERO)

func _on_Area_shape_entered(body_id, body, body_shape_index, local_shape_index):
	if !has_fallen and body.has_method("should_break"): #only add loginstances
		collisions.append(body_id)

func _on_Area_shape_exited(body_id, body, body_shape_index, local_shape_index):
	collisions.erase(body_id)
	if len(collisions) == 0:
		unset_static()

func _on_body_shape_entered(body_id, body, body_shape_index, local_shape_index):
	if body.get_mode() == 0 and len(collisions) == 0:
		unset_static()

func on_aging_toggle(rate, value):
	aging = value
	aging_rate = rate
