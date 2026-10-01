#include "circuit_placer.h"

#include <godot_cpp/variant/utility_functions.hpp>

#include <string>
#include <vector>
#include <map>
#include <set>
#include <queue>
#include <algorithm>
#include <cmath>

namespace godot {

void CircuitPlacer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("place_circuit", "netlist_data"), &CircuitPlacer::place_circuit);
}

static int type_str_to_enum(const String &type_name) {
	String t = type_name.to_upper().strip_edges();
	if (t == "RESISTOR" || t == "R") return 0;
	if (t == "VOLTAGE_SOURCE" || t == "V" || t == "VSOURCE") return 1;
	if (t == "CURRENT_SOURCE" || t == "I" || t == "ISOURCE") return 2;
	if (t == "GROUND" || t == "GND") return 3;
	if (t == "CAPACITOR" || t == "C") return 4;
	if (t == "INDUCTOR" || t == "L") return 5;
	if (t == "DIODE" || t == "D") return 6;
	if (t == "BJT_NPN" || t == "NPN") return 7;
	if (t == "BJT_PNP" || t == "PNP") return 8;
	if (t == "OPAMP" || t == "OP_AMP") return 9;
	return 0;
}

Dictionary CircuitPlacer::place_circuit(const Dictionary &p_netlist_data) {
	Dictionary result;
	Dictionary placed_components;
	Dictionary node_positions;
	Dictionary local_gnds;
	Dictionary ground_pins;
	Dictionary active_pins;
	Dictionary component_pins;
	Array wires;

	Array components = p_netlist_data.get("components", Array());
	String ref_node = p_netlist_data.get("reference_node", "0");
	if (ref_node.is_empty()) {
		ref_node = "0";
	}

	// 1. Collect all electrical nodes and component edges
	std::set<std::string> all_nodes;
	std::map<std::string, std::set<std::string>> adj;
	std::set<std::string> source_nodes;

	struct CompItem {
		std::string id;
		int type_enum;
		std::string value;
		std::string from_node;
		std::string to_node;
		std::vector<std::string> connected_nodes;
		Dictionary pins_dict;
	};

	std::vector<CompItem> comp_list;

	for (int i = 0; i < components.size(); ++i) {
		Dictionary c = components[i];
		std::string cid = String(c.get("id", "comp_" + String::num_int64(i))).utf8().get_data();
		Variant raw_type = c.get("type", 0);
		int ctype = (raw_type.get_type() == Variant::STRING) ? type_str_to_enum(raw_type) : (int)raw_type;
		std::string val = String(c.get("value", "")).utf8().get_data();

		Dictionary pins = c.get("pins", Dictionary());
		std::string nA = "";
		std::string nB = "";
		std::vector<std::string> conns;

		if (pins.has("from_node")) {
			nA = String(pins["from_node"]).utf8().get_data();
		} else if (pins.has("pos")) {
			nA = String(pins["pos"]).utf8().get_data();
		} else if (pins.has("p1")) {
			nA = String(pins["p1"]).utf8().get_data();
		}

		if (pins.has("to_node")) {
			nB = String(pins["to_node"]).utf8().get_data();
		} else if (pins.has("neg")) {
			nB = String(pins["neg"]).utf8().get_data();
		} else if (pins.has("p2")) {
			nB = String(pins["p2"]).utf8().get_data();
		}

		if (!nA.empty()) {
			all_nodes.insert(nA);
			conns.push_back(nA);
		}
		if (!nB.empty()) {
			all_nodes.insert(nB);
			conns.push_back(nB);
		}

		// Also check other multi-terminal pins (e.g. B, C, E, in_neg, in_pos, out)
		Array pin_keys = pins.keys();
		for (int k = 0; k < pin_keys.size(); ++k) {
			String pkey = pin_keys[k];
			if (pkey != "from_node" && pkey != "to_node" && pkey != "pos" && pkey != "neg" && pkey != "p1" && pkey != "p2") {
				std::string pnode = String(pins[pkey]).utf8().get_data();
				if (!pnode.empty()) {
					all_nodes.insert(pnode);
					conns.push_back(pnode);
				}
			}
		}

		if (!nA.empty() && !nB.empty()) {
			adj[nA].insert(nB);
			adj[nB].insert(nA);
		}

		// If this is a source, mark the positive terminal as a source node
		if (ctype == 1 || ctype == 2) {
			if (!nA.empty() && nA != ref_node.utf8().get_data()) {
				source_nodes.insert(nA);
			}
		}

		comp_list.push_back({ cid, ctype, val, nA, nB, conns, pins });
	}

	std::string gnd_str = ref_node.utf8().get_data();
	all_nodes.insert(gnd_str);

	// 2. Sugiyama Phase 1 & 2: Layer Assignment (Ranking)
	std::map<std::string, int> node_rank;
	std::queue<std::string> q;

	if (source_nodes.empty()) {
		// Pick first non-gnd node as root
		for (const auto &n : all_nodes) {
			if (n != gnd_str) {
				source_nodes.insert(n);
				break;
			}
		}
	}

	for (const auto &src : source_nodes) {
		node_rank[src] = 0;
		q.push(src);
	}

	while (!q.empty()) {
		std::string u = q.front();
		q.pop();
		int r = node_rank[u];

		for (const auto &v : adj[u]) {
			if (v == gnd_str) {
				continue; // GND placed at bottom layer
			}
			if (node_rank.find(v) == node_rank.end()) {
				node_rank[v] = r + 1;
				q.push(v);
			}
		}
	}

	// Any unvisited nodes get successive layers
	int max_r = 0;
	for (const auto &pair : node_rank) {
		max_r = std::max(max_r, pair.second);
	}
	for (const auto &n : all_nodes) {
		if (n != gnd_str && node_rank.find(n) == node_rank.end()) {
			max_r++;
			node_rank[n] = max_r;
		}
	}
	node_rank[gnd_str] = max_r + 1;

	// Group nodes into layers
	std::map<int, std::vector<std::string>> layers;
	for (const auto &pair : node_rank) {
		layers[pair.second].push_back(pair.first);
	}

	// 3. Sugiyama Phase 3: Barycentric Ordering within Layers
	for (auto &pair : layers) {
		int layer_idx = pair.first;
		auto &vec = pair.second;
		if (vec.size() > 1 && layer_idx > 0) {
			std::vector<std::pair<double, std::string>> scored;
			for (const auto &n : vec) {
				double sum_pos = 0.0;
				int count = 0;
				for (const auto &neighbor : adj[n]) {
					if (node_rank[neighbor] < layer_idx) {
						auto it = std::find(layers[node_rank[neighbor]].begin(), layers[node_rank[neighbor]].end(), neighbor);
						if (it != layers[node_rank[neighbor]].end()) {
							sum_pos += (double)std::distance(layers[node_rank[neighbor]].begin(), it);
							count++;
						}
					}
				}
				double score = (count > 0) ? (sum_pos / count) : 0.0;
				scored.push_back({ score, n });
			}
			std::sort(scored.begin(), scored.end());
			for (size_t i = 0; i < scored.size(); ++i) {
				vec[i] = scored[i].second;
			}
		}
	}

	// 4. Sugiyama Phase 4: Coordinate Assignment
	const double DX = 220.0;
	const double DY = 160.0;
	const double START_X = 140.0;
	const double START_Y = 120.0;

	std::map<std::string, Vector2> node_coords;
	for (const auto &pair : layers) {
		int layer_idx = pair.first;
		const auto &vec = pair.second;
		for (size_t i = 0; i < vec.size(); ++i) {
			double x = START_X + layer_idx * DX;
			double y = START_Y + i * DY;
			node_coords[vec[i]] = Vector2((float)x, (float)y);
			node_positions[String(vec[i].c_str())] = Vector2((float)x, (float)y);
		}
	}

	// 5. Component Placement & Orientation
	int gnd_counter = 1;
	for (const auto &comp : comp_list) {
		Vector2 comp_pos(0, 0);
		int rot_deg = 0;

		bool has_gnd = (comp.from_node == gnd_str || comp.to_node == gnd_str);
		std::string active_node = "";

		if (has_gnd) {
			active_node = (comp.from_node == gnd_str) ? comp.to_node : comp.from_node;
			Vector2 act_pos = node_coords[active_node];

			// Vertical placement above local ground
			comp_pos = Vector2(act_pos.x, act_pos.y + 60.0f);
			rot_deg = 90;

			// Check voltage source orientation (+ terminal towards active node, - terminal towards ground)
			if (comp.type_enum == 1 || comp.type_enum == 2) {
				if (comp.to_node == gnd_str) {
					// from_node is active (+), to_node is GND (-)
					// With rot 90, pos is bottom (40), neg is top (-40) -> rotate 270 so pos is top (towards active)
					rot_deg = 270;
				} else {
					rot_deg = 90;
				}
			}

			// Add local ground symbol directly beneath
			String gnd_id = "GND_" + String(comp.id.c_str());
			Vector2 gnd_pos = Vector2(act_pos.x, act_pos.y + 130.0f);

			Dictionary gnd_dict;
			gnd_dict["id"] = gnd_id;
			gnd_dict["type"] = 3; // GROUND
			gnd_dict["pos"] = gnd_pos;
			gnd_dict["rotation_deg"] = 0;
			gnd_dict["value"] = "0";
			placed_components[gnd_id] = gnd_dict;

			local_gnds[String(comp.id.c_str())] = gnd_id;
			ground_pins[String(comp.id.c_str())] = (comp.from_node == gnd_str) ? "pos" : "neg";
			active_pins[String(comp.id.c_str())] = (comp.from_node == gnd_str) ? "neg" : "pos";

		} else if (!comp.from_node.empty() && !comp.to_node.empty()) {
			Vector2 pA = node_coords[comp.from_node];
			Vector2 pB = node_coords[comp.to_node];

			if (std::abs(pA.x - pB.x) > std::abs(pA.y - pB.y)) {
				// Horizontal placement
				comp_pos = (pA + pB) * 0.5f;
				rot_deg = 0;
			} else {
				// Vertical placement
				comp_pos = (pA + pB) * 0.5f;
				rot_deg = 90;
			}
		} else {
			// Multi-terminal or isolated component
			if (!comp.connected_nodes.empty()) {
				Vector2 avg(0, 0);
				for (const auto &n : comp.connected_nodes) {
					avg += node_coords[n];
				}
				comp_pos = avg / (float)comp.connected_nodes.size();
			} else {
				comp_pos = Vector2(200, 200);
			}
			rot_deg = 0;
		}

		Dictionary c_data;
		c_data["id"] = String(comp.id.c_str());
		c_data["type"] = comp.type_enum;
		c_data["pos"] = comp_pos;
		c_data["rotation_deg"] = rot_deg;
		c_data["value"] = String(comp.value.c_str());
		c_data["pins"] = comp.pins_dict;

		Array conns_arr;
		for (const auto &cn : comp.connected_nodes) {
			conns_arr.append(String(cn.c_str()));
		}
		c_data["connected_nodes"] = conns_arr;

		placed_components[String(comp.id.c_str())] = c_data;
		component_pins[String(comp.id.c_str())] = comp.pins_dict;
	}

	result["success"] = true;
	result["components"] = placed_components;
	result["node_positions"] = node_positions;
	result["node_coords"] = node_positions;
	result["component_pins"] = component_pins;
	result["local_gnds"] = local_gnds;
	result["ground_pins"] = ground_pins;
	result["active_pins"] = active_pins;
	result["gnd_node"] = ref_node;

	return result;
}

} // namespace godot
