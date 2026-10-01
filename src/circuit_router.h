#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot {

class CircuitRouter : public RefCounted {
	GDCLASS(CircuitRouter, RefCounted)

protected:
	static void _bind_methods();

public:
	enum RoutingDirection {
		DIR_NONE = 0,
		DIR_UP = 1,
		DIR_DOWN = 2,
		DIR_LEFT = 4,
		DIR_RIGHT = 8,
		DIR_ALL = 15
	};

	enum RoutingMode {
		ROUTING_ORTHOGONAL = 0,
		ROUTING_POLYLINE = 1
	};

	CircuitRouter() = default;
	~CircuitRouter() override = default;

	Dictionary route_circuit(const Dictionary &p_circuit_graph);
};

} // namespace godot

VARIANT_ENUM_CAST(godot::CircuitRouter::RoutingDirection);
VARIANT_ENUM_CAST(godot::CircuitRouter::RoutingMode);
