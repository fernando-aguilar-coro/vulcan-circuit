class_name CircuitReconstructor
extends RefCounted

## CircuitReconstructor: Orchestrates netlist parsing and 2D dipole placement.

static func parse_and_build(ai_text: String) -> Dictionary:
	# 1. Parse raw SPICE text / JSON into parsed nodes and dipole components
	var parse_result = NetlistParser.parse(ai_text)
	if parse_result.components.is_empty():
		return {
			"success": false,
			"components": {},
			"wires": []
		}

	# 2. Compute 2D dipole placements and orthogonal Manhattan wires via DipolePlacer
	var result = DipolePlacer.place_circuit(parse_result)
	if not result.get("success", false):
		return {
			"success": false,
			"components": {},
			"wires": []
		}

	var components: Dictionary = result.get("components", {})
	var wires: Array = result.get("wires", [])

	return {
		"success": true,
		"components": components,
		"wires": wires
	}
