class_name CircuitPin
extends RefCounted

var id: String = ""
var component_id: String = ""
var name: String = ""
var local_position: Vector2 = Vector2.ZERO
var is_ground: bool = false

func _init(p_component_id: String = "", p_name: String = "", p_local_pos: Vector2 = Vector2.ZERO, p_is_ground: bool = false) -> void:
	component_id = p_component_id
	name = p_name
	id = component_id + ":" + name
	local_position = p_local_pos
	is_ground = p_is_ground

func get_world_position(comp_pos: Vector2, comp_rotation_deg: int) -> Vector2:
	var rad = deg_to_rad(comp_rotation_deg)
	return comp_pos + local_position.rotated(rad)

func duplicate_pin(new_comp_id: String = "") -> RefCounted:
	var cid = new_comp_id if new_comp_id != "" else component_id
	return get_script().new(cid, name, local_position, is_ground)
