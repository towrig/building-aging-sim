tool
extends RigidBody

var aging = false
var aging_rate = 0.1
var _counter = 0
var rendered = false
export var density = 600 #in kg/m3
export(Vector3) var start_position = Vector3(0.0, -2.0, 0.0) setget set_start_pos
export(Vector3) var end_position = Vector3(0.0, 2.0, 0.0) setget set_end_pos
export(Material) var end_material
export(Material) var bark_material
export(Material) var rot_material
export(Mesh) var piece_mesh = load('res://assets/log.obj')
export(Mesh) var top_shape setget set_top_shape
var top_shape_copy
export(Mesh) var bottom_shape setget set_bottom_shape
var bottom_shape_copy

export(bool) var show_debug = false;
var debug_point = preload("res://assets/Point.tscn")

var nodeList = []
var length = (end_position - start_position).y

class DataNode extends Reference:
	var position = Vector3(0.0,0.0,0.0)
	var mesh
	var stress = 0.0
	var rot = 0.0

# Example of ducktyping
func duckExmpl(node):
	#if has method -> call method
	if node.has_method("walk"):
		node.call("walk")
		node.call_deferred("walk") #called when everything else is already updated

func set_start_pos(new_pos):
	start_position = new_pos
	rendered = false

func set_end_pos(new_pos):
	end_position = new_pos
	rendered = false

func set_top_shape(new_top_shape):
	top_shape = new_top_shape
	rendered = false
	
func set_bottom_shape(new_bottom_shape):
	bottom_shape = new_bottom_shape
	rendered = false

# generates default node positions
func genNodes():
	var nodes = []
	var i = start_position.y+1
	while (i < end_position.y):
		var node = DataNode.new()
		node.position = Vector3(0.0, i, 0.0)
		nodes.append(node)
		i+=2
	return nodes;

func create_joint(node, rotation_y, scale_vec, mesh, material):
	var mesh_copy = mesh.duplicate()
	var mat = material.duplicate()
	if mat.get_shader_param("humidity"):
		print("HAS MATERIAL HUMIDITY")
		mat.set_shader_param("humidity", 0.0)
	mesh_copy.surface_set_material(0, mat)
	var end = MeshInstance.new()
	end.translation = node.position
	end.scale = scale_vec
	end.set_mesh(mesh_copy)
	node.mesh = end
	return end

func create_end_joint(node, rotation_y, isTop, scale_vec, mesh, material):
	#var core_scale = Vector3(0.9, 0.05, 0.9);
	if mesh == null: 
		mesh = piece_mesh
		var core_mesh = create_joint(node, rotation_y, scale_vec, mesh, bark_material)
		self.add_child(core_mesh)
		return
		
	var core_scale = Vector3(0.9, 1.0, 0.9);
	var core_mesh = create_joint(node, rotation_y, core_scale, mesh, material)
	if isTop:
		core_mesh.translation.y += 0.0 #used to be 0.1
	else:
		core_mesh.translation.y -= 0.0 #used to be 0.1
		core_mesh.rotate_x(PI)
		core_mesh.rotate_y(PI)
	self.add_child(core_mesh)

func genTree(list):
	var t_scale = Vector3(1.0, 1.0, 1.0);
	var i = 0
	while i < len(list):
		if i == 0:
			create_end_joint(list[i], 0.0, false, t_scale, bottom_shape, end_material)
		elif i+1 == len(list):
			create_end_joint(list[i], 0.0, true, t_scale, top_shape, end_material)
		else:
			self.add_child(create_joint(list[i], 0.0, t_scale, piece_mesh, bark_material))
		i += 1

func getCollisionDisk(mesh, point, offset, boundary):
	var returnable = []
	var mdt = MeshDataTool.new()
	mdt.create_from_surface(mesh, 0)
	for i in range(mdt.get_vertex_count()):
		var vertex = mdt.get_vertex(i)
		if vertex.y == boundary:
			var hitbox_vertex = Vector3(vertex.x, point.y+offset, vertex.z)
			if !returnable.has(hitbox_vertex):
				returnable.append(hitbox_vertex)
	
	#print("-----------------------------")
	#print(point.y)
	#print(offset)
	#print("-----------------------------")
	#print(returnable)
	#print("-----------------------------")
	return returnable
	
func showPoints(vectors):
	var existing = get_tree().get_nodes_in_group("debug_points");
	for node in existing:
		node.queue_free()
	
	for vec in vectors:
		var point = debug_point.instance()
		point.scale = Vector3(0.1, 0.1, 0.1)
		point.translation = vec
		self.add_child(point)

