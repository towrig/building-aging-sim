tool
extends RigidBody

var aging = false
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

var debug_point = preload("res://assets/Point.tscn")

var nodeList = []
var length = (end_position - start_position).y

class DataNode extends Reference:
	var position = Vector3(0.0,0.0,0.0)
	var stress = 0.0
	var rot = 0.0

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

func create_joint(pos, rotation_y, scale_vec, mesh):
	var end = MeshInstance.new()
	end.translation = pos
	end.scale = scale_vec
	end.set_mesh(mesh)
	return end

func create_end_joint(pos, rotation_y, isTop, scale_vec, mesh):
	#var core_scale = Vector3(0.9, 0.05, 0.9);
	if mesh == null: return;
	var core_scale = Vector3(0.9, 1.0, 0.9);
	var core_mesh = create_joint(pos, rotation_y, core_scale, mesh);
	if isTop:
		core_mesh.translation.y += 0.1
	else:
		core_mesh.translation.y -= 0.1
		core_mesh.rotate_x(PI)
		core_mesh.rotate_y(PI)
	self.add_child(core_mesh)


func genTree(list):
	var t_scale = Vector3(1.0, 1.0, 1.0);
	create_end_joint(start_position, 0.0, false, t_scale, bottom_shape)
	for node in list:
		self.add_child(create_joint(node.position, 0.0, t_scale, piece_mesh))
	create_end_joint(end_position, 0.0, true, t_scale, top_shape)


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
	hitbox_points += getCollisionDisk(shape, pos, 0, 1)
	showPoints(hitbox_points)
	hitbox_shape.set_points(hitbox_points)
	hitbox.shape = hitbox_shape
	self.add_child(hitbox)

func createHitbox():
	var hitbox = CollisionShape.new()
	var hitbox_shape = ConvexPolygonShape.new()
	var hitbox_points = []
	
	if top_shape:
		createEndHitbox(top_shape, end_position, 1)
	
	hitbox_points += getCollisionDisk(piece_mesh, end_position, 0, 1)
	hitbox_points += getCollisionDisk(piece_mesh, start_position, 0, 1)
	
	if bottom_shape:
		createEndHitbox(bottom_shape, start_position, -1)
	
	showPoints(hitbox_points)
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
	print("RECIEVED RATE:"+str(rate))

# Called when the node enters the scene tree for the first time.
func _ready():
	assembleTree()
	Globals.connect("start_aging", self, "on_aging_start")
	#var button = get_tree().get_root().find_node("AgeOrHumidify",true,false)
	#button.connect("start_aging", self, "on_aging_start")

func _process(delta):
	if Engine.editor_hint and not rendered:
		assembleTree()

#
#func _input(event):
#	if event is InputEventMouseButton:
#		if event.button_index == BUTTON_LEFT and not event.pressed:
#			print("clicked rigidbody")
