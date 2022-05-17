tool
extends RigidBody

# using English Oak: https://www.wood-database.com/english-oak/

export var density = 675.0 # in kg/m3
export var modulus_of_rupture = 97.1 # in MPa
export var radius = 0.25 setget set_radius # in m
export var section_length = 0.5 # in m
export(int) var length = 6 setget set_length

export(Material) var end_material
export(Material) var bark_material
export(Mesh) var piece_mesh = load('res://assets/log.obj')
export(Mesh) var top_shape setget set_top_shape
var top_shape_copy
export(Mesh) var bottom_shape setget set_bottom_shape
var bottom_shape_copy

var log_preload 
var area_preload
var nodeList = []

# STATUSES:
var aging = false
var broken = false
var is_static = false
var is_structure_view = false
var rendered = false
export(bool) var show_debug = false;

var aging_rate = 0.0
var years_per_tick = 0.1
var _counter = 0
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
	var area
	
	func clone():
		var clone = DataNode.new()
		clone.position = position
		clone.source_mesh = source_mesh
		clone.mesh = mesh
		clone.colliders = colliders.duplicate(true)
		clone.collider_forces = collider_forces.duplicate(true)
		clone.collisions = collisions.duplicate(true)
		clone.stress = stress
		clone.rot = rot
		return clone

func _enter_tree():
	log_preload = load("res://LogInstance.tscn")
	area_preload = load("res://RigidArea.tscn")

func _ready():
	if not rendered:
		assemble_tree()
	Globals.connect("toggle_aging", self, "on_aging_toggle")
	Globals.connect("toggle_structure", self, "on_structure_toggle")
	#connect("body_shape_entered", self, "_on_body_shape_entered")
	#connect("body_shape_exited", self, "_on_body_shape_exited")

func _process(delta):
	_counter += delta
	if (aging_rate < _counter) :
		if aging && !broken:
			update_nodes()
			age()
		_counter = 0
	if Engine.editor_hint and not rendered:
		assemble_tree()

func set_length(new_length):
	length = new_length
	rendered = false

func set_radius(new_radius):
	radius = new_radius
	rendered = false

func set_top_shape(new_top_shape):
	top_shape = new_top_shape
	rendered = false
	
func set_bottom_shape(new_bottom_shape):
	bottom_shape = new_bottom_shape
	rendered = false

func set_state(state):
	if state == null:
		set_collisions(false)
		hide()
	else:
		set_transform(state.transform)
		clear_children()
		var new_nodes = []
		for node in state.nodes:
			new_nodes.append(node.clone())
		nodeList = new_nodes
		gen_tree(nodeList)
		show()
		rendered = true

func set_collisions(value):
	for child in get_children():
		if child.has_method("set_disabled"):
			child.set_disabled(!value) #so set_collisions(true) will enable them
			if !value:
				remove_child(child)

func assemble_tree():
	set_contact_monitor(true)
	set_max_contacts_reported(length*4)
	clear()
	mass = calculate_mass()
	set_materials()
	nodeList = gen_nodes()
	gen_tree(nodeList)
	set_static()
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
	if mat.get_shader_param("humidity") != null:
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
	
	var core_scale = Vector3(scale_vec.x*0.9, scale_vec.y, scale_vec.z*0.9);
	var core_mesh = create_joint(node, rotation_y, isTop, !isTop, core_scale, mesh, material)
	if isTop:
		core_mesh.translation.y += 0.0 #used to be 0.1
	else:
		core_mesh.translation.y -= 0.0 #used to be 0.1
		core_mesh.rotate_x(PI)
		core_mesh.rotate_y(PI)
	return core_mesh

func gen_tree(list):
	var xy_scale = radius * 4.0
	var t_scale = Vector3(xy_scale, 1.0, xy_scale);
	if len(list) == 1:
		if top_shape != null:
			self.add_child(create_end_joint(list[0], 0.0, true, t_scale, top_shape, end_material))
		elif bottom_shape != null:
			self.add_child(create_end_joint(list[0], 0.0, false, t_scale, bottom_shape, end_material))
		else:
			self.add_child(create_joint(list[0], 0.0, false, false, t_scale, piece_mesh, bark_material))
		return
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
	var xy_scale = radius * 4.0
	var mdt = MeshDataTool.new()
	mdt.create_from_surface(mesh, 0)
	for i in range(mdt.get_vertex_count()):
		var vertex = mdt.get_vertex(i)
		if vertex.y == boundary:
			var hitbox_vertex = Vector3(vertex.x * xy_scale, point.y+offset, vertex.z * xy_scale)
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
	else:
		hitbox_points += get_collision_disk(piece_mesh, top, 0, 1)
	
	if is_bottom:
		instance_ids.append(create_node_end_hitbox(bottom_shape, bottom, 1))
		hitbox_points += get_collision_disk(piece_mesh, pos, 0, 1)
	else:
		hitbox_points += get_collision_disk(piece_mesh, bottom, 0, 1)
	
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

func hide_all():
	set_collisions(false)
	hide()

