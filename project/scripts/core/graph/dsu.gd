class_name DSU
extends RefCounted

## Disjoint-Set Union (Union-Find) with path compression and rank optimization.

var parent: Dictionary = {}
var rank: Dictionary = {}

func make_set(item: String) -> void:
	if not parent.has(item):
		parent[item] = item
		rank[item] = 0

func find_set(item: String) -> String:
	if not parent.has(item):
		make_set(item)
		return item
	if parent[item] != item:
		parent[item] = find_set(parent[item])
	return parent[item]

func union_sets(a: String, b: String) -> void:
	var root_a = find_set(a)
	var root_b = find_set(b)
	if root_a != root_b:
		var rank_a = rank[root_a]
		var rank_b = rank[root_b]
		if rank_a < rank_b:
			parent[root_a] = root_b
		elif rank_a > rank_b:
			parent[root_b] = root_a
		else:
			parent[root_b] = root_a
			rank[root_a] += 1
