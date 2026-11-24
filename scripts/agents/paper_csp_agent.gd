class_name PaperCspAgent
extends SolverAgent

const EPS := 0.000000001

var node_limit: int = 400000
var use_subset_rule: bool = true

var _rng := RandomNumberGenerator.new()
var _nodes: int = 0

var _s_order := PackedInt32Array()
var _s_vc: Array = []
var _s_rem_sum := PackedInt32Array()
var _s_rem_un := PackedInt32Array()
var _s_value := PackedByteArray()
var _s_by_mines: Dictionary = {}
var _s_n: int = 0
var _s_mines: int = 0
var _s_cap: int = 0
var _s_nodes: int = 0
var _s_node_limit: int = 0
var _s_truncated: bool = false


func _init() -> void:
	display_name = "CSP Paper"
	description = "Equation strategy + backtracking (Gardea dkk., CS 221, 2015)"
	_rng.randomize()


func get_options_schema() -> Array:
	return [
		{
			"key": "node_limit",
			"label": "Batas node backtracking",
			"type": "int",
			"default": 400000,
			"min": 10000,
			"max": 5000000,
			"step": 10000,
		},
		{
			"key": "use_subset_rule",
			"label": "Aktifkan aturan subset",
			"type": "bool",
			"default": true,
		},
	]


func configure(p_options: Dictionary) -> void:
	super.configure(p_options)
	node_limit = clampi(int(p_options.get("node_limit", node_limit)), 10000, 5000000)
	use_subset_rule = bool(p_options.get("use_subset_rule", use_subset_rule))


func reset() -> void:
	_nodes = 0


func next_move(state: Dictionary) -> AgentMove:
	_nodes = 0
	var ctx := _scan_board(state)
	var width: int = ctx["width"]
	var height: int = ctx["height"]
	var free_cells: Array = ctx["free_cells"]
	var remaining_mines: int = ctx["remaining_mines"]

	if int(ctx["revealed_count"]) == 0:
		var opening := AgentMove.reveal(0, "Papan kosong: buka sel sudut")
		opening.is_guess = true
		opening.nodes = _nodes
		return opening

	if free_cells.is_empty():
		return AgentMove.none("Tidak ada sel tersisa yang bisa dibuka")
	if remaining_mines < 0:
		return _fallback_guess(ctx, "Jumlah bendera melebihi jumlah ranjau")

	var built := _build_constraints(ctx)
	if not built["ok"]:
		return _fallback_guess(ctx, String(built["reason"]))
	var constraints: Array = built["constraints"]
	var frontier: Dictionary = built["frontier"]

	var simplified := _simplify(constraints)
	if not simplified["ok"]:
		return _fallback_guess(ctx, "Penyederhanaan constraint menemukan kontradiksi")
	var assigned: Dictionary = simplified["assigned"]

	var forced := _forced_move(assigned, width)
	if forced != null:
		return forced

	var remaining_constraints: Array = simplified["constraints"]
	var outside_cells := _collect_outside_cells(free_cells, frontier)

	if remaining_constraints.is_empty():
		if outside_cells.is_empty():
			return AgentMove.none("Tidak ada kandidat langkah")
		var area_risk := clampf(float(remaining_mines) / float(outside_cells.size()), 0.0, 1.0)
		return _outside_move(outside_cells, area_risk, width, height)

	var components := _split_components(remaining_constraints)
	var comp_data: Array = []
	var truncated := false
	for comp in components:
		var solved := _solve_component(comp["cells"], comp["constraints"], remaining_mines)
		var by_mines: Dictionary = solved["by_mines"]
		var comp_truncated: bool = solved["truncated"]
		if by_mines.is_empty() and not comp_truncated:
			return _fallback_guess(ctx, "Tidak ada solusi CSP yang konsisten")
		if comp_truncated:
			truncated = true
		comp_data.append(solved)

	var feasible := _feasible_groups(comp_data, remaining_mines, outside_cells.size(), truncated)
	if not feasible["ok"]:
		return _fallback_guess(ctx, "Tidak ada konfigurasi ranjau yang valid")
	var groups: Array = feasible["groups"]
	var stats := _component_stats(comp_data, groups)

	if not truncated:
		var certain := _certain_move(stats, width)
		if certain != null:
			return certain
		var shoot := _crap_shoot_move(stats, ctx)
		if shoot != null:
			return shoot

	return _best_guess(stats, outside_cells, remaining_mines, width, height)


