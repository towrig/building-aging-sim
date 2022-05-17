extends Area

signal something_entered(target, target_shape_idx, self_id, self_shape_idx)
signal something_exited(target, target_shape_idx, self_id, self_shape_idx)

# Called when the node enters the scene tree for the first time.
func _ready():
	connect("area_shape_exited", self, "_on_area_shape_exited")
	connect("area_shape_entered", self, "_on_area_shape_entered")
	connect("body_shape_entered", self, "_on_body_shape_entered")
	connect("body_shape_exited", self, "_on_body_shape_exited")


func _on_area_shape_entered(area_rid, area, area_shape_index, local_shape_index ):
	if area.get_parent().get_instance_id() != get_parent().get_instance_id():
		emit_signal("something_entered", area, area_shape_index, get_instance_id(), local_shape_index)

func _on_area_shape_exited(area_rid, area, area_shape_index, local_shape_index ):
	emit_signal("something_exited", area, area_shape_index, get_instance_id(), local_shape_index)

func _on_body_shape_entered(body_id, body, body_shape_index, local_shape_index):
	if body.get_instance_id() != get_parent().get_instance_id():
		emit_signal("something_entered", body, body_shape_index, get_instance_id(), local_shape_index)

func _on_body_shape_exited(body_id, body, body_shape_index, local_shape_index):
	emit_signal("something_exited", body, body_shape_index, get_instance_id(), local_shape_index)