func show_all():
	set_collisions(true)
	show()

func clear():
	top_shape_copy = null
	bottom_shape_copy = null
	clear_children()

func clear_children():
	for n in self.get_children():
		if not n.has_method("set_node_a"):
			self.remove_child(n)
			n.queue_free()

func get_force_per_collision():
	
	var support_count = 0
	
	for node in nodeList:
		for key in node.collider_forces.keys():
			if node.collider_forces[key].y > 0:
				support_count += 1
	
	if support_count == 0:
		support_count = 1
	return calculate_mass() / support_count

func get_mass_per_node():
	return calculate_mass() / float(length)

func get_mass_loss():
	var sum = 0.0
	for node in nodeList:
		if node.rot > 0.8:
			sum += 0.8 - node.rot #rot over 80% depicts 0 - 10%
	
	return abs(sum / (2.0 * len(nodeList))) #would return a 0.0 - 0.2 range, we want 0.0 - 0.1 range

func calculate_mass(loss = 0.0):
	var volume = (PI * pow(radius, 2.0)) * length
	return volume * density * (1.0 - loss)

#offset comes out as a global value
func get_offset(stress: Vector3, prev_offset: Vector3):
	var radius = 1.0
	var piece_mass = mass / length
	var stiffness = (density / 1000.0) / radius
	var max_change = stiffness * piece_mass / 1000
	var offset = stress * max_change
	if offset.length() > 1.0:
		offset = offset.normalized()
	return offset


#deprecated, worked with old system
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
	var left_length = i + 1
	var right_length = len(nodeList) - left_length
	if right_length == 0 || left_length == 0:
		return
	broken = true
	aging = false
	print(name, " broke at ", i, ", lengths (b/t): ", left_length, "/", right_length)
	var left_half = log_preload.instance()
	var right_half = log_preload.instance()
	left_half.set_length(left_length)
	left_half.radius = radius
	left_half.end_material = end_material
	left_half.bark_material = bark_material
	left_half.set_bottom_shape(bottom_shape)
	right_half.set_length(right_length)
	right_half.radius = radius
	right_half.end_material = end_material
	right_half.bark_material = bark_material
	right_half.set_top_shape(top_shape)
	left_half.assemble_tree()
	right_half.assemble_tree()
	
	# set positions
	var left_pos = get_piece_location(left_length, 0, left_length)
	left_half.set_transform(self.get_transform())
	left_half.set_translation(left_pos)
	var right_pos = get_piece_location(right_length, left_length, len(nodeList))
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
	left_half.aging = true
	right_half.aging = true
	
	# Clear all children
	clear_children()
	var root = get_tree().root.get_child(1)
	left_half.unset_static()
	right_half.unset_static()
	root.add_child(left_half)
	root.add_child(right_half)
	Globals.emit_signal("break_happened", left_half.get_instance_id())
	Globals.emit_signal("break_happened", right_half.get_instance_id())
	hide_all()

# Calculates if stress is bigger than the tensile strength of wood, taking rot into account in the process
func should_break(i):
	var force = calculate_mass() * 9.8 # force in newtons
	var mass_loss = clamp(1.0 - nodeList[i].rot, 0.0, 0.2) # precentage
	var area = pow(radius, 2.0) # m2
	var x = radius
	var y = radius
	var z_squared = section_length * section_length
	var breaking_threshold = (modulus_of_rupture * 10000 * y * z_squared) / (3 * x)
	var strength_loss = mass_loss * 2.0
	if mass_loss > 0.0:
		if mass_loss > 0.1:
			strength_loss = mass_loss * 4.0
		breaking_threshold = breaking_threshold * strength_loss
	if show_debug:
		print("Threshold: "+ str(breaking_threshold)+"; F: "+ str(force) + "; strength loss: "+ str(strength_loss))
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
		#prev_offset = offset_mesh(nodeList[i], prev_offset, false, is_end) <- bending
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
			return 0.0
		var collider_id = self.shape_owner_get_owner(index).get_instance_id()
		for node in nodeList:
			if collider_id in node.colliders:
				sum += node.rot
				counter += 1
	if counter == 0:
		return sum
	return sum / counter

func get_neighbouring_rot(index):
	if len(nodeList) == 1:
		return 0.0
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
		if body.name == "Floor":
			value = 1.0
			break
		else:
			if body.has_method("get_rot_at"):
				var rot = body.get_rot_at(node.collisions[key])
				if value < rot:
					value = rot
	return value


func calc_rot(touching_rot, neighbours_rot, current_rot):
	
	if show_debug:
		print("Calculating: ", current_rot, " N:", neighbours_rot, " T:", touching_rot)
	
	if current_rot > 0.8: #fungal infection
		var fungal_rate = 0.02 # 1% increase in mass loss 
		var fungal_decay = 0.75 * fungal_rate * years_per_tick
		return clamp(current_rot + fungal_decay, 0.0, 1.0)
	
	var U = neighbours_rot
	if touching_rot > U:
		U = touching_rot
	
	var addable = ((U*50.0) * section_length / (density/1000.0)) * years_per_tick
	var u = current_rot + (addable/100.0) #divide by 100 cause rot is 0.0 -> 1.0
	return clamp(u, 0.0, 1.0)