func createEndHitbox(shape, pos, offset):
	var hitbox = CollisionShape.new()
	var hitbox_shape = ConvexPolygonShape.new()
	var hitbox_points = []
	hitbox_points += getCollisionDisk(shape, pos, offset, 1)
	hitbox_points += getCollisionDisk(shape, pos, offset-1, 1)
	hitbox_shape.set_points(hitbox_points)
	hitbox.shape = hitbox_shape
	self.add_child(hitbox)

func createHitbox():
	var hitbox = CollisionShape.new()
	var hitbox_shape = ConvexPolygonShape.new()
	var hitbox_points = []
	
	if top_shape:
		createEndHitbox(top_shape, end_position, 0)
		var pos = Vector3(end_position.x, end_position.y - 1, end_position.z)
		hitbox_points += getCollisionDisk(piece_mesh, pos, 0, 1)
	else:
		hitbox_points += getCollisionDisk(piece_mesh, end_position, 0, 1)
	
	if bottom_shape:
		createEndHitbox(bottom_shape, start_position, 1)
		var pos = Vector3(end_position.x, start_position.y + 1, end_position.z)
		hitbox_points += getCollisionDisk(piece_mesh, pos, 0, 1)
	else:
		hitbox_points += getCollisionDisk(piece_mesh, start_position, 0, 1)
	
	hitbox_shape.set_points(hitbox_points)
	hitbox.shape = hitbox_shape
	self.add_child(hitbox)

func setMaterials():
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

func assembleTree():
	clear()
	createHitbox()
	setMaterials()
	nodeList = genNodes()
	genTree(nodeList);
	
	var radius = 1 / 2
	var volume = (PI * pow(radius, 2)) * length
	weight = volume * density
	mass = volume * density
	rendered = true

func on_aging_start(rate):
	aging = true
	aging_rate = rate

func calcRot(prev_rot, current_rot):
	if prev_rot < 0.35:
		return 0.0
	var operations_result = current_rot + 0.01
	return clamp(operations_result, 0.0, 1.0)

func handleHumidity():
	# use translation for world position of node
	# based on if touching ground, start increasing humidity from there.
	var start_pos = translation + nodeList[0].position
	var top_pos = translation + nodeList[len(nodeList)-1].position
	var diff = start_pos.y - top_pos.y
	
	#if show_debug:
	#	print("Start: "+ str(start_pos.y))
	#	print("Top: "+ str(top_pos.y))
	#	print("-----------------")
	var prev_rot = 0.35
	var i = 0
	
	if diff < 0.1: #top is higher
		while i < len(nodeList):
			var new_rot_value = calcRot(prev_rot, nodeList[i].rot)
			nodeList[i].rot = new_rot_value
			if show_debug:
				nodeList[i].mesh.get_active_material(0).set_shader_param("humidity", new_rot_value)
			prev_rot = new_rot_value
			i += 1
	elif diff > -0.1: #top is lower
		i = len(nodeList) - 1
		while i >= 0:
			var new_rot_value = calcRot(prev_rot, nodeList[i].rot)
			nodeList[i].rot = new_rot_value
			if show_debug:
				nodeList[i].mesh.get_active_material(0).set_shader_param("humidity", new_rot_value)
			prev_rot = new_rot_value
			i -= 1
	else: # basically level
		while i < len(nodeList):
			var new_rot_value = calcRot(prev_rot, nodeList[i].rot)
			nodeList[i].rot = new_rot_value
			if show_debug:
				nodeList[i].mesh.get_active_material(0).set_shader_param("humidity", new_rot_value)
			prev_rot = new_rot_value
			i += 1

func age():
	handleHumidity()

# Called when the node enters the scene tree for the first time.
func _ready():
	assembleTree()
	Globals.connect("start_aging", self, "on_aging_start")
	#var button = get_tree().get_root().find_node("AgeOrHumidify",true,false)
	#button.connect("start_aging", self, "on_aging_start")

func _process(delta):
	_counter += aging_rate * delta
	if aging && (1 < _counter) :
		age()
		_counter = 0
	if Engine.editor_hint and not rendered:
		assembleTree()

#
#func _input(event):
#	if event is InputEventMouseButton:
#		if event.button_index == BUTTON_LEFT and not event.pressed:
#			print("clicked rigidbody")
