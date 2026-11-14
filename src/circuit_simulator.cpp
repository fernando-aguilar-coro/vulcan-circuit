#include "circuit_simulator.h"
#include "ngspice/sharedspice.h"

#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <sstream>
#include <iostream>
#include <cstring>
#include <string>
#include <algorithm>
#include <cmath>

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
	ClassDB::bind_method(D_METHOD("run_analysis", "netlist_text", "analysis_mode", "options"), &CircuitSimulator::run_analysis, DEFVAL(Dictionary()));
	ClassDB::bind_method(D_METHOD("execute_command", "cmd"), &CircuitSimulator::execute_command);
	ClassDB::bind_method(D_METHOD("get_last_log"), &CircuitSimulator::get_last_log);

	ClassDB::bind_method(D_METHOD("start_live_sim", "netlist_text"), &CircuitSimulator::start_live_sim);
	ClassDB::bind_method(D_METHOD("stop_live_sim"), &CircuitSimulator::stop_live_sim);
	ClassDB::bind_method(D_METHOD("is_sim_running"), &CircuitSimulator::is_sim_running);
	ClassDB::bind_method(D_METHOD("alter_component_value", "device_id", "param_val"), &CircuitSimulator::alter_component_value);
	ClassDB::bind_method(D_METHOD("get_live_vector_snapshot"), &CircuitSimulator::get_live_vector_snapshot);
	ClassDB::bind_method(D_METHOD("evaluate_component_telemetry", "type", "id", "val", "nodes", "voltages", "currents"), &CircuitSimulator::evaluate_component_telemetry);
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
	return run_analysis(p_netlist_text, "op", Dictionary());
}

