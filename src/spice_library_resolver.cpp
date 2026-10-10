#include "spice_library_resolver.h"

#include <godot_cpp/variant/utility_functions.hpp>
#include <fstream>
#include <sstream>
#include <algorithm>
#include <cctype>
#include <filesystem>

namespace godot {

namespace fs = std::filesystem;

static inline std::string to_lower_str(std::string s) {
	std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return std::tolower(c); });
	return s;
}

static inline std::string trim_str(const std::string &s) {
	size_t start = s.find_first_not_of(" \t\r\n");
	if (start == std::string::npos) return "";
	size_t end = s.find_last_not_of(" \t\r\n");
	return s.substr(start, end - start + 1);
}

static inline std::vector<std::string> split_tokens(const std::string &s) {
	std::vector<std::string> tokens;
	std::istringstream iss(s);
	std::string token;
	while (iss >> token) {
		tokens.push_back(token);
	}
	return tokens;
}

void SpiceLibraryResolver::_bind_methods() {
	ClassDB::bind_method(D_METHOD("scan_file", "file_path"), &SpiceLibraryResolver::scan_file);
	ClassDB::bind_method(D_METHOD("scan_directory", "dir_path", "recursive"), &SpiceLibraryResolver::scan_directory, DEFVAL(true));
	ClassDB::bind_method(D_METHOD("register_raw_library", "library_text", "source_name"), &SpiceLibraryResolver::register_raw_library, DEFVAL("memory"));

	ClassDB::bind_method(D_METHOD("has_subcircuit", "name"), &SpiceLibraryResolver::has_subcircuit);
	ClassDB::bind_method(D_METHOD("has_model", "name"), &SpiceLibraryResolver::has_model);
	ClassDB::bind_method(D_METHOD("get_subcircuit_info", "name"), &SpiceLibraryResolver::get_subcircuit_info);
	ClassDB::bind_method(D_METHOD("get_model_info", "name"), &SpiceLibraryResolver::get_model_info);

	ClassDB::bind_method(D_METHOD("get_subcircuit_names"), &SpiceLibraryResolver::get_subcircuit_names);
	ClassDB::bind_method(D_METHOD("get_model_names"), &SpiceLibraryResolver::get_model_names);
	ClassDB::bind_method(D_METHOD("get_subcircuit_pins", "name"), &SpiceLibraryResolver::get_subcircuit_pins);

	ClassDB::bind_method(D_METHOD("resolve_dependencies", "names"), &SpiceLibraryResolver::resolve_dependencies);
	ClassDB::bind_method(D_METHOD("generate_injection_deck", "needed_names"), &SpiceLibraryResolver::generate_injection_deck);
	ClassDB::bind_method(D_METHOD("clear"), &SpiceLibraryResolver::clear);
}

SpiceLibraryResolver::SpiceLibraryResolver() {
}

SpiceLibraryResolver::~SpiceLibraryResolver() {
	clear();
}

void SpiceLibraryResolver::clear() {
	m_subcircuits.clear();
	m_models.clear();
	m_scanned_library_paths.clear();
}

bool SpiceLibraryResolver::scan_file(const String &p_file_path) {
	std::string path_str = p_file_path.utf8().get_data();
	std::ifstream file(path_str);
	if (!file.is_open()) {
		return false;
	}

	std::stringstream buffer;
	buffer << file.rdbuf();
	parse_text_buffer(buffer.str(), path_str);
	m_scanned_library_paths.push_back(path_str);
	return true;
}

