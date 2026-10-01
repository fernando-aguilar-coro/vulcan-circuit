class_name CircuitWire
extends RefCounted

var id: String = ""
var from_pin_id: String = ""
var to_pin_id: String = ""
var waypoints: PackedVector2Array = PackedVector2Array()

func _init(p_id: String = "", p_from_pin: String = "", p_to_pin: String = "", p_waypoints: PackedVector2Array = PackedVector2Array()) -> void:
	id = p_id
	from_pin_id = p_from_pin
	to_pin_id = p_to_pin
	waypoints = p_waypoints

func clone() -> RefCounted:
	var w = get_script().new(id, from_pin_id, to_pin_id, waypoints.duplicate())
	return w
