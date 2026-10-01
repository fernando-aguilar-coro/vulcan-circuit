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
}

CircuitSimulator::CircuitSimulator() {
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

} // namespace godot