Dictionary CircuitSimulator::run_analysis(const String &p_netlist_text, const String &p_analysis_mode, const Dictionary &p_options) {
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

	String mode = p_analysis_mode.to_lower().strip_edges();
	String command;
	if (mode == "op") {
		command = "op";
	} else if (mode == "tran" || mode == "transient") {
		double time_step = (double)p_options.get("time_step", 1e-5);
		double stop_time = (double)p_options.get("stop_time", 0.01);
		if (!std::isfinite(time_step) || !std::isfinite(stop_time) || time_step <= 0.0 || stop_time <= time_step) {
			result["error"] = "Transient analysis requires finite positive time_step and stop_time > time_step.";
			result["log"] = get_last_log();
			return result;
		}
		command = "tran " + String::num_real(time_step) + " " + String::num_real(stop_time) + " 0 " + String::num_real(time_step);
		mode = "tran";
	} else if (mode == "ac" || mode == "phasor") {
		double start_frequency = (double)p_options.get("start_frequency_hz", 10.0);
		double stop_frequency = (double)p_options.get("stop_frequency_hz", 1e6);
		int points_per_decade = (int)p_options.get("points_per_decade", 20);
		if (!std::isfinite(start_frequency) || !std::isfinite(stop_frequency) ||
				start_frequency <= 0.0 || stop_frequency <= start_frequency ||
				points_per_decade < 1 || points_per_decade > 10000) {
			result["error"] = "AC analysis requires 0 < start_frequency_hz < stop_frequency_hz and 1-10000 points per decade.";
			result["log"] = get_last_log();
			return result;
		}
		command = "ac dec " + String::num_int64(points_per_decade) + " " +
				String::num_real(start_frequency) + " " + String::num_real(stop_frequency);
		mode = "ac";
	} else {
		result["error"] = "Unsupported analysis mode: " + p_analysis_mode;
		result["log"] = get_last_log();
		return result;
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

	std::string command_str = command.utf8().get_data();
	int analysis_ret = cmd_fn(&command_str[0]);
	if (analysis_ret != 0) {
		result["error"] = "ngspice failed to run " + mode.to_upper() + " analysis (code: " + String::num_int64(analysis_ret) + ").";
		result["log"] = get_last_log();
		return result;
	}

	char *cur_plot = cur_plot_fn();
	Dictionary node_voltages;
	Dictionary branch_currents;
	Dictionary all_vectors;
	Dictionary ac_voltages;
	Dictionary ac_device_currents;
	PackedFloat64Array ac_frequencies;

	if (cur_plot) {
		char **vecs = all_vecs_fn(cur_plot);
		if (vecs) {
			for (int i = 0; vecs[i] != nullptr; ++i) {
				char *vname = vecs[i];
				pvector_info vinfo = vec_info_fn(vname);
				if (vinfo && vinfo->v_length > 0 && (vinfo->v_realdata || vinfo->v_compdata)) {
					String name_str = String(vname).to_lower();
					String node_name;
					String device_name;
					if (name_str.begins_with("v(") && name_str.ends_with(")")) {
						node_name = name_str.substr(2, name_str.length() - 3);
					} else if (name_str.begins_with("i(") && name_str.ends_with(")")) {
						device_name = name_str.substr(2, name_str.length() - 3);
					} else if (name_str.ends_with("#branch")) {
						device_name = name_str.substr(0, name_str.length() - 7);
					} else if (name_str.begins_with("@") && name_str.ends_with("[i]")) {
						device_name = name_str.substr(1, name_str.length() - 4);
					}

					if (vinfo->v_compdata) {
						Array values;
						for (int k = 0; k < vinfo->v_length; ++k) {
							values.append(Vector2((real_t)vinfo->v_compdata[k].cx_real, (real_t)vinfo->v_compdata[k].cx_imag));
						}
						all_vectors[name_str] = values;
						if (!node_name.is_empty()) {
							ac_voltages[node_name] = values;
							double last_real = vinfo->v_compdata[vinfo->v_length - 1].cx_real;
							double last_imag = vinfo->v_compdata[vinfo->v_length - 1].cx_imag;
							node_voltages[node_name] = std::hypot(last_real, last_imag);
						}
						if (!device_name.is_empty()) {
							ac_device_currents[device_name] = values;
							double last_real = vinfo->v_compdata[vinfo->v_length - 1].cx_real;
							double last_imag = vinfo->v_compdata[vinfo->v_length - 1].cx_imag;
							branch_currents[device_name + "#branch"] = std::hypot(last_real, last_imag);
						}
					} else if (vinfo->v_realdata) {
						double val = vinfo->v_realdata[vinfo->v_length - 1];
						if (vinfo->v_length == 1) {
							all_vectors[name_str] = val;
						} else {
							PackedFloat64Array values;
							for (int k = 0; k < vinfo->v_length; ++k) {
								values.append(vinfo->v_realdata[k]);
							}
							all_vectors[name_str] = values;
						}

						if (name_str == "frequency") {
							for (int k = 0; k < vinfo->v_length; ++k) {
								ac_frequencies.append(vinfo->v_realdata[k]);
							}
						}
						if (!node_name.is_empty()) {
							node_voltages[node_name] = val;
						} else if (!device_name.is_empty()) {
							branch_currents[device_name + "#branch"] = val;
						} else if (!name_str.contains("#") && name_str != "time" && name_str != "frequency") {
							node_voltages[name_str] = val;
						}
					}
				}
			}
		}
	}

	if (mode == "ac" && ac_frequencies.is_empty()) {
		result["error"] = "ngspice AC analysis did not return a frequency vector.";
		result["log"] = get_last_log();
		return result;
	}

	result["success"] = true;
	result["analysis_mode"] = mode;
	result["node_voltages"] = node_voltages;
	result["branch_currents"] = branch_currents;
	result["all_vectors"] = all_vectors;
	if (mode == "ac") {
		result["ac_voltages"] = ac_voltages;
		result["ac_device_currents"] = ac_device_currents;
		result["ac_frequencies_hz"] = ac_frequencies;
	}
	result["log"] = get_last_log();

	Dictionary snap;
	snap["node_voltages"] = node_voltages;
	snap["branch_currents"] = branch_currents;
	m_last_snapshot = snap;
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

	// First load circuit netlist deck and calculate operating point / state
	Dictionary sim_res = simulate_netlist(p_netlist_text);

	auto cmd_fn = (int (*)(char*))p_ngSpice_Command;
	if (!cmd_fn) return false;

	// Launch background run or continuous transient if applicable
	cmd_fn((char*)"bg_run");
	return sim_res.get("success", false);
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
					} else if (name_str.ends_with("#branch")) {
						branch_currents[name_str] = val;
					} else if (!name_str.contains("#") && name_str != "time") {
						// Raw node name in SPICE OP/TRAN vectors (e.g. "n1", "n2", "out")
						node_voltages[name_str] = val;
					}
				}
			}
		}
	}

	if (node_voltages.is_empty() && !m_last_snapshot.is_empty()) {
		return m_last_snapshot;
	}

	result["node_voltages"] = node_voltages;
	result["branch_currents"] = branch_currents;
	if (!node_voltages.is_empty()) {
		m_last_snapshot = result;
	}
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

	// Keep these values aligned with CircuitComponent.Type in circuit_component.gd.
	// 0: UNKNOWN, 1: RESISTOR, 2: VOLTAGE_SOURCE, 3: CURRENT_SOURCE,
	// 4: GROUND, 5: CAPACITOR, 6: INDUCTOR, 7: DIODE,
	// 8: BJT_NPN, 9: BJT_PNP, 22+: digital component types.
	if (p_type == 1) { // RESISTOR
		String pin1_id = p_id + String(":p1");
		String pin2_id = p_id + String(":p2");
		if (!p_nodes.has(pin1_id) || !p_nodes.has(pin2_id)) {
			telem["v_drop"] = 0.0;
			telem["current"] = 0.0;
			telem["power"] = 0.0;
			telem["resistance"] = 1000.0;
			telem["state_str"] = "Open Pin";
			return telem;
		}
		String n1 = p_nodes[pin1_id];
		String n2 = p_nodes[pin2_id];
		if (n1 == n2) {
			telem["v_drop"] = 0.0;
			telem["current"] = 0.0;
			telem["power"] = 0.0;
			telem["resistance"] = 1000.0;
			telem["state_str"] = "Equipotential / Short";
			return telem;
		}
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
	else if (p_type == 2) { // VOLTAGE_SOURCE
		String n_pos = p_nodes.get(p_id + String(":pos"), "0");
		String n_neg = p_nodes.get(p_id + String(":neg"), "0");
		double v_pos = helper_get_voltage(p_voltages, n_pos);
		double v_neg = helper_get_voltage(p_voltages, n_neg);
		double v_src = v_pos - v_neg;
		String b_name = p_id.to_lower() + String("#branch");
		double curr = 0.0;
		if (p_currents.has(b_name)) curr = std::abs((double)p_currents[b_name]);
		else if (p_currents.has(p_id + String("#branch"))) curr = std::abs((double)p_currents[p_id + String("#branch")]);

		telem["v_drop"] = v_src;
		telem["current"] = curr;
		telem["power"] = std::abs(v_src * curr);
		telem["state_str"] = "Active Source";
	}
	else if (p_type == 5 || p_type == 6) { // CAPACITOR / INDUCTOR
		String pin1_id = p_id + String(":p1");
		String pin2_id = p_id + String(":p2");
		String n1 = p_nodes.get(pin1_id, "0");
		String n2 = p_nodes.get(pin2_id, "0");
		double v_drop = helper_get_voltage(p_voltages, n1) - helper_get_voltage(p_voltages, n2);
		String branch_name = p_id.to_lower() + String("#branch");
		double current = 0.0;
		if (p_currents.has(branch_name)) current = (double)p_currents[branch_name];
		else if (p_currents.has(p_id + String("#branch"))) current = (double)p_currents[p_id + String("#branch")];

		telem["v_drop"] = v_drop;
		telem["current"] = current;
		telem["power"] = v_drop * current;
		telem["state_str"] = (p_type == 5) ? "Capacitor (transient)" : "Inductor (transient)";
	}
	else if (p_type == 7) { // DIODE
		String n_a = p_nodes.get(p_id + String(":anode"), "0");
		String n_k = p_nodes.get(p_id + String(":cathode"), "0");
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
	else if (p_type == 8 || p_type == 9) { // BJT_NPN / BJT_PNP
		String n_c = p_nodes.get(p_id + String(":C"), "0");
		String n_b = p_nodes.get(p_id + String(":B"), "0");
		String n_e = p_nodes.get(p_id + String(":E"), "0");
		double vc = helper_get_voltage(p_voltages, n_c);
		double vb = helper_get_voltage(p_voltages, n_b);
		double ve = helper_get_voltage(p_voltages, n_e);

		double vbe = vb - ve;
		double vce = vc - ve;
		telem["v_be"] = vbe;
		telem["v_ce"] = vce;
		if (p_type == 8) { // NPN
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
		String n_out = p_nodes.get(p_id + String(":out"), "0");
		double v_out = helper_get_voltage(p_voltages, n_out);
		telem["v_drop"] = v_out;
		telem["logic_state"] = (v_out > 1.65) ? "1" : "0";
		telem["state_str"] = (v_out > 1.65) ? "HIGH (1)" : "LOW (0)";
	}

	return telem;
}

PackedVector2Array CircuitSimulator::compute_current_particles(const PackedVector2Array &p_wire_pts, double p_current_amps, double p_accum_time, double p_spacing) {
	PackedVector2Array particles;
	if (p_wire_pts.size() < 2 || std::abs(p_current_amps) < 1e-7 || p_spacing <= 1.0) {
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

	// Keep these values aligned with CircuitComponent.Type in circuit_component.gd.
	// 7: DIODE
	if (p_type == 7) {
		params["id"] = query_internal_vector(String("@") + dev + String("[id]"));
		params["vd"] = query_internal_vector(String("@") + dev + String("[vd]"));
		params["gd"] = query_internal_vector(String("@") + dev + String("[gd]"));
		params["cd"] = query_internal_vector(String("@") + dev + String("[cd]"));
		params["p"] = query_internal_vector(String("@") + dev + String("[p]"));
	}
	// 8: BJT_NPN or 9: BJT_PNP
	else if (p_type == 8 || p_type == 9) {
		params["ib"] = query_internal_vector(String("@") + dev + String("[ib]"));
		params["ic"] = query_internal_vector(String("@") + dev + String("[ic]"));
		params["ie"] = query_internal_vector(String("@") + dev + String("[ie]"));
		params["vbe"] = query_internal_vector(String("@") + dev + String("[vbe]"));
		params["vce"] = query_internal_vector(String("@") + dev + String("[vce]"));
		params["gm"] = query_internal_vector(String("@") + dev + String("[gm]"));
		params["gpi"] = query_internal_vector(String("@") + dev + String("[gpi]"));
		params["go"] = query_internal_vector(String("@") + dev + String("[go]"));
		params["cpi"] = query_internal_vector(String("@") + dev + String("[cpi]"));
		params["cmu"] = query_internal_vector(String("@") + dev + String("[cmu]"));
		params["cbx"] = query_internal_vector(String("@") + dev + String("[cbx]"));
		params["p"] = query_internal_vector(String("@") + dev + String("[p]"));
	}
	// MOSFET (NMOS/PMOS) or generic device query
	else {
		double gm = query_internal_vector(String("@") + dev + String("[gm]"));
		if (std::abs(gm) > 1e-12) {
			params["gm"] = gm;
			params["gds"] = query_internal_vector(String("@") + dev + String("[gds]"));
			params["id"] = query_internal_vector(String("@") + dev + String("[id]"));
			params["vgs"] = query_internal_vector(String("@") + dev + String("[vgs]"));
			params["vds"] = query_internal_vector(String("@") + dev + String("[vds]"));
			params["cgs"] = query_internal_vector(String("@") + dev + String("[cgs]"));
			params["cgd"] = query_internal_vector(String("@") + dev + String("[cgd]"));
			params["p"] = query_internal_vector(String("@") + dev + String("[p]"));
		}
	}

	return params;
}

} // namespace godot