func calc_stress_percentage(node_index):
	var node = nodeList[node_index]
	return clamp(node.stress.length()*20, 0.0, 100.0)

func handle_humidity():
	var i = 0
	while i < len(nodeList):
		var touching_rot = touching_ground_or_rot(nodeList[i])
		var neighbours_rot = get_neighbouring_rot(i)
		var new_rot_value = calc_rot(touching_rot, neighbours_rot, nodeList[i].rot)
		nodeList[i].rot = new_rot_value
		nodeList[i].mesh.get_active_material(0).set_shader_param("humidity", new_rot_value)
		nodeList[i].mesh.get_active_material(0).set_shader_param("stress_percentage", calc_stress_percentage(i))
		nodeList[i].mesh.get_active_material(0).set_shader_param("show_structure", is_structure_view)
		i += 1

func age():
	if len(get_children()) == 0 || len(nodeList) == 0:
		return
	handle_humidity()
	if show_debug:
		print("---MASS LOSS: ",get_mass_loss())
	#handle_sinking()

func get_node_pos_by_collider(shape_id):
	for node in nodeList:
		if shape_id in node.colliders:
			return to_global(node.position)
	return null


# Collisions
func set_static():
	set_mode(1)
	#set_collisions(false)
	for node in nodeList:
		if area_preload == null:
			area_preload = load("res://RigidArea.tscn")
		if node.area == null:
			var collider = area_preload.instance()
			var cs = CollisionShape.new()
			var cs_shape = instance_from_id(node.colliders[0]).shape.duplicate()
			cs.shape = cs_shape
			collider.add_child(cs)
			node.area = collider
		add_child(node.area)
		node.area.connect("something_entered", self, "_on_Area_entered")
		node.area.connect("something_exited", self, "_on_Area_exited")

func unset_static():
	set_mode(0)
	for node in nodeList:
		remove_child(node.area)

func add_node_collision(collider_id, body, body_id, body_shape_index):
	for node in nodeList:
		cleanup_collisions(node)
		var is_area = false
		if node.area != null && collider_id == node.area.get_instance_id():
			is_area = true
		if collider_id in node.colliders or is_area:
			if !(body_id in node.collisions):
				node.collisions[body_id] = []
			if !(body_shape_index in node.collisions[body_id]):
				node.collisions[body_id].append(body_shape_index)
			var colliding_force_dir = get_force_direction(body, body_shape_index, collider_id)
			#if body.has_method("get_force_per_collision"):
			#	colliding_force_dir = colliding_force_dir.normalized()
			node.collider_forces[collider_id] = colliding_force_dir
			break

func remove_node_collision(collider_id, body_id, body_collider_index):
	for node in nodeList:
		var is_area = false
		if node.area != null && collider_id == node.area.get_instance_id():
			is_area = true
		if collider_id in node.colliders or is_area:
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
		if body.shape_owner_get_owner(body_shape_index) == null:
			return Vector3.ZERO
		var b_shape_id = body.shape_owner_get_owner(body_shape_index).get_instance_id()
		var b_node_pos = body.get_node_pos_by_collider(b_shape_id)
		return node_pos - b_node_pos
	if body.get_parent().has_method("get_collision_body_position"):
		var node_pos = to_global(get_area_node(collider_id).position)
		var b_node_pos = body.get_parent().get_collision_body_position()
		return node_pos - b_node_pos
	return Vector3.ZERO

func get_area_node(area_id, return_index = false):
	var i = 0
	for node in nodeList:
		if node.area != null and node.area.get_instance_id() == area_id:
			if return_index:
				return i
			return node
		i += 1

# SIGNALS
func on_structure_toggle(value):
	is_structure_view = value

func on_aging_toggle(rate, value):
	aging = value
	aging_rate = rate

func _on_Area_entered(target, target_shape_idx, area_id, area_shape_idx):
	if get_mode() == 0: 
		return
	if target is Area:
		if show_debug:
			print("COLLISION: "+ name + " " + str(area_id) + "; " + str(target.get_parent().name) + " " + str(target.get_instance_id()))
		add_node_collision(area_id, target, target.get_instance_id(), target_shape_idx)
	else:
		if show_debug:
			print("NON-AREA COLLISION: "+ name + " " + str(area_id) + "; " + str(target.name) + " " + str(target.get_instance_id()))
		if target.name == "Floor":
			add_node_collision(area_id, target, target.get_instance_id(), target_shape_idx)
		

func _on_Area_exited(target, target_shape_idx, area_id, area_shape_idx):
	if get_mode() == 0: 
		return
	if target is Area:
		if show_debug:
			print("COLLISION ENDED: "+ name + " " + str(area_shape_idx) + "; " + str(target))
		remove_node_collision(area_id, target.get_instance_id(), target_shape_idx)

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
