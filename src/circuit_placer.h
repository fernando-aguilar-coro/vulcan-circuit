#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class CircuitPlacer : public RefCounted {
	GDCLASS(CircuitPlacer, RefCounted)

protected:
	static void _bind_methods();

public:
	CircuitPlacer() = default;
	~CircuitPlacer() override = default;

	Dictionary place_circuit(const Dictionary &p_netlist_data);
};

} // namespace godot
