extends Node

signal toggle_aging(rate, value)
signal toggle_structure(value)
signal break_happened(object_id)
signal set_debug(value)

var tickrate = 1.0

func stop_physics():
	var scene_root = get_tree().root.get_child(1)
	for child in scene_root.get_children():
		if child.has_method("should_break"): # is loginstance
			child.set_mode(1) #0 = rigidbody, 1 = static

func start_physics():
	var scene_root = get_tree().root.get_child(1)
	for child in scene_root.get_children():
		if child.has_method("should_break"):
			child.set_mode(0)
