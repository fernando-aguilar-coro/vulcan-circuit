class_name StarJunctionRouter
extends RefCounted

## StarJunctionRouter: Implements EDA Star-Junction routing to eliminate duplicate wire segments
## and place solder dots at multi-wire junctions.


const GRID_SNAP: float = 20.0
const ORIGIN: Vector2 = Vector2(200.0, 180.0)

static func route_mesh_wires(
	components: Dictionary,
	comp_placement_map: Dictionary,
	node_to_pins: Dictionary,
	node_canvas: Dictionary
) -> Array[CircuitWire]:
	var wires: Array[CircuitWire] = []
	var wire_idx := 1

	for nid in node_to_pins:
		var all_pins: Array = node_to_pins[nid]
		var active_pins: Array[String] = []

		for pid in all_pins:
			var cid = pid.split(":")[0]
			var comp: CircuitComponent = components.get(cid)
			if comp and not comp.is_virtual:
				active_pins.append(pid)

		if active_pins.size() < 2:
			continue

		var raw_j: Vector2 = node_canvas.get(nid, ORIGIN)
		var junction = Vector2(
			round(raw_j.x / GRID_SNAP) * GRID_SNAP,
			round(raw_j.y / GRID_SNAP) * GRID_SNAP
		)

		if active_pins.size() == 2:
			# Direct two-point connection (Degree 2) - No solder dot needed
			var pin_a = active_pins[0]
			var pin_b = active_pins[1]
			var p_a = _get_pin_pos(components, pin_a)
			var p_b = _get_pin_pos(components, pin_b)
			var bp_a = comp_placement_map.get(pin_a.split(":")[0])
			var bp_b = comp_placement_map.get(pin_b.split(":")[0])

			var waypoints = _route_two_pins(components, pin_a, p_a, bp_a, pin_b, p_b, bp_b, junction)
			wires.append(CircuitWire.new("w" + str(wire_idx), pin_a, pin_b, waypoints))
			wire_idx += 1
		else:
			# Multi-pin Star Junction (Degree >= 3)
			# Solder dot (JUNCTION) at the node coordinate
			var j_id = "J_" + nid
			var j_comp = CircuitComponent.new(j_id, CircuitComponent.Type.JUNCTION, junction, "dot")
			components[j_id] = j_comp

			for pin_id in active_pins:
				var p_world = _get_pin_pos(components, pin_id)
				var bp = comp_placement_map.get(pin_id.split(":")[0])
				var waypoints = _route_pin_to_point(components, pin_id, p_world, junction, bp)
				wires.append(CircuitWire.new("w" + str(wire_idx), pin_id, j_id + ":dot", waypoints))
				wire_idx += 1

	return wires

static func _route_pin_to_point(
	components: Dictionary,
	pin_id: String,
	p_from: Vector2,
	p_to: Vector2,
	bp: BranchClassifier.BranchPlacement
) -> PackedVector2Array:
	var waypoints = PackedVector2Array()
	if p_from.distance_squared_to(p_to) < 4.0:
		return waypoints

	if bp and bp.is_spanning:
		# Elevated branch: horizontal along elevated track, then vertical to junction
		var elevated_corner = Vector2(p_to.x, p_from.y)
		waypoints.append(elevated_corner)
		return waypoints

	var dx = abs(p_to.x - p_from.x)
	var dy = abs(p_to.y - p_from.y)
	if dx < 2.0 or dy < 2.0:
		return waypoints

	# Determine pin physical exit orientation
	var is_horiz = _is_horizontal_exit(components, pin_id, p_from, p_to)
	var corner = Vector2(p_to.x, p_from.y) if is_horiz else Vector2(p_from.x, p_to.y)
	corner = Vector2(round(corner.x / GRID_SNAP) * GRID_SNAP, round(corner.y / GRID_SNAP) * GRID_SNAP)
	waypoints.append(corner)
	return waypoints

static func _route_two_pins(
	components: Dictionary,
	pin_a: String,
	p_a: Vector2,
	bp_a: BranchClassifier.BranchPlacement,
	_pin_b: String,
	p_b: Vector2,
	bp_b: BranchClassifier.BranchPlacement,
	junction: Vector2
) -> PackedVector2Array:
	var waypoints = PackedVector2Array()

	if bp_a and bp_a.is_spanning:
		waypoints.append(Vector2(junction.x, p_a.y))
		if junction.distance_squared_to(p_b) > 4.0:
			waypoints.append(junction)
		return waypoints
	if bp_b and bp_b.is_spanning:
		if junction.distance_squared_to(p_a) > 4.0:
			waypoints.append(junction)
		waypoints.append(Vector2(junction.x, p_b.y))
		return waypoints

	var dx = abs(p_b.x - p_a.x)
	var dy = abs(p_b.y - p_a.y)
	if dx < 2.0 or dy < 2.0:
		return waypoints

	var is_horiz_a = _is_horizontal_exit(components, pin_a, p_a, p_b)
	var corner = Vector2(p_b.x, p_a.y) if is_horiz_a else Vector2(p_a.x, p_b.y)
	corner = Vector2(round(corner.x / GRID_SNAP) * GRID_SNAP, round(corner.y / GRID_SNAP) * GRID_SNAP)
	waypoints.append(corner)
	return waypoints

static func _is_horizontal_exit(components: Dictionary, pin_id: String, p_from: Vector2, p_to: Vector2) -> bool:
	var parts = pin_id.split(":")
	var comp: CircuitComponent = components.get(parts[0])
	if comp:
		var pin = comp.get_pin(parts[1]) if parts.size() > 1 else null
		if pin and pin.local_position.length_squared() > 1.0:
			var rot_rad = deg_to_rad(comp.rotation_deg)
			var local_dir = pin.local_position.rotated(rot_rad)
			return abs(local_dir.x) >= abs(local_dir.y)
	return abs(p_to.x - p_from.x) >= abs(p_to.y - p_from.y)

static func _get_pin_pos(components: Dictionary, pin_id: String) -> Vector2:
	var parts = pin_id.split(":")
	if parts.size() < 2:
		return Vector2.ZERO
	var comp: CircuitComponent = components.get(parts[0])
	return comp.get_pin_world_position(parts[1]) if comp else Vector2.ZERO
