extends Spatial

var selected = false
var scale_step = 0.1
var min_scale = 0.2
var max_scale = 7
var scale_target_factor = null
var target = null

var cylinder_path = NodePath("Cylinder")
var top_path = NodePath("Top-slice")
var bottom_path = NodePath("Bottom-slice")
var collision_shape_path = NodePath("CollisionShape")

func rescale_log_x(parent : Node, op : String):
	var cylinder = parent.get_node(cylinder_path)
	var top = parent.get_node(top_path)
	var bottom = parent.get_node(bottom_path)
	var collision_shape = parent.get_node(collision_shape_path)
	var parts = [ top, cylinder, bottom, collision_shape ]
	
	for current in parts:
		var current_scale = current.scale
		if op == "+":
			current.scale = Vector3(current_scale.x + scale_step, current_scale.y, current_scale.z + scale_step)
		else:
			current.scale = Vector3(current_scale.x - scale_step, current_scale.y, current_scale.z - scale_step)


func rescale_log_y():
	var cylinder = target.get_node(cylinder_path)
	var top = target.get_node(top_path)
	var bottom = target.get_node(bottom_path)
	var collision_shape = target.get_node(collision_shape_path)
	
	cylinder.scale = Vector3(cylinder.scale.x, cylinder.scale.y + scale_target_factor, cylinder.scale.z)
	collision_shape.scale = Vector3(collision_shape.scale.x, collision_shape.scale.y + scale_target_factor, collision_shape.scale.z)
	top.translation = Vector3(top.translation.x, top.translation.y + scale_target_factor, top.translation.z)
	bottom.translation = Vector3(bottom.translation.x, bottom.translation.y - scale_target_factor, bottom.translation.z)
	translation = Vector3(translation.x, translation.y + scale_target_factor, translation.z)
	
	print(target.global_transform)
	
	
	

func _physics_process(delta):
	if selected:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		target.linear_velocity = Vector3(0,0,0)
		target.angular_velocity = Vector3(0,0,0)
		if scale_target_factor != null:
			rescale_log_y()
			scale_target_factor = null
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_Area_input_event(camera, event, click_position, click_normal, shape_idx):
	if event is InputEventMouseButton:
		if event.button_index == BUTTON_LEFT and event.pressed:
			selected = true
			target = get_parent()
			
		if event.button_index == BUTTON_WHEEL_DOWN:
			scale_target_factor = -scale_step
			
		if event.button_index == BUTTON_WHEEL_UP:
			scale_target_factor = scale_step

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == BUTTON_LEFT and not event.pressed:
			selected = false

#func _physics_process(delta):
#	if selected:
#		var global_position = lerp(global_position, get_global_mouse_position(), 25 * delta)
