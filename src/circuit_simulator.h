#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>

#include <string>
#include <vector>

namespace godot {

class CircuitSimulator : public RefCounted {
	GDCLASS(CircuitSimulator, RefCounted)

protected:
	static void _bind_methods();

private:
	void *m_dll_handle = nullptr;
	std::string m_last_log;
	bool m_is_initialized = false;

	// Function pointers to ngspice shared library
	void *p_ngSpice_Init = nullptr;
	void *p_ngSpice_Command = nullptr;
	void *p_ngSpice_Circ = nullptr;
	void *p_ngGet_Vec_Info = nullptr;
	void *p_ngSpice_CurPlot = nullptr;
	void *p_ngSpice_AllPlots = nullptr;
	void *p_ngSpice_AllVecs = nullptr;
	void *p_ngSpice_running = nullptr;

	static int cb_send_char(char *msg, int id, void *user_data);
	static int cb_send_stat(char *msg, int id, void *user_data);
	static int cb_controlled_exit(int status, bool immediate, bool is_error, int id, void *user_data);

public:
	CircuitSimulator();
	~CircuitSimulator() override;

	bool init_simulator(const String &p_dll_path = "");
	bool is_available() const;
	Dictionary simulate_netlist(const String &p_netlist_text);
	Dictionary execute_command(const String &p_cmd);
	String get_last_log() const;
	void append_log(const char *msg);

	// --- Enhanced GDExtension Live Simulation & Multicomponent Telemetry ---
	bool start_live_sim(const String &p_netlist_text);
	bool stop_live_sim();
	bool is_sim_running() const;
	bool alter_component_value(const String &p_device_id, const String &p_param_val);
	Dictionary get_live_vector_snapshot();
	Dictionary evaluate_component_telemetry(int p_type, const String &p_id, const String &p_val, const Dictionary &p_nodes, const Dictionary &p_voltages, const Dictionary &p_currents);
	PackedVector2Array compute_current_particles(const PackedVector2Array &p_wire_pts, double p_current_amps, double p_accum_time, double p_spacing = 24.0);
};

} // namespace godot
