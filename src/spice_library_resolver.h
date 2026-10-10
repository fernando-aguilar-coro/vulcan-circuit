#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/array.hpp>

#include <string>
#include <vector>
#include <unordered_map>

namespace godot {

struct SpiceSubcircuitInfo {
	std::string name;
	std::vector<std::string> pins;
	std::string definition_text;
	std::string file_path;
};

struct SpiceModelInfo {
	std::string name;
	std::string type; // NPN, PNP, D, NMOS, PMOS, VDMOS, etc.
	std::unordered_map<std::string, std::string> parameters;
	std::string definition_text;
	std::string file_path;
};

class SpiceLibraryResolver : public RefCounted {
	GDCLASS(SpiceLibraryResolver, RefCounted)

protected:
	static void _bind_methods();

private:
	std::unordered_map<std::string, SpiceSubcircuitInfo> m_subcircuits;
	std::unordered_map<std::string, SpiceModelInfo> m_models;
	std::vector<std::string> m_scanned_library_paths;

	void parse_text_buffer(const std::string &p_content, const std::string &p_source_file = "");

public:
	SpiceLibraryResolver();
	~SpiceLibraryResolver() override;

	// Filesystem scanning
	bool scan_file(const String &p_file_path);
	int scan_directory(const String &p_dir_path, bool p_recursive = true);
	bool register_raw_library(const String &p_library_text, const String &p_source_name = "memory");

	// Query capabilities
	bool has_subcircuit(const String &p_name) const;
	bool has_model(const String &p_name) const;
	Dictionary get_subcircuit_info(const String &p_name) const;
	Dictionary get_model_info(const String &p_name) const;

	PackedStringArray get_subcircuit_names() const;
	PackedStringArray get_model_names() const;
	PackedStringArray get_subcircuit_pins(const String &p_name) const;

	// Netlist injection and dependency resolution
	PackedStringArray resolve_dependencies(const PackedStringArray &p_model_or_subckt_names) const;
	String generate_injection_deck(const PackedStringArray &p_needed_names) const;
	void clear();
};

} // namespace godot
