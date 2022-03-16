tool
extends RigidBody

export var density = 600 # in kg/m3
export var radius = 0.5 # in m
export(int) var length = 6 setget set_length
export(Material) var end_material
export(Material) var bark_material
export(Mesh) var piece_mesh = load('res://assets/log.obj')
export(Mesh) var top_shape setget set_top_shape
var top_shape_copy
export(Mesh) var bottom_shape setget set_bottom_shape
var bottom_shape_copy

onready var log_preload = load("res://LogInstance.tscn")
export(bool) var show_debug = false;
var nodeList = []
var aging = false
var aging_rate = 0.1
var _counter = 0
var rendered = false
var collision_force = {}

class DataNode extends Reference:
	var position = Vector3(0.0,0.0,0.0)
	var source_mesh
	var mesh
	var colliders = [] # instance id-s of colliders
	var collider_forces = {}
	var collisions = {} #key: body; value: array of colliding collider indexes of the body
	var stress = Vector3(0.0, 0.0, 0.0)
	var rot = 0.0

func _ready():
	if not rendered:
		assemble_tree()
	Globals.connect("start_aging", self, "on_aging_start")
	connect("body_shape_entered", self, "_on_body_shape_entered")
	connect("body_shape_exited", self, "_on_body_shape_exited")

func _process(delta):
	_counter += aging_rate * delta
	if (1 < _counter) :
		if aging:
			update_nodes()
			age()
		_counter = 0
	if Engine.editor_hint and not rendered:
		assemble_tree()

func set_length(new_length):
	length = new_length
	rendered = false

func set_top_shape(new_top_shape):
	top_shape = new_top_shape
	rendered = false
	
func set_bottom_shape(new_bottom_shape):
	bottom_shape = new_bottom_shape
	rendered = false

func assemble_tree():
	set_contact_monitor(true)
	set_max_contacts_reported(length*2)
	clear()
	var volume = (PI * pow(radius, 2.0)) * length
	mass = volume * density
	set_materials()
	nodeList = gen_nodes()
	gen_tree(nodeList)
	rendered = true

# generates default node positions
func gen_nodes():
	var nodes = []
	var start = -length;
	var end = length;
	var i = start+1
	while (i <= end):
		var node = DataNode.new()
		node.position = Vector3(0.0, i, 0.0)
		nodes.append(node)
		i+=2
	return nodes;

func create_joint(node, rotation_y, is_top, is_bottom, scale_vec, mesh, material):
	var mesh_copy = mesh.duplicate()
	var mat = material.duplicate()
	if mat.get_shader_param("humidity"):
		mat.set_shader_param("humidity", node.rot)
	mesh_copy.surface_set_material(0, mat)
	var end = MeshInstance.new()
	end.translation = node.position
	end.scale = scale_vec
	end.set_mesh(mesh_copy)
	node.mesh = end
	node.source_mesh = mesh_copy
	node.colliders = create_node_hitbox(mesh_copy, node.position, is_top, is_bottom)
	return end

func create_end_joint(node, rotation_y, isTop, scale_vec, mesh, material):
	#var core_scale = Vector3(0.9, 0.05, 0.9);
	if mesh == null:
		mesh = piece_mesh
		var core_mesh = create_joint(node, rotation_y, false, false, scale_vec, mesh, bark_material)
		return core_mesh
	
	var core_scale = Vector3(0.9, 1.0, 0.9);
	var core_mesh = create_joint(node, rotation_y, isTop, !isTop, core_scale, mesh, material)
	if isTop:
		core_mesh.translation.y += 0.0 #used to be 0.1
	else:
		core_mesh.translation.y -= 0.0 #used to be 0.1
		core_mesh.rotate_x(PI)
		core_mesh.rotate_y(PI)
	return core_mesh

func gen_tree(list):
	var t_scale = Vector3(1.0, 1.0, 1.0);
	var i = 0
	var current_node = null
	while i < len(list):
		if i == 0:
			current_node = create_end_joint(list[i], 0.0, false, t_scale, bottom_shape, end_material)
		elif i+1 == len(list):
			current_node = create_end_joint(list[i], 0.0, true, t_scale, top_shape, end_material)
		else:
			current_node = create_joint(list[i], 0.0, false, false, t_scale, piece_mesh, bark_material)
		self.add_child(current_node)
		i += 1