func _scan_board(state: Dictionary) -> Dictionary:
	var width: int = state["width"]
	var height: int = state["height"]
	var values: PackedInt32Array = state["values"]
	var flags: PackedByteArray = state["flags"]
	var mines_total: int = state["mines_total"]
	var total := width * height

	var revealed_count := 0
	var flagged_count := 0
	var free_cells: Array = []
	for i in total:
		if values[i] >= 0:
			revealed_count += 1
		elif flags[i] == 1:
			flagged_count += 1
		else:
			free_cells.append(i)

	return {
		"width": width,
		"height": height,
		"values": values,
		"flags": flags,
		"total": total,
		"revealed_count": revealed_count,
		"free_cells": free_cells,
		"remaining_mines": mines_total - flagged_count,
	}


func _build_constraints(ctx: Dictionary) -> Dictionary:
	var width: int = ctx["width"]
	var height: int = ctx["height"]
	var values: PackedInt32Array = ctx["values"]
	var flags: PackedByteArray = ctx["flags"]

	var constraints: Array = []
	var frontier: Dictionary = {}
	for i in int(ctx["total"]):
		if values[i] < 0:
			continue
		var local_vars: Array = []
		var adjacent_flags := 0
		for nb in neighbor_indices(i, width, height):
			if values[nb] >= 0:
				continue
			if flags[nb] == 1:
				adjacent_flags += 1
			else:
				local_vars.append(nb)

		var mine_sum: int = values[i] - adjacent_flags
		if mine_sum < 0 or mine_sum > local_vars.size():
			return {"ok": false, "reason": "Constraint tidak konsisten dengan bendera", "constraints": [], "frontier": {}}
		if local_vars.is_empty():
			continue

		for lv in local_vars:
			frontier[lv] = true
		constraints.append({"vars": local_vars, "sum": mine_sum})

	return {"ok": true, "reason": "", "constraints": constraints, "frontier": frontier}


func _collect_outside_cells(free_cells: Array, frontier: Dictionary) -> Array:
	var outside: Array = []
	for cell in free_cells:
		if not frontier.has(cell):
			outside.append(int(cell))
	return outside


func _simplify(constraints: Array) -> Dictionary:
	var assigned: Dictionary = {}
	var current: Array = constraints
	var passes := 0

	while passes < 400:
		passes += 1
		_nodes += 1

		var changed := false
		var reduced: Array = []
		var seen: Dictionary = {}

		for c in current:
			var remaining: int = int(c["sum"])
			var vs: Array = []
			for v in c["vars"]:
				if assigned.has(v):
					remaining -= int(assigned[v])
				else:
					vs.append(int(v))
			if remaining < 0 or remaining > vs.size():
				return {"ok": false, "assigned": {}, "constraints": []}
			if vs.is_empty():
				continue
			if remaining == 0 or remaining == vs.size():
				var forced_value := 0 if remaining == 0 else 1
				for v in vs:
					assigned[v] = forced_value
				changed = true
				continue

			var key := str(vs)
			if seen.has(key):
				if int(seen[key]) != remaining:
					return {"ok": false, "assigned": {}, "constraints": []}
				continue
			seen[key] = remaining
			reduced.append({"vars": vs, "sum": remaining})

		current = reduced
		if changed:
			continue
		if not use_subset_rule:
			break

		var subset_result := _apply_subset_rule(current)
		if subset_result == -1:
			return {"ok": false, "assigned": {}, "constraints": []}
		if subset_result == 0:
			break

	return {"ok": true, "assigned": assigned, "constraints": current}


