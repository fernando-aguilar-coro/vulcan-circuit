#include "circuit_simulator.h"
#include "ngspice/sharedspice.h"

#include <godot_cpp/variant/utility_functions.hpp>

#include <sstream>
#include <iostream>
#include <cstring>
#include <string>

#if defined(_WIN32) || defined(_WIN64)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#else
#include <dlfcn.h>
#endif

namespace godot {

int CircuitSimulator::cb_send_char(char *msg, int id, void *user_data) {
	if (user_data && msg) {
		CircuitSimulator *sim = static_cast<CircuitSimulator *>(user_data);
		sim->append_log(msg);
	}
	return 0;
}

int CircuitSimulator::cb_send_stat(char *msg, int id, void *user_data) {
	if (user_data && msg) {
		CircuitSimulator *sim = static_cast<CircuitSimulator *>(user_data);
		sim->append_log(msg);
	}
	return 0;
}

int CircuitSimulator::cb_controlled_exit(int status, bool immediate, bool is_error, int id, void *user_data) {
	if (user_data) {
		CircuitSimulator *sim = static_cast<CircuitSimulator *>(user_data);
		std::string exit_msg = "[ngspice exit code: " + std::to_string(status) + "]\n";
		sim->append_log(exit_msg.c_str());
	}
	return 0;
}

void CircuitSimulator::_bind_methods() {
	ClassDB::bind_method(D_METHOD("init_simulator", "dll_path"), &CircuitSimulator::init_simulator, DEFVAL(""));
	ClassDB::bind_method(D_METHOD("is_available"), &CircuitSimulator::is_available);
	ClassDB::bind_method(D_METHOD("simulate_netlist", "netlist_text"), &CircuitSimulator::simulate_netlist);
	ClassDB::bind_method(D_METHOD("execute_command", "cmd"), &CircuitSimulator::execute_command);
	ClassDB::bind_method(D_METHOD("get_last_log"), &CircuitSimulator::get_last_log);

	ClassDB::bind_method(D_METHOD("start_live_sim", "netlist_text"), &CircuitSimulator::start_live_sim);
	ClassDB::bind_method(D_METHOD("stop_live_sim"), &CircuitSimulator::stop_live_sim);
	ClassDB::bind_method(D_METHOD("is_sim_running"), &CircuitSimulator::is_sim_running);
	ClassDB::bind_method(D_METHOD("alter_component_value", "device_id", "param_val"), &CircuitSimulator::alter_component_value);
	ClassDB::bind_method(D_METHOD("get_live_vector_snapshot"), &CircuitSimulator::get_live_vector_snapshot);
	ClassDB::bind_method(D_METHOD("compute_current_particles", "wire_pts", "current_amps", "accum_time", "spacing"), &CircuitSimulator::compute_current_particles, DEFVAL(24.0));

	ClassDB::bind_method(D_METHOD("scan_library_file", "file_path"), &CircuitSimulator::scan_library_file);
	ClassDB::bind_method(D_METHOD("scan_library_directory", "dir_path", "recursive"), &CircuitSimulator::scan_library_directory, DEFVAL(true));
	ClassDB::bind_method(D_METHOD("register_raw_library", "library_text", "source_name"), &CircuitSimulator::register_raw_library, DEFVAL("memory"));
	ClassDB::bind_method(D_METHOD("get_library_catalog"), &CircuitSimulator::get_library_catalog);
	ClassDB::bind_method(D_METHOD("resolve_subcircuits_and_models", "needed_names"), &CircuitSimulator::resolve_subcircuits_and_models);

	ClassDB::bind_method(D_METHOD("get_device_internal_parameters", "device_id", "type"), &CircuitSimulator::get_device_internal_parameters);
	ClassDB::bind_method(D_METHOD("query_internal_vector", "query"), &CircuitSimulator::query_internal_vector);
}

CircuitSimulator::CircuitSimulator() {
	m_library_resolver.instantiate();
	init_simulator("");
}

CircuitSimulator::~CircuitSimulator() {
	if (m_dll_handle) {
#if defined(_WIN32) || defined(_WIN64)
		FreeLibrary((HMODULE)m_dll_handle);
#else
		dlclose(m_dll_handle);
#endif
		m_dll_handle = nullptr;
	}
}

void CircuitSimulator::append_log(const char *msg) {
	if (msg) {
		m_last_log += msg;
	}
}

String CircuitSimulator::get_last_log() const {
	return String(m_last_log.c_str());
}

bool CircuitSimulator::is_available() const {
	return m_is_initialized && (m_dll_handle != nullptr);
}

// Helper: safely convert a Godot String to std::wstring
static std::wstring godot_str_to_wstring(const godot::String &s) {
	std::string utf8_str = s.utf8().get_data();
#if defined(_WIN32) || defined(_WIN64)
	if (utf8_str.empty()) return L"";
	int len = MultiByteToWideChar(CP_UTF8, 0, utf8_str.c_str(), -1, nullptr, 0);
	std::wstring wstr(len, 0);
	MultiByteToWideChar(CP_UTF8, 0, utf8_str.c_str(), -1, &wstr[0], len);
	if (!wstr.empty() && wstr.back() == L'\0') wstr.pop_back();
	return wstr;
#else
	return std::wstring(utf8_str.begin(), utf8_str.end());
#endif
}

bool CircuitSimulator::init_simulator(const String &p_dll_path) {
	if (m_is_initialized) {
		return true;
	}

	std::vector<std::wstring> candidate_paths;
	if (!p_dll_path.is_empty()) {
		candidate_paths.push_back(godot_str_to_wstring(p_dll_path));
	} else {
		candidate_paths.push_back(L"C:/Spice64/Spice64_dll/dll-vs/ngspice-34.dll");
		candidate_paths.push_back(L"C:/Spice64/Spice64_dll/dll-mingw/ngspice-34.dll");
		candidate_paths.push_back(L"C:/fer/Spice64/bin/ngspice.dll");
		candidate_paths.push_back(L"ngspice-34.dll");
		candidate_paths.push_back(L"ngspice.dll");
	}

	for (const auto &wpath : candidate_paths) {
#if defined(_WIN32) || defined(_WIN64)
		HMODULE hMod = LoadLibraryW(wpath.c_str());
		if (hMod) {
			m_dll_handle = (void *)hMod;
			break;
		}
#else
		std::string spath(wpath.begin(), wpath.end());
		void *handle = dlopen(spath.c_str(), RTLD_NOW | RTLD_GLOBAL);
		if (handle) {
			m_dll_handle = handle;
			break;
		}
#endif
	}

	if (!m_dll_handle) {
		m_last_log = "Error: Could not load ngspice dynamic library.\n";
		return false;
	}

#if defined(_WIN32) || defined(_WIN64)
	#define RESOLVE_SYM(fn_name) p_##fn_name = (void*)GetProcAddress((HMODULE)m_dll_handle, #fn_name)
#else
	#define RESOLVE_SYM(fn_name) p_##fn_name = dlsym(m_dll_handle, #fn_name)
#endif

	RESOLVE_SYM(ngSpice_Init);
	RESOLVE_SYM(ngSpice_Command);
	RESOLVE_SYM(ngSpice_Circ);
	RESOLVE_SYM(ngGet_Vec_Info);
	RESOLVE_SYM(ngSpice_CurPlot);
	RESOLVE_SYM(ngSpice_AllPlots);
	RESOLVE_SYM(ngSpice_AllVecs);
	RESOLVE_SYM(ngSpice_running);

	if (!p_ngSpice_Init || !p_ngSpice_Command || !p_ngSpice_Circ || !p_ngGet_Vec_Info) {
		m_last_log = "Error: ngspice missing required interface functions.\n";
		return false;
	}

	auto init_fn = (int (*)(SendChar*, SendStat*, ControlledExit*, SendData*, SendInitData*, BGThreadRunning*, void*))p_ngSpice_Init;
	int ret = init_fn(cb_send_char, cb_send_stat, cb_controlled_exit, nullptr, nullptr, nullptr, this);

	m_is_initialized = (ret == 0);
	return m_is_initialized;
}

Dictionary CircuitSimulator::simulate_netlist(const String &p_netlist_text) {
	Dictionary result;
	result["success"] = false;
	m_last_log.clear();

	if (!is_available()) {
		if (!init_simulator("")) {
			result["error"] = "ngspice library not initialized or unavailable.";
			result["log"] = get_last_log();
			return result;
		}
	}

	// Split netlist into lines
	PackedStringArray raw_lines = p_netlist_text.split("\n", false);
	std::vector<std::string> lines;
	lines.push_back("ProtoAI Circuit Netlist"); // Title card

	for (int i = 0; i < raw_lines.size(); ++i) {
		String l = raw_lines[i].strip_edges();
		if (!l.is_empty() && !l.begins_with("*")) {
			// Skip title if user provided one, skip end card since we add it
			if (l.to_lower() == ".end") {
				continue;
			}
			lines.push_back(l.utf8().get_data());
		}
	}
	lines.push_back(".end");

	std::vector<char *> circ_ptrs;
	for (auto &str : lines) {
		circ_ptrs.push_back(&str[0]);
	}
	circ_ptrs.push_back(nullptr);

	auto circ_fn = (int (*)(char**))p_ngSpice_Circ;
	auto cmd_fn = (int (*)(char*))p_ngSpice_Command;
	auto cur_plot_fn = (char* (*)(void))p_ngSpice_CurPlot;
	auto all_vecs_fn = (char** (*)(char*))p_ngSpice_AllVecs;
	auto vec_info_fn = (pvector_info (*)(char*))p_ngGet_Vec_Info;

	int c_ret = circ_fn(circ_ptrs.data());
	if (c_ret != 0) {
		result["error"] = "Error passing circuit to ngspice (code: " + String::num_int64(c_ret) + ").";
		result["log"] = get_last_log();
		return result;
	}

	// Run Operating Point analysis by default
	cmd_fn((char*)"op");

	char *cur_plot = cur_plot_fn();
	Dictionary node_voltages;
	Dictionary branch_currents;
	Dictionary all_vectors;

	if (cur_plot) {
		char **vecs = all_vecs_fn(cur_plot);
		if (vecs) {
			for (int i = 0; vecs[i] != nullptr; ++i) {
				char *vname = vecs[i];
				pvector_info vinfo = vec_info_fn(vname);
				if (vinfo && vinfo->v_realdata && vinfo->v_length > 0) {
					String name_str = String(vname).to_lower();
					double val = vinfo->v_realdata[0];

					if (vinfo->v_length == 1) {
						all_vectors[name_str] = val;
						if (name_str.begins_with("v(") && name_str.ends_with(")")) {
							String node_name = name_str.substr(2, name_str.length() - 3);
							node_voltages[node_name] = val;
						} else if (name_str.begins_with("i(") && name_str.ends_with(")")) {
							String branch_name = name_str.substr(2, name_str.length() - 3);
							branch_currents[branch_name] = val;
						}
					} else {
						PackedFloat64Array arr;
						for (int k = 0; k < vinfo->v_length; ++k) {
							arr.append(vinfo->v_realdata[k]);
						}
						all_vectors[name_str] = arr;
					}
				}
			}
		}
	}

	result["success"] = true;
	result["node_voltages"] = node_voltages;
	result["branch_currents"] = branch_currents;
	result["all_vectors"] = all_vectors;
	result["log"] = get_last_log();
	return result;
}

Dictionary CircuitSimulator::execute_command(const String &p_cmd) {
	Dictionary result;
	result["success"] = false;
	m_last_log.clear();

	if (!is_available()) {
		result["error"] = "Simulator not initialized.";
		return result;
	}

	auto cmd_fn = (int (*)(char*))p_ngSpice_Command;
	std::string cmd_str = p_cmd.utf8().get_data();
	int ret = cmd_fn(&cmd_str[0]);

	result["success"] = (ret == 0);
	result["return_code"] = ret;
	result["log"] = get_last_log();
	return result;
}

bool CircuitSimulator::start_live_sim(const String &p_netlist_text) {
	if (!is_available()) {
		if (!init_simulator("")) return false;
	}

	// First load circuit netlist deck
	simulate_netlist(p_netlist_text);

	auto cmd_fn = (int (*)(char*))p_ngSpice_Command;
	if (!cmd_fn) return false;

	// Launch background run or continuous transient
	int ret = cmd_fn((char*)"bg_run");
	return (ret == 0);
}

bool CircuitSimulator::stop_live_sim() {
	if (!is_available()) return false;
	auto cmd_fn = (int (*)(char*))p_ngSpice_Command;
	if (!cmd_fn) return false;
	int ret = cmd_fn((char*)"bg_halt");
	return (ret == 0);
}

bool CircuitSimulator::is_sim_running() const {
	if (!m_dll_handle || !p_ngSpice_running) return false;
	auto running_fn = (bool (*)(void))p_ngSpice_running;
	return running_fn();
}

bool CircuitSimulator::alter_component_value(const String &p_device_id, const String &p_param_val) {
	if (!is_available()) return false;
	auto cmd_fn = (int (*)(char*))p_ngSpice_Command;
	if (!cmd_fn) return false;

	String cmd = "alter " + p_device_id + " = " + p_param_val;
	std::string s = cmd.utf8().get_data();
	int ret = cmd_fn(&s[0]);
	return (ret == 0);
}

Dictionary CircuitSimulator::get_live_vector_snapshot() {
	Dictionary result;
	Dictionary node_voltages;
	Dictionary branch_currents;

	if (!is_available() || !p_ngSpice_CurPlot || !p_ngSpice_AllVecs || !p_ngGet_Vec_Info) {
		result["node_voltages"] = node_voltages;
		result["branch_currents"] = branch_currents;
		return result;
	}

	auto cur_plot_fn = (char* (*)(void))p_ngSpice_CurPlot;
	auto all_vecs_fn = (char** (*)(char*))p_ngSpice_AllVecs;
	auto vec_info_fn = (pvector_info (*)(char*))p_ngGet_Vec_Info;

	char *cur_plot = cur_plot_fn();
	if (cur_plot) {
		char **vecs = all_vecs_fn(cur_plot);
		if (vecs) {
			for (int i = 0; vecs[i] != nullptr; ++i) {
				char *vname = vecs[i];
				pvector_info vinfo = vec_info_fn(vname);
				if (vinfo && vinfo->v_realdata && vinfo->v_length > 0) {
					String name_str = String(vname).to_lower();
					double val = vinfo->v_realdata[vinfo->v_length - 1]; // Latest time point
					if (name_str.begins_with("v(") && name_str.ends_with(")")) {
						String node_name = name_str.substr(2, name_str.length() - 3);
						node_voltages[node_name] = val;
					} else if (name_str.begins_with("i(") && name_str.ends_with(")")) {
						String branch_name = name_str.substr(2, name_str.length() - 3);
						branch_currents[branch_name] = val;
					}
				}
			}
		}
	}

	result["node_voltages"] = node_voltages;
	result["branch_currents"] = branch_currents;
	return result;
}

static double helper_get_voltage(const Dictionary &v_map, const String &node_name) {
	if (node_name == "0") return 0.0;
	if (v_map.has(node_name)) return (double)v_map[node_name];
	String lower = node_name.to_lower();
	if (v_map.has(lower)) return (double)v_map[lower];
	String upper = node_name.to_upper();
	if (v_map.has(upper)) return (double)v_map[upper];
	return 0.0;
}

Dictionary CircuitSimulator::evaluate_component_telemetry(int p_type, const String &p_id, const String &p_val, const Dictionary &p_nodes, const Dictionary &p_voltages, const Dictionary &p_currents) {
	Dictionary telem;
	telem["id"] = p_id;
	telem["type"] = p_type;
	telem["value"] = p_val;

	// CircuitComponent.Type enum mapping:
	// 0: RESISTOR, 1: VOLTAGE_SOURCE, 2: CURRENT_SOURCE, 3: GROUND, 4: CAPACITOR, 5: INDUCTOR, 6: DIODE
	// 7: BJT_NPN, 8: BJT_PNP, 9: OPAMP, 10: POTENTIOMETER
	// 21+: GATE_AND, GATE_OR, GATE_NOT, GATE_NAND, GATE_NOR, GATE_XOR
	if (p_type == 0) { // RESISTOR
		String n1 = p_nodes.get(p_id + ":p1", "0");
		String n2 = p_nodes.get(p_id + ":p2", "0");
		double v1 = helper_get_voltage(p_voltages, n1);
		double v2 = helper_get_voltage(p_voltages, n2);
		double v_drop = std::abs(v1 - v2);
		double r_val = 1000.0; // default 1k
		// Parse standard multiplier
		String s = p_val.strip_edges().to_lower();
		double mult = 1.0;
		if (s.ends_with("meg")) { mult = 1e6; s = s.substr(0, s.length() - 3); }
		else if (s.ends_with("k")) { mult = 1e3; s = s.substr(0, s.length() - 1); }
		else if (s.ends_with("m")) { mult = 1e-3; s = s.substr(0, s.length() - 1); }
		else if (s.ends_with("u")) { mult = 1e-6; s = s.substr(0, s.length() - 1); }
		double parsed = s.to_float();
		if (parsed > 0.0) r_val = parsed * mult;

		double current = (r_val > 0.0) ? (v_drop / r_val) : 0.0;
		double power = v_drop * current;

		telem["v_drop"] = v_drop;
		telem["current"] = current;
		telem["power"] = power;
		telem["resistance"] = r_val;
		telem["state_str"] = "Normal";
	}
	else if (p_type == 1) { // VOLTAGE_SOURCE
		String n_pos = p_nodes.get(p_id + ":pos", "0");
		String n_neg = p_nodes.get(p_id + ":neg", "0");
		double v_pos = helper_get_voltage(p_voltages, n_pos);
		double v_neg = helper_get_voltage(p_voltages, n_neg);
		double v_src = v_pos - v_neg;
		String b_name = p_id.to_lower() + "#branch";
		double curr = 0.0;
		if (p_currents.has(b_name)) curr = std::abs((double)p_currents[b_name]);
		else if (p_currents.has(p_id + "#branch")) curr = std::abs((double)p_currents[p_id + "#branch"]);

		telem["v_drop"] = v_src;
		telem["current"] = curr;
		telem["power"] = std::abs(v_src * curr);
		telem["state_str"] = "Active Source";
	}
	else if (p_type == 6) { // DIODE
		String n_a = p_nodes.get(p_id + ":anode", "0");
		String n_k = p_nodes.get(p_id + ":cathode", "0");
		double v_a = helper_get_voltage(p_voltages, n_a);
		double v_k = helper_get_voltage(p_voltages, n_k);
		double v_d = v_a - v_k;
		bool is_conducting = (v_d >= 0.65);
		telem["v_drop"] = v_d;
		telem["state_str"] = is_conducting ? "Conducting (ON)" : "Reverse Biased (OFF)";

		// Internal small-signal and dynamic extraction
		Dictionary internals = get_device_internal_parameters(p_id, p_type);
		if (!internals.is_empty()) {
			telem["internals"] = internals;
			if (internals.has("id")) telem["current"] = std::abs((double)internals["id"]);
			if (internals.has("p")) telem["power"] = std::abs((double)internals["p"]);
		}
	}
	else if (p_type == 7 || p_type == 8) { // BJT_NPN / BJT_PNP
		String n_c = p_nodes.get(p_id + ":C", "0");
		String n_b = p_nodes.get(p_id + ":B", "0");
		String n_e = p_nodes.get(p_id + ":E", "0");
		double vc = helper_get_voltage(p_voltages, n_c);
		double vb = helper_get_voltage(p_voltages, n_b);
		double ve = helper_get_voltage(p_voltages, n_e);

		double vbe = vb - ve;
		double vce = vc - ve;
		telem["v_be"] = vbe;
		telem["v_ce"] = vce;
		if (p_type == 7) { // NPN
			if (vbe < 0.6) telem["state_str"] = "Cutoff";
			else if (vce < 0.2) telem["state_str"] = "Saturation";
			else telem["state_str"] = "Active Forward";
		} else { // PNP
			if (-vbe < 0.6) telem["state_str"] = "Cutoff";
			else if (-vce < 0.2) telem["state_str"] = "Saturation";
			else telem["state_str"] = "Active Forward";
		}

		// Internal small-signal and dynamic extraction (gm, cpi, cmu, power)
		Dictionary internals = get_device_internal_parameters(p_id, p_type);
		if (!internals.is_empty()) {
			telem["internals"] = internals;
			if (internals.has("ic")) telem["current"] = std::abs((double)internals["ic"]);
			if (internals.has("p")) telem["power"] = std::abs((double)internals["p"]);
		}
	}
	else { // Digital Gates or Default
		String n_out = p_nodes.get(p_id + ":out", "0");
		double v_out = helper_get_voltage(p_voltages, n_out);
		telem["v_drop"] = v_out;
		telem["logic_state"] = (v_out > 1.65) ? "1" : "0";
		telem["state_str"] = (v_out > 1.65) ? "HIGH (1)" : "LOW (0)";
	}

	return telem;
}

PackedVector2Array CircuitSimulator::compute_current_particles(const PackedVector2Array &p_wire_pts, double p_current_amps, double p_accum_time, double p_spacing) {
	PackedVector2Array particles;
	if (p_wire_pts.size() < 2 || std::abs(p_current_amps) < 1e-9 || p_spacing <= 1.0) {
		return particles;
	}

	// Calculate total polyline length
	double total_length = 0.0;
	std::vector<double> seg_lengths;
	for (int i = 0; i < p_wire_pts.size() - 1; ++i) {
		Vector2 d = p_wire_pts[i + 1] - p_wire_pts[i];
		double len = d.length();
		seg_lengths.push_back(len);
		total_length += len;
	}

	if (total_length <= 1.0) return particles;

	// Speed proportional to log/current
	double speed_factor = std::clamp(std::abs(p_current_amps) * 1000.0, 10.0, 120.0);
	double dir = (p_current_amps >= 0.0) ? 1.0 : -1.0;
	double offset = std::fmod(dir * p_accum_time * speed_factor, p_spacing);
	if (offset < 0.0) offset += p_spacing;

	// Distribute points along polyline
	for (double dist = offset; dist < total_length; dist += p_spacing) {
		double accum = 0.0;
		for (size_t i = 0; i < seg_lengths.size(); ++i) {
			if (dist <= accum + seg_lengths[i]) {
				double seg_t = (dist - accum) / seg_lengths[i];
				Vector2 p = p_wire_pts[i].lerp(p_wire_pts[i + 1], seg_t);
				particles.append(p);
				break;
			}
			accum += seg_lengths[i];
		}
	}

	return particles;
}

// --- SPICE Library & Subcircuit Management ---

bool CircuitSimulator::scan_library_file(const String &p_file_path) {
	if (m_library_resolver.is_valid()) {
		return m_library_resolver->scan_file(p_file_path);
	}
	return false;
}

int CircuitSimulator::scan_library_directory(const String &p_dir_path, bool p_recursive) {
	if (m_library_resolver.is_valid()) {
		return m_library_resolver->scan_directory(p_dir_path, p_recursive);
	}
	return 0;
}

bool CircuitSimulator::register_raw_library(const String &p_library_text, const String &p_source_name) {
	if (m_library_resolver.is_valid()) {
		return m_library_resolver->register_raw_library(p_library_text, p_source_name);
	}
	return false;
}

Dictionary CircuitSimulator::get_library_catalog() const {
	Dictionary catalog;
	if (m_library_resolver.is_valid()) {
		catalog["subcircuits"] = m_library_resolver->get_subcircuit_names();
		catalog["models"] = m_library_resolver->get_model_names();
	}
	return catalog;
}

String CircuitSimulator::resolve_subcircuits_and_models(const PackedStringArray &p_needed_names) const {
	if (m_library_resolver.is_valid()) {
		return m_library_resolver->generate_injection_deck(p_needed_names);
	}
	return "";
}

// --- Detailed Semiconductor Internal Vectors Extraction (@device[param]) ---

double CircuitSimulator::query_internal_vector(const String &p_query) {
	if (!is_available() || !p_ngGet_Vec_Info) {
		return 0.0;
	}

	auto vec_info_fn = (pvector_info (*)(char*))p_ngGet_Vec_Info;
	std::string q_str = p_query.strip_edges().utf8().get_data();
	pvector_info vinfo = vec_info_fn(&q_str[0]);
	if (vinfo && vinfo->v_realdata && vinfo->v_length > 0) {
		return vinfo->v_realdata[vinfo->v_length - 1]; // latest point
	}
	return 0.0;
}

Dictionary CircuitSimulator::get_device_internal_parameters(const String &p_device_id, int p_type) {
	Dictionary params;
	if (!is_available()) {
		return params;
	}

	String dev = p_device_id.to_lower();

	// 6: DIODE
	if (p_type == 6) {
		params["id"] = query_internal_vector("@" + dev + "[id]");
		params["vd"] = query_internal_vector("@" + dev + "[vd]");
		params["gd"] = query_internal_vector("@" + dev + "[gd]");
		params["cd"] = query_internal_vector("@" + dev + "[cd]");
		params["p"] = query_internal_vector("@" + dev + "[p]");
	}
	// 7: BJT_NPN or 8: BJT_PNP
	else if (p_type == 7 || p_type == 8) {
		params["ib"] = query_internal_vector("@" + dev + "[ib]");
		params["ic"] = query_internal_vector("@" + dev + "[ic]");
		params["ie"] = query_internal_vector("@" + dev + "[ie]");
		params["vbe"] = query_internal_vector("@" + dev + "[vbe]");
		params["vce"] = query_internal_vector("@" + dev + "[vce]");
		params["gm"] = query_internal_vector("@" + dev + "[gm]");
		params["gpi"] = query_internal_vector("@" + dev + "[gpi]");
		params["go"] = query_internal_vector("@" + dev + "[go]");
		params["cpi"] = query_internal_vector("@" + dev + "[cpi]");
		params["cmu"] = query_internal_vector("@" + dev + "[cmu]");
		params["cbx"] = query_internal_vector("@" + dev + "[cbx]");
		params["p"] = query_internal_vector("@" + dev + "[p]");
	}
	// MOSFET (NMOS/PMOS) or generic device query
	else {
		double gm = query_internal_vector("@" + dev + "[gm]");
		if (std::abs(gm) > 1e-12) {
			params["gm"] = gm;
			params["gds"] = query_internal_vector("@" + dev + "[gds]");
			params["id"] = query_internal_vector("@" + dev + "[id]");
			params["vgs"] = query_internal_vector("@" + dev + "[vgs]");
			params["vds"] = query_internal_vector("@" + dev + "[vds]");
			params["cgs"] = query_internal_vector("@" + dev + "[cgs]");
			params["cgd"] = query_internal_vector("@" + dev + "[cgd]");
			params["p"] = query_internal_vector("@" + dev + "[p]");
		}
	}

	return params;
}

} // namespace godot