func get_collision_disk(mesh, point, offset, boundary):
	var returnable = []
	var mdt = MeshDataTool.new()
	mdt.create_from_surface(mesh, 0)
	for i in range(mdt.get_vertex_count()):
		var vertex = mdt.get_vertex(i)
		if vertex.y == boundary:
			var hitbox_vertex = Vector3(vertex.x, point.y+offset, vertex.z)
			if !returnable.has(hitbox_vertex):
				returnable.append(hitbox_vertex)
	return returnable

func create_node_end_hitbox(shape, pos, offset):
	var hitbox = CollisionShape.new()
	var hitbox_shape = ConvexPolygonShape.new()
	var hitbox_points = []
	hitbox_points += get_collision_disk(shape, pos, offset, 1)
	hitbox_points += get_collision_disk(shape, pos, offset-1, 1)
	hitbox_shape.set_points(hitbox_points)
	hitbox.shape = hitbox_shape
	hitbox.scale.x *= 0.9
	hitbox.scale.z *= 0.9
	self.add_child(hitbox)
	return hitbox.get_instance_id()

func create_node_hitbox(mesh, pos, is_top, is_bottom):
	var hitbox = CollisionShape.new()
	var hitbox_shape = ConvexPolygonShape.new()
	var hitbox_points = []
	var instance_ids = []
	var top = Vector3(pos.x, pos.y+1.0, pos.z)
	var bottom = Vector3(pos.x, pos.y-1.0, pos.z)
	
	if is_top:
		instance_ids.append(create_node_end_hitbox(top_shape, top, 0))
		hitbox_points += get_collision_disk(piece_mesh, pos, 0, 1)
		pass
	else:
		hitbox_points += get_collision_disk(piece_mesh, top, 0, 1)
		pass
	
	if is_bottom:
		instance_ids.append(create_node_end_hitbox(bottom_shape, bottom, 1))
		hitbox_points += get_collision_disk(piece_mesh, pos, 0, 1)
		pass
	else:
		hitbox_points += get_collision_disk(piece_mesh, bottom, 0, 1)
		pass
	
	hitbox_shape.set_points(hitbox_points)
	hitbox.shape = hitbox_shape
	if is_top or is_bottom:
		hitbox.scale.x *= 0.9
		hitbox.scale.z *= 0.9
	self.add_child(hitbox)
	instance_ids.append(hitbox.get_instance_id())
	return instance_ids

func set_materials():
	piece_mesh.surface_set_material(0, bark_material)
	if top_shape:
		top_shape_copy = top_shape.duplicate()
		top_shape.surface_set_material(0, end_material)
		top_shape_copy.surface_set_material(0, end_material)
		
	if bottom_shape:
		bottom_shape_copy = bottom_shape.duplicate()
		bottom_shape.surface_set_material(0, end_material)
		bottom_shape_copy.surface_set_material(0, end_material)

func clear():
	top_shape_copy = null
	bottom_shape_copy = null
	#clear children
	for n in self.get_children():
		self.remove_child(n)
		n.queue_free()

func get_force_per_collision():
	#TODO: make this smart
	return mass * 9.8 / 2.0

func get_mass_per_node():
	return mass / float(length)

#offset comes out as a global value
func get_offset(stress: Vector3, prev_offset: Vector3):
	var radius = 1.0 # TODO: read this in from script variables
	var piece_mass = mass / length
	var stiffness = (density / 1000.0) / radius
	var max_change = stiffness * piece_mass / 1000
	var offset = stress * max_change
	if offset.length() > 1.0:
		offset = offset.normalized()
	return offset

func offset_mesh(node: DataNode, prev_offset: Vector3, is_start:bool, is_end: bool):
	var mesh_copy = node.source_mesh.duplicate()
	var mdt = MeshDataTool.new()
	var offset = get_offset(node.stress, prev_offset)
	if is_end:
		offset = Vector3.ZERO
	mdt.create_from_surface(mesh_copy, 0)
	for i in range(mdt.get_vertex_count()):
		var vertex = mdt.get_vertex(i)
		var local_y = vertex.y
		var lerp_weight = (vertex.y + 1) / 2
		var lerped_offset = lerp(prev_offset, offset, lerp_weight)
		if node.mesh.get_rotation().length() > 0:
			lerped_offset = lerp(offset, prev_offset, lerp_weight)
		vertex = to_local(to_global(vertex) + lerped_offset)
		vertex.y = local_y
		mdt.set_vertex(i, vertex)
	mesh_copy.surface_remove(0)
	mdt.commit_to_surface(mesh_copy)
	node.mesh.set_mesh(mesh_copy)
	return offset

