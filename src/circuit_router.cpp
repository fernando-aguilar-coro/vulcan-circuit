#include "circuit_router.h"
#include "libavoid/libavoid.h"
#include "libavoid/connectionpin.h"

#include <godot_cpp/variant/utility_functions.hpp>
#include <map>
#include <vector>
#include <algorithm>

namespace godot {

void CircuitRouter::_bind_methods() {
	ClassDB::bind_method(D_METHOD("route_circuit", "circuit_graph"), &CircuitRouter::route_circuit);

	BIND_ENUM_CONSTANT(DIR_NONE);
	BIND_ENUM_CONSTANT(DIR_UP);
	BIND_ENUM_CONSTANT(DIR_DOWN);
	BIND_ENUM_CONSTANT(DIR_LEFT);
	BIND_ENUM_CONSTANT(DIR_RIGHT);
	BIND_ENUM_CONSTANT(DIR_ALL);

	BIND_ENUM_CONSTANT(ROUTING_ORTHOGONAL);
	BIND_ENUM_CONSTANT(ROUTING_POLYLINE);
}

Dictionary CircuitRouter::route_circuit(const Dictionary &p_circuit_graph) {
	Dictionary result;
	Dictionary routes;

	int routing_mode = p_circuit_graph.get("routing_mode", (int)ROUTING_ORTHOGONAL);
	double segment_penalty = p_circuit_graph.get("segment_penalty", 150.0);
	double crossing_penalty = p_circuit_graph.get("crossing_penalty", 120.0);
	double port_direction_penalty = p_circuit_graph.get("port_direction_penalty", 100.0);
	double reverse_direction_penalty = p_circuit_graph.get("reverse_direction_penalty", 50.0);
	double port_pin_offset = p_circuit_graph.get("port_pin_offset", 16.0);
	double nudging_distance = p_circuit_graph.get("nudging_distance", 12.0);
	double shape_buffer_distance = p_circuit_graph.get("shape_buffer_distance", 10.0);
	bool nudge_connected_to_shapes = p_circuit_graph.get("nudge_connected_to_shapes", true);

	unsigned int flags = (routing_mode == ROUTING_POLYLINE) ? Avoid::PolyLineRouting : Avoid::OrthogonalRouting;
	Avoid::Router router(flags);

	if (flags & Avoid::OrthogonalRouting) {
		router.setRoutingParameter(Avoid::segmentPenalty, segment_penalty);
		router.setRoutingParameter(Avoid::crossingPenalty, crossing_penalty);
		router.setRoutingParameter(Avoid::portDirectionPenalty, port_direction_penalty);
		router.setRoutingParameter(Avoid::reverseDirectionPenalty, reverse_direction_penalty);
		router.setRoutingParameter(Avoid::idealNudgingDistance, nudging_distance);
		router.setRoutingParameter(Avoid::shapeBufferDistance, shape_buffer_distance);
		router.setRoutingOption(Avoid::nudgeOrthogonalSegmentsConnectedToShapes, nudge_connected_to_shapes);
		router.setRoutingOption(Avoid::performUnifyingNudgingPreprocessingStep, true);
		router.setRoutingOption(Avoid::nudgeOrthogonalTouchingColinearSegments, true);
	}

	// 1. Process Obstacles (Components / Chips)
	std::map<Variant, Avoid::ShapeRef *> shape_map;
	Array obstacles = p_circuit_graph.get("obstacles", Array());

	for (int i = 0; i < obstacles.size(); ++i) {
		Dictionary obs = obstacles[i];
		Variant obs_id = obs.get("id", i);
		Rect2 rect = obs.get("rect", Rect2(0, 0, 40, 40));

		double min_x = rect.position.x;
		double min_y = rect.position.y;
		double max_x = rect.position.x + std::max((double)rect.size.x, 1.0);
		double max_y = rect.position.y + std::max((double)rect.size.y, 1.0);

		Avoid::Rectangle shape_rect(Avoid::Point(min_x, min_y), Avoid::Point(max_x, max_y));
		Avoid::ShapeRef *shape_ref = new Avoid::ShapeRef(&router, shape_rect);
		shape_map[obs_id] = shape_ref;

		// Process Pins on this obstacle
		Array pins = obs.get("pins", Array());
		for (int p = 0; p < pins.size(); ++p) {
			Dictionary pin = pins[p];
			int pin_id = pin.get("id", p + 1);
			int dir_flags = pin.get("dir", (int)DIR_ALL);

			double rel_x = 0.5;
			double rel_y = 0.5;

			if (pin.has("pos")) {
				Vector2 pos = pin.get("pos", Vector2());
				if (rect.size.x > 0.0f) {
					rel_x = (pos.x - rect.position.x) / rect.size.x;
				}
				if (rect.size.y > 0.0f) {
					rel_y = (pos.y - rect.position.y) / rect.size.y;
				}
			} else if (pin.has("offset")) {
				Vector2 offset = pin.get("offset", Vector2());
				if (rect.size.x > 0.0f) {
					rel_x = offset.x / rect.size.x;
				}
				if (rect.size.y > 0.0f) {
					rel_y = offset.y / rect.size.y;
				}
			} else if (pin.has("rel_x") && pin.has("rel_y")) {
				rel_x = pin.get("rel_x", 0.5);
				rel_y = pin.get("rel_y", 0.5);
			}

			rel_x = std::max(0.0, std::min(1.0, rel_x));
			rel_y = std::max(0.0, std::min(1.0, rel_y));

			new Avoid::ShapeConnectionPin(shape_ref, pin_id, rel_x, rel_y, true, port_pin_offset, dir_flags);
		}
	}

	// 2. Process Connections (Wires)
	Array connections = p_circuit_graph.get("connections", Array());
	std::vector<std::pair<Variant, Avoid::ConnRef *>> conn_list;

	for (int i = 0; i < connections.size(); ++i) {
		Dictionary conn = connections[i];
		Variant conn_id = conn.get("id", i);

		bool from_is_obstacle = conn.has("from_obstacle") && shape_map.find(conn.get("from_obstacle", Variant())) != shape_map.end();
		bool to_is_obstacle = conn.has("to_obstacle") && shape_map.find(conn.get("to_obstacle", Variant())) != shape_map.end();

		Avoid::ConnEnd src_end;
		Avoid::ConnEnd dst_end;

		if (from_is_obstacle) {
			Variant from_obs = conn.get("from_obstacle", Variant());
			int from_pin = conn.get("from_pin", 1);
			src_end = Avoid::ConnEnd(shape_map[from_obs], from_pin);
		} else {
			Vector2 from_pos = conn.get("from_pos", Vector2());
			int from_dir = conn.get("from_dir", (int)DIR_ALL);
			src_end = Avoid::ConnEnd(Avoid::Point(from_pos.x, from_pos.y), from_dir);
		}

		if (to_is_obstacle) {
			Variant to_obs = conn.get("to_obstacle", Variant());
			int to_pin = conn.get("to_pin", 1);
			dst_end = Avoid::ConnEnd(shape_map[to_obs], to_pin);
		} else {
			Vector2 to_pos = conn.get("to_pos", Vector2());
			int to_dir = conn.get("to_dir", (int)DIR_ALL);
			dst_end = Avoid::ConnEnd(Avoid::Point(to_pos.x, to_pos.y), to_dir);
		}

		Avoid::ConnRef *conn_ref = new Avoid::ConnRef(&router, src_end, dst_end);
		conn_list.push_back(std::make_pair(conn_id, conn_ref));
	}

	// 3. Solve Obstacle-avoiding Orthogonal Routes
	router.processTransaction();

	// 4. Extract Waypoints
	for (size_t i = 0; i < conn_list.size(); ++i) {
		const Avoid::PolyLine &route = conn_list[i].second->displayRoute();
		PackedVector2Array waypoints;
		for (size_t p = 0; p < route.ps.size(); ++p) {
			waypoints.append(Vector2((float)route.ps[p].x, (float)route.ps[p].y));
		}
		routes[conn_list[i].first] = waypoints;
	}

	result["success"] = true;
	result["routes"] = routes;
	return result;
}

} // namespace godot