func _apply_subset_rule(eff: Array) -> int:
	var by_var: Dictionary = {}
	for ci in eff.size():
		for v in eff[ci]["vars"]:
			if not by_var.has(v):
				by_var[v] = []
			by_var[v].append(ci)

	var replaced: Dictionary = {}
	var any_replaced := false
	for ai in eff.size():
		if replaced.has(ai):
			continue
		var a: Dictionary = eff[ai]
		var a_vars: Array = a["vars"]
		var candidates: Array = by_var[a_vars[0]]
		for bi in candidates:
			if bi == ai or replaced.has(bi):
				continue
			var b: Dictionary = eff[bi]
			var b_vars: Array = b["vars"]
			if a_vars.size() >= b_vars.size():
				continue
			if not _is_subset(a_vars, b_vars):
				continue

			var diff: Array = []
			for v in b_vars:
				if not a_vars.has(v):
					diff.append(int(v))
			var new_sum: int = int(b["sum"]) - int(a["sum"])
			if new_sum < 0 or new_sum > diff.size():
				return -1
			eff[bi] = {"vars": diff, "sum": new_sum}
			replaced[bi] = true
			any_replaced = true

	return 1 if any_replaced else 0


func _is_subset(a: Array, b: Array) -> bool:
	for v in a:
		if not b.has(v):
			return false
	return true


func _forced_move(assigned: Dictionary, width: int) -> AgentMove:
	var safe_cell := -1
	var mine_cell := -1
	for key in assigned.keys():
		var cell := int(key)
		if int(assigned[key]) == 0:
			if safe_cell == -1 or cell < safe_cell:
				safe_cell = cell
		else:
			if mine_cell == -1 or cell < mine_cell:
				mine_cell = cell

	if safe_cell != -1:
		var reveal_move := AgentMove.reveal(
			safe_cell,
			"Equation strategy: sel (%d,%d) pasti aman" % [safe_cell % width, safe_cell / width]
		)
		reveal_move.nodes = _nodes
		return reveal_move

	if mine_cell != -1:
		var flag_move := AgentMove.flag(
			mine_cell,
			"Equation strategy: sel (%d,%d) pasti ranjau" % [mine_cell % width, mine_cell / width]
		)
		flag_move.nodes = _nodes
		return flag_move

	return null


func _split_components(constraints: Array) -> Array:
	var parent: Dictionary = {}
	for c in constraints:
		for v in c["vars"]:
			if not parent.has(int(v)):
				parent[int(v)] = int(v)
	for c in constraints:
		var first: int = int(c["vars"][0])
		for i in range(1, c["vars"].size()):
			_union(parent, first, int(c["vars"][i]))

	var grouped: Dictionary = {}
	for c in constraints:
		var root := _find(parent, int(c["vars"][0]))
		if not grouped.has(root):
			grouped[root] = {"cells": {}, "constraints": []}
		var group: Dictionary = grouped[root]
		var cell_set: Dictionary = group["cells"]
		for v in c["vars"]:
			cell_set[int(v)] = true
		var group_constraints: Array = group["constraints"]
		group_constraints.append(c)

	var roots: Array = grouped.keys()
	roots.sort()
	var components: Array = []
	for root in roots:
		var group: Dictionary = grouped[root]
		var cell_set: Dictionary = group["cells"]
		var cells: Array = cell_set.keys()
		cells.sort()
		components.append({"cells": cells, "constraints": group["constraints"]})
	return components


func _find(parent: Dictionary, v: int) -> int:
	var root := v
	while int(parent[root]) != root:
		root = int(parent[root])
	while int(parent[v]) != v:
		var nxt := int(parent[v])
		parent[v] = root
		v = nxt
	return root


