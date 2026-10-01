class_name WireRouter
extends RefCounted


static func get_wire_points(p1: Vector2, p2: Vector2, waypoints: PackedVector2Array) -> Array[Vector2]:
	if waypoints.size() > 0:
		var pts: Array[Vector2] = [p1]
		for wp in waypoints:
			pts.append(wp)
		pts.append(p2)
		return pts

	# Fallback orthogonal (Manhattan) routing: avoid diagonal crossings
	if abs(p1.x - p2.x) < 2.0 or abs(p1.y - p2.y) < 2.0:
		return [p1, p2]

	var mid_x = (p1.x + p2.x) / 2.0
	return [p1, Vector2(mid_x, p1.y), Vector2(mid_x, p2.y), p2]

static func dist_point_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab = b - a
	var ab_len_sq = ab.length_squared()
	if ab_len_sq == 0.0:
		return p.distance_to(a)
	var t = clamp((p - a).dot(ab) / ab_len_sq, 0.0, 1.0)
	var proj = a + t * ab
	return p.distance_to(proj)

static func find_wire_at_pos(pos: Vector2, wires: Array, state: CircuitState, threshold: float = 8.0) -> String:
	if not state:
		return ""
	for w in wires:
		var p1 = state.get_pin_world_pos(w.from_pin_id)
		var p2 = state.get_pin_world_pos(w.to_pin_id)
		var pts = get_wire_points(p1, p2, w.waypoints)
		for i in range(pts.size() - 1):
			if dist_point_to_segment(pos, pts[i], pts[i + 1]) <= threshold:
				return w.id
	return ""

## Routes all circuit wires using GDExtension C++ libavoid or clean orthogonal routing
static func route_all_wires_with_libavoid(components: Dictionary, wires: Array) -> bool:
	if not ClassDB.class_exists("CircuitRouter"):
		_route_simple_orthogonal(components, wires)
		return true

	var router = ClassDB.instantiate("CircuitRouter")
	if not router:
		_route_simple_orthogonal(components, wires)
		return true

	var obstacles_arr: Array = []
	for comp_id in components.keys():
		var comp: CircuitComponent = components[comp_id]
		var min_x = comp.position.x - 25.0
		var max_x = comp.position.x + 25.0
		var min_y = comp.position.y - 25.0
		var max_y = comp.position.y + 25.0

		var pins_arr: Array = []
		for pin in comp.pins:
			var wpos = pin.get_world_position(comp.position, comp.rotation_deg)
			min_x = min(min_x, wpos.x - 5.0)
			max_x = max(max_x, wpos.x + 5.0)
			min_y = min(min_y, wpos.y - 5.0)
			max_y = max(max_y, wpos.y + 5.0)

			var dir_flag = _get_pin_dir_flag(comp.position, wpos)
			pins_arr.append({
				"id": hash(pin.id),
				"pos": wpos,
				"dir": dir_flag
			})

		var rect = Rect2(min_x, min_y, max(max_x - min_x, 10.0), max(max_y - min_y, 10.0))
		obstacles_arr.append({
			"id": comp.id,
			"rect": rect,
			"pins": pins_arr
		})

	var connections_arr: Array = []
	for wire in wires:
		var from_parts = wire.from_pin_id.split(":")
		var to_parts = wire.to_pin_id.split(":")
		if from_parts.size() >= 2 and to_parts.size() >= 2:
			var from_comp_id = from_parts[0]
			var to_comp_id = to_parts[0]
			if components.has(from_comp_id) and components.has(to_comp_id):
				connections_arr.append({
					"id": wire.id,
					"from_obstacle": from_comp_id,
					"from_pin": hash(wire.from_pin_id),
					"to_obstacle": to_comp_id,
					"to_pin": hash(wire.to_pin_id)
				})

	if connections_arr.is_empty():
		return true

	var graph_data: Dictionary = {
		"routing_mode": 0, # Orthogonal
		"segment_penalty": 50.0,
		"nudging_distance": 12.0,
		"shape_buffer_distance": 10.0,
		"nudge_connected_to_shapes": true,
		"obstacles": obstacles_arr,
		"connections": connections_arr
	}

	var result: Dictionary = router.route_circuit(graph_data)
	if result.get("success", false) and result.has("routes"):
		var routes: Dictionary = result["routes"]
		for wire in wires:
			if routes.has(wire.id):
				var full_route: PackedVector2Array = routes[wire.id]
				if full_route.size() >= 3:
					wire.waypoints = full_route.slice(1, full_route.size() - 1)
				else:
					wire.waypoints = PackedVector2Array()
		return true

	return false

static func _get_pin_dir_flag(center: Vector2, pin_pos: Vector2) -> int:
	var delta = pin_pos - center
	if abs(delta.x) > abs(delta.y):
		return 4 if delta.x < 0 else 8 # Left (4) or Right (8)
	else:
		return 1 if delta.y < 0 else 2 # Up (1) or Down (2)

static func _route_simple_orthogonal(components: Dictionary, wires: Array) -> void:
	for wire in wires:
		# If wire already has deterministic waypoints (e.g. from DipolePlacer), preserve them
		if not wire.waypoints.is_empty():
			continue
		var p1 = _get_pin_pos(components, wire.from_pin_id)
		var p2 = _get_pin_pos(components, wire.to_pin_id)
		if abs(p1.x - p2.x) > 2.0 and abs(p1.y - p2.y) > 2.0:
			var mid_x = (p1.x + p2.x) / 2.0
			wire.waypoints = PackedVector2Array([Vector2(mid_x, p1.y), Vector2(mid_x, p2.y)])
		else:
			wire.waypoints = PackedVector2Array()

static func _get_pin_pos(components: Dictionary, pin_id: String) -> Vector2:
	var parts = pin_id.split(":")
	if parts.size() < 2: return Vector2.ZERO
	var comp: CircuitComponent = components.get(parts[0])
	return comp.get_pin_world_position(parts[1]) if comp else Vector2.ZERO
