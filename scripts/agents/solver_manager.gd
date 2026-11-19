class_name SolverManager
extends RefCounted

## [SOLVER MANAGER] (proposal 3.2, fitur tambahan nomor 2)
##
## Memindai folder scripts/agents/ dan memuat setiap file .gd yang merupakan
## turunan SolverAgent. Menambah agen baru cukup dengan menaruh file .gd di
## folder tersebut, lalu tekan "Rescan" di UI. Tidak perlu kompilasi ulang.

const AGENT_DIR := "res://scripts/agents"
const EXCLUDED := ["solver_agent.gd", "agent_move.gd", "solver_manager.gd"]


func discover() -> Array:
	var found: Array = []
	var dir := DirAccess.open(AGENT_DIR)
	if dir == null:
		push_warning("SolverManager: folder agen tidak ditemukan: " + AGENT_DIR)
		return found

	var files := dir.get_files()
	files.sort()

	for file_name in files:
		if not file_name.ends_with(".gd"):
			continue
		if EXCLUDED.has(file_name):
			continue

		var path := AGENT_DIR + "/" + file_name
		var script := load(path)
		if script == null or not (script is GDScript):
			continue
		if not script.can_instantiate():
			continue

		var instance = script.new()
		if instance is SolverAgent:
			found.append({
				"id": file_name.get_basename(),
				"path": path,
				"agent": instance,
			})

	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _priority(a["id"]) < _priority(b["id"])
	)
	return found


func _priority(id: String) -> int:
	match id:
		"rule_based_agent":
			return 0
		"csp_agent":
			return 1
		"csp_utility_agent":
			return 2
		_:
			return 10