func update_stress(node: DataNode):
	var gravity_force = Vector3(0.0, -1.0, 0.0)
	var supporting_force = Vector3.ZERO
	for key in node.collider_forces:
		var direction = node.collider_forces[key]
		supporting_force.y += direction.y
	if supporting_force.y > 0.0:
		node.stress = supporting_force
	else:
		node.stress = gravity_force + supporting_force

func get_piece_location(length, start, end):
	var left_pos_y = 0.0
	var j = start
	while j < end:
		left_pos_y += nodeList[j].position.y
		j += 1
	return to_global(Vector3(0.0, left_pos_y/float(length), 0.0))

func break_at(i):
	aging = false
	var left_half = log_preload.instance()
	var right_half = log_preload.instance()
	var left_length = len(nodeList) - i + 1
	var right_length = len(nodeList) - left_length
	left_half.set_length(left_length)
	left_half.end_material = end_material
	left_half.bark_material = bark_material
	left_half.set_bottom_shape(bottom_shape)
	right_half.set_length(right_length)
	right_half.end_material = end_material
	right_half.bark_material = bark_material
	right_half.set_top_shape(top_shape)
	left_half.assemble_tree()
	right_half.assemble_tree()
	
	# set positions
	var left_pos = get_piece_location(left_length, 0, left_length)
	left_half.set_transform(self.get_transform())
	left_half.set_translation(left_pos)
	var right_pos = get_piece_location(right_length, left_length-1, len(nodeList))
	right_half.set_transform(self.get_transform())
	right_half.set_translation(right_pos)
	
	# transfer rot
	var j = 0
	while j < left_length:
		left_half.nodeList[j].rot = nodeList[j].rot
		left_half.nodeList[j].mesh.get_active_material(0).set_shader_param("humidity", nodeList[j].rot)
		j+=1
	while j < len(nodeList):
		right_half.nodeList[j-left_length].rot = nodeList[j].rot
		right_half.nodeList[j-left_length].mesh.get_active_material(0).set_shader_param("humidity", nodeList[j].rot)
		j+=1
	
	print(left_half.nodeList[0].rot)
	
	# Clear all children
	for n in self.get_children():
		self.remove_child(n)
		n.queue_free()

	left_half.aging = true
	right_half.aging = true
	var root = get_tree().root.get_child(0)
	root.add_child(left_half)
	root.add_child(right_half)
	get_parent().remove_child(self)
	self.queue_free()

# Calculates if stress is bigger than the tensile strength of wood, taking rot into account
func should_break(i):
	var force = nodeList[i].stress.length() # force in newtons
	var stability_factor = 1.0 - nodeList[i].rot + 0.01 # precentage
	var area = pow(radius, 2.0) # m2
	var breaking_threshold = area * 80000 * stability_factor # 70MPa - 140MPa
	return force >= breaking_threshold

func update_nodes():
	var i = 0
	#var prev_offset = Vector3.ZERO
	var highest_stress = 0
	var highest_stress_i = -1
	while i < len(nodeList):
		var is_end = i == len(nodeList)-1
		update_stress(nodeList[i])
		if nodeList[i].stress.length() > highest_stress:
			highest_stress = nodeList[i].stress.length()
			highest_stress_i = i
		#prev_offset = offset_mesh(nodeList[i], prev_offset, false, is_end)
		i+=1
	if should_break(highest_stress_i):
		break_at(highest_stress_i)

func get_rot_at(collider_indexes):
	if len(get_children()) == 0:
		return 0.0
	var counter = 0
	var sum = 0.0
	for index in collider_indexes:
		if self.shape_owner_get_owner(index) == null:
			print(name)
			print(len(get_children()))
		var collider_id = self.shape_owner_get_owner(index).get_instance_id()
		for node in nodeList:
			if collider_id in node.colliders:
				sum += node.rot
				counter += 1
	if counter == 0:
		return sum
	return sum / counter