int SpiceLibraryResolver::scan_directory(const String &p_dir_path, bool p_recursive) {
	std::string dir_str = p_dir_path.utf8().get_data();
	if (!fs::exists(dir_str) || !fs::is_directory(dir_str)) {
		return 0;
	}

	int count = 0;
	try {
		auto handle_entry = [&](const fs::directory_entry &entry) {
			if (entry.is_regular_file()) {
				std::string ext = to_lower_str(entry.path().extension().string());
				if (ext == ".lib" || ext == ".mod" || ext == ".subckt" || ext == ".cir" || ext == ".sp" || ext == ".spice") {
					std::string filepath = entry.path().string();
					std::ifstream file(filepath);
					if (file.is_open()) {
						std::stringstream buffer;
						buffer << file.rdbuf();
						parse_text_buffer(buffer.str(), filepath);
						m_scanned_library_paths.push_back(filepath);
						count++;
					}
				}
			}
		};

		if (p_recursive) {
			for (const auto &entry : fs::recursive_directory_iterator(dir_str, fs::directory_options::skip_permission_denied)) {
				handle_entry(entry);
			}
		} else {
			for (const auto &entry : fs::directory_iterator(dir_str, fs::directory_options::skip_permission_denied)) {
				handle_entry(entry);
			}
		}
	} catch (...) {
		// Suppress filesystem errors gracefully
	}

	return count;
}

bool SpiceLibraryResolver::register_raw_library(const String &p_library_text, const String &p_source_name) {
	std::string content = p_library_text.utf8().get_data();
	if (content.empty()) return false;
	parse_text_buffer(content, p_source_name.utf8().get_data());
	return true;
}

void SpiceLibraryResolver::parse_text_buffer(const std::string &p_content, const std::string &p_source_file) {
	std::istringstream stream(p_content);
	std::string raw_line;
	std::vector<std::string> lines;

	// SPICE continuation line handling: lines starting with '+' belong to previous line
	while (std::getline(stream, raw_line)) {
		std::string trimmed = trim_str(raw_line);
		if (trimmed.empty()) continue;

		if (trimmed[0] == '+' && !lines.empty()) {
			lines.back() += " " + trim_str(trimmed.substr(1));
		} else {
			lines.push_back(trimmed);
		}
	}

	bool in_subckt = false;
	SpiceSubcircuitInfo cur_subckt;

	for (const auto &line : lines) {
		std::string l_lower = to_lower_str(line);

		// Handle comments
		if (line[0] == '*') {
			continue;
		}

		if (in_subckt) {
			cur_subckt.definition_text += line + "\n";
			if (l_lower.rfind(".ends", 0) == 0) {
				in_subckt = false;
				m_subcircuits[cur_subckt.name] = cur_subckt;
			}
			continue;
		}

		// Detect .subckt
		if (l_lower.rfind(".subckt", 0) == 0) {
			auto tokens = split_tokens(line);
			if (tokens.size() >= 2) {
				in_subckt = true;
				cur_subckt.name = to_lower_str(tokens[1]);
				cur_subckt.pins.clear();
				for (size_t i = 2; i < tokens.size(); ++i) {
					// Parameters can start with params: or par:
					if (to_lower_str(tokens[i]).rfind("params:", 0) == 0 || tokens[i].find('=') != std::string::npos) {
						break;
					}
					cur_subckt.pins.push_back(tokens[i]);
				}
				cur_subckt.definition_text = line + "\n";
				cur_subckt.file_path = p_source_file;
			}
			continue;
		}

		// Detect .model
		if (l_lower.rfind(".model", 0) == 0) {
			auto tokens = split_tokens(line);
			if (tokens.size() >= 3) {
				SpiceModelInfo mod;
				mod.name = to_lower_str(tokens[1]);
				std::string raw_type = tokens[2];
				// Remove potential parentheses attached to type e.g. "npn(" -> "npn"
				size_t paren_idx = raw_type.find('(');
				if (paren_idx != std::string::npos) {
					mod.type = to_lower_str(raw_type.substr(0, paren_idx));
				} else {
					mod.type = to_lower_str(raw_type);
				}
				mod.definition_text = line;
				mod.file_path = p_source_file;
				m_models[mod.name] = mod;
			}
			continue;
		}
	}
}