func _union(parent: Dictionary, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[rb] = ra


func _solve_component(cells: Array, constraints: Array, cap: int) -> Dictionary:
	var n := cells.size()
	var pos: Dictionary = {}
	for i in n:
		pos[int(cells[i])] = i

	var var_constraints: Array = []
	for i in n:
		var_constraints.append([])

	var member_lists: Array = []
	var rem_sum := PackedInt32Array()
	var rem_un := PackedInt32Array()
	for ci in constraints.size():
		var c: Dictionary = constraints[ci]
		var members: Array = []
		for v in c["vars"]:
			var p: int = pos[int(v)]
			members.append(p)
			var_constraints[p].append(ci)
		member_lists.append(members)
		rem_sum.append(int(c["sum"]))
		rem_un.append(members.size())

	_s_order = _search_order(n, var_constraints, member_lists)
	_s_vc = var_constraints
	_s_rem_sum = rem_sum
	_s_rem_un = rem_un
	_s_value = PackedByteArray()
	_s_value.resize(n)
	_s_value.fill(0)
	_s_by_mines = {}
	_s_n = n
	_s_mines = 0
	_s_cap = cap
	_s_nodes = 0
	_s_node_limit = node_limit
	_s_truncated = false

	_search(0)
	_nodes += _s_nodes

	return {"cells": cells, "by_mines": _s_by_mines, "truncated": _s_truncated}


func _search_order(n: int, var_constraints: Array, member_lists: Array) -> PackedInt32Array:
	var placed := PackedByteArray()
	placed.resize(n)
	placed.fill(0)
	var linked := PackedInt32Array()
	linked.resize(n)
	linked.fill(0)
	var order := PackedInt32Array()

	for _step in n:
		var best := -1
		for v in n:
			if placed[v] == 1:
				continue
			if best == -1:
				best = v
				continue
			var v_linked := 1 if linked[v] > 0 else 0
			var best_linked := 1 if linked[best] > 0 else 0
			if v_linked != best_linked:
				if v_linked > best_linked:
					best = v
			elif var_constraints[v].size() > var_constraints[best].size():
				best = v
		placed[best] = 1
		order.append(best)
		for ci in var_constraints[best]:
			for member in member_lists[ci]:
				linked[member] += 1

	return order


func _search(depth: int) -> void:
	if _s_truncated:
		return
	if _s_nodes > _s_node_limit:
		_s_truncated = true
		return

	if depth >= _s_order.size():
		_record_solution()
		return

	var var_index: int = _s_order[depth]

	for value in 2:
		_s_nodes += 1
		if value == 1 and _s_mines >= _s_cap:
			continue

		var viable := true
		for ci in _s_vc[var_index]:
			_s_rem_sum[ci] -= value
			_s_rem_un[ci] -= 1
			if _s_rem_sum[ci] < 0 or _s_rem_sum[ci] > _s_rem_un[ci]:
				viable = false

		if viable:
			_s_value[var_index] = value
			_s_mines += value
			_search(depth + 1)
			_s_mines -= value
			_s_value[var_index] = 0

		for ci in _s_vc[var_index]:
			_s_rem_sum[ci] += value
			_s_rem_un[ci] += 1

		if _s_truncated:
			return


func _record_solution() -> void:
	var group: Dictionary
	if _s_by_mines.has(_s_mines):
		group = _s_by_mines[_s_mines]
	else:
		var fresh: Array = []
		fresh.resize(_s_n)
		fresh.fill(0)
		group = {"count": 0, "tally": fresh}
		_s_by_mines[_s_mines] = group

	group["count"] = int(group["count"]) + 1
	var tally: Array = group["tally"]
	for i in _s_n:
		if _s_value[i] == 1:
			tally[i] = int(tally[i]) + 1


func _sum_sets(a: Dictionary, b: Dictionary, limit: int) -> Dictionary:
	var out: Dictionary = {}
	for x in a.keys():
		for y in b.keys():
			var s := int(x) + int(y)
			if s <= limit:
				out[s] = true
	return out


func _feasible_groups(comp_data: Array, target: int, outside: int, truncated: bool) -> Dictionary:
	var m := comp_data.size()
	var groups: Array = []

	if truncated:
		for i in m:
			var by_mines: Dictionary = comp_data[i]["by_mines"]
			var all_groups: Dictionary = {}
			for k in by_mines.keys():
				all_groups[int(k)] = true
			groups.append(all_groups)
		return {"ok": true, "groups": groups}

	var key_sets: Array = []
	for i in m:
		var by_mines: Dictionary = comp_data[i]["by_mines"]
		var keys: Dictionary = {}
		for k in by_mines.keys():
			keys[int(k)] = true
		key_sets.append(keys)

	var prefix: Array = [{0: true}]
	for i in m:
		prefix.append(_sum_sets(prefix[i], key_sets[i], target))
	var suffix: Array = []
	suffix.resize(m + 1)
	suffix[m] = {0: true}
	for i in range(m - 1, -1, -1):
		suffix[i] = _sum_sets(suffix[i + 1], key_sets[i], target)

	var any_valid := false
	var total_sums: Dictionary = prefix[m]
	for s in total_sums.keys():
		var rest := target - int(s)
		if rest >= 0 and rest <= outside:
			any_valid = true
	if not any_valid:
		return {"ok": false, "groups": []}

	for i in m:
		var others := _sum_sets(prefix[i], suffix[i + 1], target)
		var valid: Dictionary = {}
		for k in key_sets[i].keys():
			for o in others.keys():
				var rest := target - int(k) - int(o)
				if rest >= 0 and rest <= outside:
					valid[int(k)] = true
					break
		groups.append(valid)

	return {"ok": true, "groups": groups}


func _component_stats(comp_data: Array, groups: Array) -> Array:
	var stats: Array = []
	for i in comp_data.size():
		var comp: Dictionary = comp_data[i]
		var cells: Array = comp["cells"]
		var by_mines: Dictionary = comp["by_mines"]
		var valid: Dictionary = groups[i]

		var tally: Array = []
		tally.resize(cells.size())
		tally.fill(0)
		var total := 0
		for k in by_mines.keys():
			if not valid.has(int(k)):
				continue
			var group: Dictionary = by_mines[k]
			total += int(group["count"])
			var group_tally: Array = group["tally"]
			for j in cells.size():
				tally[j] = int(tally[j]) + int(group_tally[j])

		stats.append({
			"cells": cells,
			"total": total,
			"tally": tally,
			"group_count": valid.size(),
		})
	return stats


func _certain_move(stats: Array, width: int) -> AgentMove:
	var safe_cell := -1
	var mine_cell := -1
	for st in stats:
		var total: int = st["total"]
		if total <= 0:
			continue
		var cells: Array = st["cells"]
		var tally: Array = st["tally"]
		for j in cells.size():
			var mine_solutions: int = int(tally[j])
			var cell: int = int(cells[j])
			if mine_solutions == 0:
				if safe_cell == -1 or cell < safe_cell:
					safe_cell = cell
			elif mine_solutions == total:
				if mine_cell == -1 or cell < mine_cell:
					mine_cell = cell

	if safe_cell != -1:
		var reveal_move := AgentMove.reveal(
			safe_cell,
			"Backtracking: sel (%d,%d) aman di semua solusi" % [safe_cell % width, safe_cell / width]
		)
		reveal_move.nodes = _nodes
		return reveal_move

	if mine_cell != -1:
		var flag_move := AgentMove.flag(
			mine_cell,
			"Backtracking: sel (%d,%d) ranjau di semua solusi" % [mine_cell % width, mine_cell / width]
		)
		flag_move.nodes = _nodes
		return flag_move

	return null


func _crap_shoot_move(stats: Array, ctx: Dictionary) -> AgentMove:
	var width: int = ctx["width"]
	var height: int = ctx["height"]
	var values: PackedInt32Array = ctx["values"]
	var flags: PackedByteArray = ctx["flags"]

	var best_cell := -1
	var best_risk := 2.0
	for st in stats:
		if int(st["group_count"]) != 1:
			continue
		var total: int = st["total"]
		if total <= 0:
			continue
		var cells: Array = st["cells"]
		var cell_set: Dictionary = {}
		for c in cells:
			cell_set[int(c)] = true
		if not _is_isolated(cells, cell_set, values, flags, width, height):
			continue

		var tally: Array = st["tally"]
		for j in cells.size():
			var risk := float(tally[j]) / float(total)
			if risk < best_risk - EPS:
				best_risk = risk
				best_cell = int(cells[j])

	if best_cell == -1:
		return null

	var move := AgentMove.reveal(
		best_cell,
		"Tebakan tak terhindarkan (crap shoot) berisiko %.1f%% pada sel (%d,%d)"
		% [best_risk * 100.0, best_cell % width, best_cell / width],
		true,
		best_risk
	)
	move.nodes = _nodes
	return move


func _is_isolated(
	cells: Array,
	cell_set: Dictionary,
	values: PackedInt32Array,
	flags: PackedByteArray,
	width: int,
	height: int
) -> bool:
	for c in cells:
		for nb in neighbor_indices(int(c), width, height):
			if values[nb] < 0 and flags[nb] == 0 and not cell_set.has(nb):
				return false
	return true


func _best_guess(
	stats: Array,
	outside_cells: Array,
	remaining_mines: int,
	width: int,
	height: int
) -> AgentMove:
	var best_cell := -1
	var best_risk := 2.0
	var expected_frontier := 0.0
	for st in stats:
		var total: int = st["total"]
		var cells: Array = st["cells"]
		var tally: Array = st["tally"]
		for j in cells.size():
			var risk := 0.5
			if total > 0:
				risk = float(tally[j]) / float(total)
			expected_frontier += risk
			if risk < best_risk - EPS:
				best_risk = risk
				best_cell = int(cells[j])

	if not outside_cells.is_empty():
		var outside_risk := clampf(
			(float(remaining_mines) - expected_frontier) / float(outside_cells.size()),
			0.0,
			1.0
		)
		if best_cell == -1 or outside_risk < best_risk - EPS:
			return _outside_move(outside_cells, outside_risk, width, height)

	if best_cell == -1:
		return AgentMove.none("Tidak ada kandidat langkah")

	var guess := AgentMove.reveal(
		best_cell,
		"Tebakan frontier berisiko %.1f%% pada sel (%d,%d)"
		% [best_risk * 100.0, best_cell % width, best_cell / width],
		true,
		best_risk
	)
	guess.nodes = _nodes
	return guess


func _outside_move(outside_cells: Array, risk: float, width: int, height: int) -> AgentMove:
	var pick := _pick_outside(outside_cells, width, height)
	var cell: int = pick["cell"]
	var move := AgentMove.reveal(
		cell,
		"Tebakan area tak terbatasi (%s) berisiko %.1f%% pada sel (%d,%d)"
		% [String(pick["kind"]), risk * 100.0, cell % width, cell / width],
		true,
		risk
	)
	move.nodes = _nodes
	return move


func _pick_outside(cells: Array, width: int, height: int) -> Dictionary:
	var corners: Array = []
	var edges: Array = []
	for cell in cells:
		var x: int = int(cell) % width
		var y: int = int(cell) / width
		var on_x := x == 0 or x == width - 1
		var on_y := y == 0 or y == height - 1
		if on_x and on_y:
			corners.append(int(cell))
		elif on_x or on_y:
			edges.append(int(cell))

	if not corners.is_empty():
		return {"cell": int(corners[_rng.randi_range(0, corners.size() - 1)]), "kind": "sudut"}
	if not edges.is_empty():
		return {"cell": int(edges[_rng.randi_range(0, edges.size() - 1)]), "kind": "tepi"}
	return {"cell": int(cells[_rng.randi_range(0, cells.size() - 1)]), "kind": "acak"}


func _fallback_guess(ctx: Dictionary, reason_text: String) -> AgentMove:
	var free_cells: Array = ctx["free_cells"]
	if free_cells.is_empty():
		return AgentMove.none("Tidak ada sel tertutup")

	var width: int = ctx["width"]
	var height: int = ctx["height"]
	var risk := clampf(float(ctx["remaining_mines"]) / float(free_cells.size()), 0.0, 1.0)
	var pick := _pick_outside(free_cells, width, height)
	var move := AgentMove.reveal(int(pick["cell"]), reason_text, true, risk)
	move.nodes = _nodes
	return move