func get_neighbouring_rot(index):
	if index == 0:
		return nodeList[1].rot
	if index == len(nodeList)-1:
		return nodeList[index-1].rot
	return (nodeList[index-1].rot + nodeList[index+1].rot)

func cleanup_collisions(node):
	var removables = []
	for key in node.collisions.keys():
		var body = instance_from_id(key)
		if body == null:
			removables.append(key)
	for key in removables:
		node.collisions.erase(key)

#function returns -1 if no collision, 100 if ground, or rot if node
func touching_ground_or_rot(node):
	var value = 0.0
	if not node.collisions:
		return value
	
	cleanup_collisions(node)
	for key in node.collisions.keys():
		var body = instance_from_id(key)
		if body.has_method("get_constant_angular_velocity"):
			value = 100.0
		else:
			
			if body.has_method("get_rot_at"):
				var rot = body.get_rot_at(node.collisions[key])
				if value < rot:
					value = rot
	return value

func calc_rot(touching_rot, neighbours_rot, current_rot):
	if touching_rot < 0.3 && neighbours_rot < 0.3:
		return 0.0
	var operations_result = current_rot + 0.01
	return clamp(operations_result, 0.0, 1.0)

func handle_humidity():
	var i = 0
	while i < len(nodeList):
		var touching_rot = touching_ground_or_rot(nodeList[i])
		var neighbours_rot = get_neighbouring_rot(i)
		var new_rot_value = calc_rot(touching_rot, neighbours_rot, nodeList[i].rot)
		nodeList[i].rot = new_rot_value
		nodeList[i].mesh.get_active_material(0).set_shader_param("humidity", new_rot_value)
		i += 1

func age():
	if len(get_children()) == 0:
		return
	handle_humidity()

func get_node_pos_by_collider(shape_id):
	for node in nodeList:
		if shape_id in node.colliders:
			return to_global(node.position)
	return null


#Collisions
func add_node_collision(collider_id, body, body_id, body_shape_index):
	for node in nodeList:
		if collider_id in node.colliders:
			if !(body_id in node.collisions):
				node.collisions[body_id] = []
			if !(body_shape_index in node.collisions[body_id]):
				node.collisions[body_id].append(body_shape_index)
			var colliding_force_dir = get_force_direction(body, body_shape_index, collider_id)
			if body.has_method("get_force_per_collision"):
				colliding_force_dir = colliding_force_dir.normalized() * body.get_force_per_collision()
			node.collider_forces[collider_id] = colliding_force_dir
			break

func remove_node_collision(collider_id, body_id, body_collider_index):
	for node in nodeList:
		if collider_id in node.colliders:
			if body_id in node.collisions:
				if body_collider_index in node.collisions[body_id]:
					node.collisions[body_id].remove(body_collider_index)
				if !node.collisions[body_id]:
					node.collisions.erase(body_id)
				node.collider_forces.erase(collider_id)
			break

func get_force_direction(body, body_shape_index, collider_id):
	if body.has_method("get_node_pos_by_collider"):
		var node_pos = self.get_node_pos_by_collider(collider_id)
		var b_shape_id = body.shape_owner_get_owner(body_shape_index).get_instance_id()
		var b_node_pos = body.get_node_pos_by_collider(b_shape_id)
		return node_pos - b_node_pos
	return Vector3.ZERO

# SIGNALS
func on_aging_start(rate):
	aging = true
	aging_rate = rate

func _on_body_shape_entered(body_id, body, body_shape_index, local_shape_index):
	if self.shape_owner_get_owner(local_shape_index) is CollisionShape:
		var collider_id = self.shape_owner_get_owner(local_shape_index).get_instance_id()
		add_node_collision(collider_id, body, body_id, body_shape_index)

func _on_body_shape_exited(body_id, body, body_shape_index, local_shape_index):
	if self.shape_owner_get_owner(local_shape_index) is CollisionShape:
		var collider_id = self.shape_owner_get_owner(local_shape_index).get_instance_id()
		remove_node_collision(collider_id, body_id, body_shape_index)


#func _input(event):
#	if event is InputEventMouseButton:
#		if event.button_index == BUTTON_LEFT and not event.pressed:
#			print("clicked rigidbody")