bool SpiceLibraryResolver::has_subcircuit(const String &p_name) const {
	std::string key = to_lower_str(p_name.utf8().get_data());
	return m_subcircuits.find(key) != m_subcircuits.end();
}

bool SpiceLibraryResolver::has_model(const String &p_name) const {
	std::string key = to_lower_str(p_name.utf8().get_data());
	return m_models.find(key) != m_models.end();
}

Dictionary SpiceLibraryResolver::get_subcircuit_info(const String &p_name) const {
	Dictionary d;
	std::string key = to_lower_str(p_name.utf8().get_data());
	auto it = m_subcircuits.find(key);
	if (it != m_subcircuits.end()) {
		d["name"] = String(it->second.name.c_str());
		PackedStringArray pins;
		for (const auto &p : it->second.pins) {
			pins.append(String(p.c_str()));
		}
		d["pins"] = pins;
		d["pin_count"] = (int64_t)it->second.pins.size();
		d["definition"] = String(it->second.definition_text.c_str());
		d["file_path"] = String(it->second.file_path.c_str());
	}
	return d;
}

Dictionary SpiceLibraryResolver::get_model_info(const String &p_name) const {
	Dictionary d;
	std::string key = to_lower_str(p_name.utf8().get_data());
	auto it = m_models.find(key);
	if (it != m_models.end()) {
		d["name"] = String(it->second.name.c_str());
		d["type"] = String(it->second.type.c_str());
		d["definition"] = String(it->second.definition_text.c_str());
		d["file_path"] = String(it->second.file_path.c_str());
	}
	return d;
}

PackedStringArray SpiceLibraryResolver::get_subcircuit_names() const {
	PackedStringArray arr;
	for (const auto &pair : m_subcircuits) {
		arr.append(String(pair.first.c_str()));
	}
	return arr;
}

PackedStringArray SpiceLibraryResolver::get_model_names() const {
	PackedStringArray arr;
	for (const auto &pair : m_models) {
		arr.append(String(pair.first.c_str()));
	}
	return arr;
}

PackedStringArray SpiceLibraryResolver::get_subcircuit_pins(const String &p_name) const {
	PackedStringArray pins;
	std::string key = to_lower_str(p_name.utf8().get_data());
	auto it = m_subcircuits.find(key);
	if (it != m_subcircuits.end()) {
		for (const auto &p : it->second.pins) {
			pins.append(String(p.c_str()));
		}
	}
	return pins;
}

PackedStringArray SpiceLibraryResolver::resolve_dependencies(const PackedStringArray &p_model_or_subckt_names) const {
	PackedStringArray resolved;
	for (int i = 0; i < p_model_or_subckt_names.size(); ++i) {
		std::string key = to_lower_str(p_model_or_subckt_names[i].utf8().get_data());
		if (m_subcircuits.find(key) != m_subcircuits.end()) {
			resolved.append(String(key.c_str()));
		} else if (m_models.find(key) != m_models.end()) {
			resolved.append(String(key.c_str()));
		}
	}
	return resolved;
}

String SpiceLibraryResolver::generate_injection_deck(const PackedStringArray &p_needed_names) const {
	std::string deck;
	std::unordered_map<std::string, bool> emitted;

	for (int i = 0; i < p_needed_names.size(); ++i) {
		std::string key = to_lower_str(p_needed_names[i].utf8().get_data());
		if (emitted[key]) continue;

		auto sub_it = m_subcircuits.find(key);
		if (sub_it != m_subcircuits.end()) {
			deck += "* --- Subcircuit: " + sub_it->second.name + " ---\n";
			deck += sub_it->second.definition_text;
			deck += "\n";
			emitted[key] = true;
			continue;
		}

		auto mod_it = m_models.find(key);
		if (mod_it != m_models.end()) {
			deck += "* --- Model Card: " + mod_it->second.name + " ---\n";
			deck += mod_it->second.definition_text;
			deck += "\n";
			emitted[key] = true;
			continue;
		}
	}

	return String(deck.c_str());
}

} // namespace godot
