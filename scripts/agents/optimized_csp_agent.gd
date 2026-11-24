class_name OptimizedCspAgent
extends SolverAgent

const EPS := 0.000000001

var node_limit: int = 400000
var use_subset_rule: bool = true

var _rng := RandomNumberGenerator.new()
var _nodes: int = 0

const MAX_DEPTH := 300
const MAX_CACHE := 50000
const COUNT_LIMIT := 1.0e290

# Memo: tanda tangan subproblem constraint -> hasil (jumlah solusi per jumlah ranjau).
# Dikosongkan tiap next_move; dipakai bersama oleh semua komponen.
var _cache: Dictionary = {}

var _s_cap: int = 0
var _s_nodes: int = 0
var _s_node_limit: int = 0
var _s_truncated: bool = false


func _init() -> void:
	display_name = "CSP Optimized"
	description = "CSP Paper + bobot kombinatorial, tebakan global, propagasi + dekomposisi + cache"
	_rng.randomize()


func get_options_schema() -> Array:
	return [
		{
			"key": "node_limit",
			"label": "Batas node backtracking (total semua komponen)",
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
	_cache.clear()


func next_move(state: Dictionary) -> AgentMove:
	_nodes = 0
	_cache.clear()
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
		if remaining_mines > outside_cells.size():
			return _fallback_guess(ctx, "Sisa ranjau melebihi jumlah sel tertutup")
		# [Poin 3] Deduksi hitungan ranjau global: 0 atau semua sel sisa.
		var global_move := _outside_certain_move([remaining_mines], outside_cells, width, height)
		if global_move != null:
			return global_move
		var area_risk := clampf(float(remaining_mines) / float(outside_cells.size()), 0.0, 1.0)
		return _outside_move(outside_cells, area_risk, width, height)

	var components := _split_components(remaining_constraints)
	# [Poin 4] Anggaran node dipakai bersama. Komponen kecil diselesaikan dulu
	# agar tuntas; komponen besar memakai sisa anggaran dan bisa terpotong
	# sendiri tanpa mematikan deduksi pada komponen lain.
	components.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: int = (a["cells"] as Array).size()
		var sb: int = (b["cells"] as Array).size()
		if sa != sb:
			return sa < sb
		return int(a["cells"][0]) < int(b["cells"][0])
	)
	var comp_data: Array = []
	var budget := node_limit
	for comp in components:
		var solved := _solve_component(comp["cells"], comp["constraints"], remaining_mines, budget)
		budget = maxi(0, budget - int(solved["nodes_used"]))
		var by_mines: Dictionary = solved["by_mines"]
		if by_mines.is_empty() and not bool(solved["truncated"]):
			return _fallback_guess(ctx, "Tidak ada solusi CSP yang konsisten")
		comp_data.append(solved)

	var feasible := _feasible_groups(comp_data, remaining_mines, outside_cells.size())
	if not feasible["ok"]:
		return _fallback_guess(ctx, "Tidak ada konfigurasi ranjau yang valid")
	var groups: Array = feasible["groups"]
	var rests: Array = feasible["rests"]
	# [Poin 1] Statistik berbobot kombinatorial; [Poin 4] komponen terpotong
	# memakai heuristik lokal dan tidak dipakai untuk deduksi pasti.
	var stats := _component_stats(comp_data, groups, remaining_mines, outside_cells.size())

	# Deduksi pasti tetap sahih walau ada komponen terpotong: komponen itu
	# diperlakukan fleksibel (jumlah ranjau 0..n), sehingga himpunan konfigurasi
	# yang dipertimbangkan hanya lebih besar dari yang sebenarnya.
	# Urutan: buka sel aman dulu (frontier, lalu luar), baru pasang bendera.
	var frontier_move := _certain_move(stats, width)
	if frontier_move != null and frontier_move.action == AgentMove.Action.REVEAL:
		return frontier_move
	var outside_move := _outside_certain_move(rests, outside_cells, width, height)
	if outside_move != null and outside_move.action == AgentMove.Action.REVEAL:
		return outside_move
	if frontier_move != null:
		return frontier_move
	if outside_move != null:
		return outside_move

	return _best_guess(stats, outside_cells, remaining_mines, ctx)


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


## [Poin 5 & 6] Menghitung, untuk tiap jumlah ranjau k, banyak solusi komponen
## (count) beserta tally per sel (jumlah solusi sel itu ranjau / aman) TANPA
## mendaftar semua solusi: propagasi unit di tiap node, pemisahan otomatis
## menjadi sub-komponen independen (hasil digabung lewat konvolusi), pemilihan
## variabel dinamis (derajat constraint terbesar), dan memoisasi subproblem
## identik. Format hasil tiap k: {"count": float, "tally": {sel: float}, "safe": {sel: float}}.
func _solve_component(cells: Array, constraints: Array, cap: int, budget: int) -> Dictionary:
	_s_cap = cap
	_s_nodes = 0
	_s_node_limit = budget
	_s_truncated = false

	var by_mines: Dictionary = _solve_sub(constraints, 0)
	_nodes += _s_nodes
	if _s_truncated:
		by_mines = {}

	return {
		"cells": cells,
		"constraints": constraints,
		"by_mines": by_mines,
		"truncated": _s_truncated,
		"nodes_used": _s_nodes,
	}


## Selesaikan himpunan constraint apa pun: propagasi -> pisah komponen -> gabung.
## Hasil kosong {} berarti tidak ada solusi (atau _s_truncated true).
func _solve_sub(constraints: Array, depth: int) -> Dictionary:
	var prop := _propagate(constraints)
	if not prop["ok"]:
		return {}
	var fixed: Dictionary = prop["assigned"]
	var active: Array = prop["constraints"]

	var core: Dictionary = {0: _new_entry(1.0)}
	if not active.is_empty():
		core = {}
		var first := true
		for part in _split_components(active):
			var r := _solve_connected(part["constraints"], depth)
			if _s_truncated or r.is_empty():
				return {}
			if first:
				core = r
				first = false
			else:
				core = _combine(core, r)
				if _s_truncated or core.is_empty():
					return {}

	if fixed.is_empty():
		return core
	return _add_fixed(core, fixed)


## Satu komponen terhubung: cek memo, lalu cabangkan satu sel.
func _solve_connected(part: Array, depth: int) -> Dictionary:
	var key := _signature(part)
	if _cache.has(key):
		return _cache[key]

	_s_nodes += 1
	if _s_nodes > _s_node_limit or depth > MAX_DEPTH:
		_s_truncated = true
		return {}

	var cell := _pick_branch_cell(part)
	var result: Dictionary = {}
	for value in 2:
		var sub: Variant = _assign(part, cell, value)
		if sub == null:
			continue
		var r := _solve_sub(sub, depth + 1)
		if _s_truncated:
			return {}
		if r.is_empty():
			continue
		_merge_branch(result, r, cell, value)
		if _s_truncated:
			return {}

	if _cache.size() < MAX_CACHE:
		_cache[key] = result
	return result


## Propagasi unit: constraint dengan sisa 0 / sisa = jumlah sel menetapkan nilai
## semua selnya; ulangi sampai tetap. Mengembalikan constraint yang sudah direduksi.
func _propagate(constraints: Array) -> Dictionary:
	var assigned: Dictionary = {}
	var current: Array = constraints
	var changed := true
	while changed:
		changed = false
		var reduced: Array = []
		for c in current:
			var remaining: int = int(c["sum"])
			var vs: Array = []
			for v in c["vars"]:
				if assigned.has(v):
					remaining -= int(assigned[v])
				else:
					vs.append(v)
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
			reduced.append({"vars": vs, "sum": remaining})
		current = reduced
	return {"ok": true, "assigned": assigned, "constraints": current}


## Pilih sel yang muncul di constraint terbanyak (seri: indeks terkecil).
func _pick_branch_cell(part: Array) -> int:
	var degree: Dictionary = {}
	for c in part:
		for v in c["vars"]:
			degree[int(v)] = int(degree.get(int(v), 0)) + 1
	var best := -1
	var best_degree := -1
	for key in degree.keys():
		var d := int(degree[key])
		if d > best_degree or (d == best_degree and int(key) < best):
			best = int(key)
			best_degree = d
	return best


## Tetapkan sel = value pada semua constraint; null jika langsung kontradiksi.
func _assign(part: Array, cell: int, value: int) -> Variant:
	var out: Array = []
	for c in part:
		var vars: Array = c["vars"]
		if not vars.has(cell):
			out.append(c)
			continue
		var vs: Array = []
		for v in vars:
			if int(v) != cell:
				vs.append(v)
		var remaining: int = int(c["sum"]) - value
		if remaining < 0 or remaining > vs.size():
			return null
		out.append({"vars": vs, "sum": remaining})
	return out


func _signature(part: Array) -> String:
	var parts := PackedStringArray()
	for c in part:
		parts.append(str(c["vars"]) + ":" + str(c["sum"]))
	parts.sort()
	return "|".join(parts)


func _new_entry(count: float) -> Dictionary:
	return {"count": count, "tally": {}, "safe": {}}


func _entry_for(table: Dictionary, k: int) -> Dictionary:
	if not table.has(k):
		table[k] = _new_entry(0.0)
	return table[k]


func _scaled_add(dst: Dictionary, src: Dictionary, factor: float) -> void:
	for cell in src.keys():
		dst[cell] = float(dst.get(cell, 0.0)) + float(src[cell]) * factor


## Gabungkan hasil cabang `cell = value` ke hasil node (hasil anak tidak diubah).
func _merge_branch(result: Dictionary, child: Dictionary, cell: int, value: int) -> void:
	for k in child.keys():
		var nk := int(k) + value
		if nk > _s_cap:
			continue
		var e: Dictionary = child[k]
		var count: float = e["count"]
		var target := _entry_for(result, nk)
		var new_count := float(target["count"]) + count
		if new_count > COUNT_LIMIT:
			_s_truncated = true
			return
		target["count"] = new_count
		_scaled_add(target["tally"], e["tally"], 1.0)
		_scaled_add(target["safe"], e["safe"], 1.0)
		var bucket: Dictionary = target["tally"] if value == 1 else target["safe"]
		bucket[cell] = float(bucket.get(cell, 0.0)) + count


## Konvolusi dua sub-komponen independen (sel-selnya saling lepas).
func _combine(a: Dictionary, b: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for ka in a.keys():
		var ea: Dictionary = a[ka]
		for kb in b.keys():
			var nk := int(ka) + int(kb)
			if nk > _s_cap:
				continue
			var eb: Dictionary = b[kb]
			var ca: float = ea["count"]
			var cb: float = eb["count"]
			var product := ca * cb
			var target := _entry_for(out, nk)
			var new_count := float(target["count"]) + product
			if new_count > COUNT_LIMIT:
				_s_truncated = true
				return {}
			target["count"] = new_count
			_scaled_add(target["tally"], ea["tally"], cb)
			_scaled_add(target["safe"], ea["safe"], cb)
			_scaled_add(target["tally"], eb["tally"], ca)
			_scaled_add(target["safe"], eb["safe"], ca)
	return out


## Sel yang ditetapkan propagasi: geser jumlah ranjau dan catat tally-nya.
func _add_fixed(core: Dictionary, fixed: Dictionary) -> Dictionary:
	var shift := 0
	for cell in fixed.keys():
		shift += int(fixed[cell])
	var out: Dictionary = {}
	for k in core.keys():
		var nk := int(k) + shift
		if nk > _s_cap:
			continue
		var e: Dictionary = core[k]
		var count: float = e["count"]
		var mine_t: Dictionary = (e["tally"] as Dictionary).duplicate()
		var safe_t: Dictionary = (e["safe"] as Dictionary).duplicate()
		for cell in fixed.keys():
			if int(fixed[cell]) == 1:
				mine_t[int(cell)] = count
			else:
				safe_t[int(cell)] = count
		out[nk] = {"count": count, "tally": mine_t, "safe": safe_t}
	return out


func _sum_sets(a: Dictionary, b: Dictionary, limit: int) -> Dictionary:
	var out: Dictionary = {}
	for x in a.keys():
		for y in b.keys():
			var s := int(x) + int(y)
			if s <= limit:
				out[s] = true
	return out


func _feasible_groups(comp_data: Array, target: int, outside: int) -> Dictionary:
	var m := comp_data.size()
	var groups: Array = []

	var key_sets: Array = []
	for i in m:
		var keys: Dictionary = {}
		if bool(comp_data[i]["truncated"]):
			# Enumerasi tidak lengkap: jumlah ranjau komponen dianggap bebas.
			var n: int = (comp_data[i]["cells"] as Array).size()
			for k in range(0, mini(n, target) + 1):
				keys[k] = true
		else:
			var by_mines: Dictionary = comp_data[i]["by_mines"]
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

	var rest_set: Dictionary = {}
	var total_sums: Dictionary = prefix[m]
	for s in total_sums.keys():
		var rest := target - int(s)
		if rest >= 0 and rest <= outside:
			rest_set[rest] = true
	if rest_set.is_empty():
		return {"ok": false, "groups": [], "rests": []}

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

	return {"ok": true, "groups": groups, "rests": rest_set.keys()}

func _component_stats(comp_data: Array, groups: Array, target: int, outside: int) -> Array:
	var m := comp_data.size()
	var factors: Array = _mine_count_factors(comp_data, groups, target, outside)

	var stats: Array = []
	for i in m:
		var comp: Dictionary = comp_data[i]
		var cells: Array = comp["cells"]

		if bool(comp["truncated"]):
			stats.append({
				"cells": cells,
				"total": 0.0,
				"tally": PackedFloat64Array(),
				"safe": PackedFloat64Array(),
				"risk": _local_risks(cells, comp["constraints"]),
				"group_count": 0,
				"truncated": true,
			})
			continue

		var by_mines: Dictionary = comp["by_mines"]
		var valid: Dictionary = groups[i]
		var factor: Dictionary = factors[i]

		var tally := PackedFloat64Array()
		tally.resize(cells.size())
		tally.fill(0.0)
		var safe := PackedFloat64Array()
		safe.resize(cells.size())
		safe.fill(0.0)
		var w_tally := PackedFloat64Array()
		w_tally.resize(cells.size())
		w_tally.fill(0.0)
		var total := 0.0
		var w_total := 0.0
		for k in by_mines.keys():
			if not valid.has(int(k)):
				continue
			var group: Dictionary = by_mines[k]
			var count: float = group["count"]
			var mine_t: Dictionary = group["tally"]
			var safe_t: Dictionary = group["safe"]
			var f := 1.0
			if factor.has(int(k)):
				f = float(factor[int(k)])
			total += count
			w_total += count * f
			for j in cells.size():
				var cell := int(cells[j])
				var mt := float(mine_t.get(cell, 0.0))
				tally[j] += mt
				safe[j] += float(safe_t.get(cell, 0.0))
				w_tally[j] += mt * f

		var risk := PackedFloat64Array()
		risk.resize(cells.size())
		for j in cells.size():
			if w_total > 0.0:
				risk[j] = clampf(w_tally[j] / w_total, 0.0, 1.0)
			elif total > 0.0:
				risk[j] = clampf(tally[j] / total, 0.0, 1.0)
			else:
				risk[j] = 0.5

		stats.append({
			"cells": cells,
			"total": total,
			"tally": tally,
			"safe": safe,
			"risk": risk,
			"group_count": valid.size(),
			"truncated": false,
		})
	return stats


## [Poin 4] Heuristik lokal untuk komponen yang enumerasinya terpotong:
## risiko sel = rata-rata (sisa ranjau / jumlah sel) dari constraint yang
## memuatnya. Tally parsial sengaja tidak dipakai karena bias ke cabang awal.
func _local_risks(cells: Array, constraints: Array) -> PackedFloat64Array:
	var pos: Dictionary = {}
	for i in cells.size():
		pos[int(cells[i])] = i
	var sums := PackedFloat64Array()
	sums.resize(cells.size())
	sums.fill(0.0)
	var counts := PackedInt32Array()
	counts.resize(cells.size())
	counts.fill(0)
	for c in constraints:
		var vars: Array = c["vars"]
		var density := float(int(c["sum"])) / float(vars.size())
		for v in vars:
			var p: int = pos[int(v)]
			sums[p] += density
			counts[p] += 1
	var risk := PackedFloat64Array()
	risk.resize(cells.size())
	for j in cells.size():
		risk[j] = clampf(sums[j] / float(counts[j]), 0.0, 1.0) if counts[j] > 0 else 0.5
	return risk


## [Poin 1] Untuk tiap komponen i dan jumlah ranjau k, hitung
##   R_i(k) = sum_s O_i(s) * C(outside, target - k - s)
## dengan O_i(s) = banyak cara komponen lain memakai total s ranjau.
## Satu solusi komponen i dengan k ranjau punya bobot R_i(k) pada distribusi
## seragam atas semua konfigurasi papan. Semua nilai diskalakan (hanya rasio
## yang penting) agar tidak overflow.
func _mine_count_factors(comp_data: Array, groups: Array, target: int, outside: int) -> Array:
	var m := comp_data.size()
	var frontier_total := 0
	for i in m:
		frontier_total += (comp_data[i]["cells"] as Array).size()
	var limit := mini(target, frontier_total)

	var polys: Array = []
	for i in m:
		var by_mines: Dictionary = comp_data[i]["by_mines"]
		var valid: Dictionary = groups[i]
		var poly := PackedFloat64Array()
		poly.resize(limit + 1)
		poly.fill(0.0)
		if bool(comp_data[i]["truncated"]):
			for k in valid.keys():
				if int(k) <= limit:
					poly[int(k)] = 1.0
		else:
			for k in by_mines.keys():
				var kk := int(k)
				if valid.has(kk) and kk <= limit:
					poly[kk] = float((by_mines[k] as Dictionary)["count"])
		polys.append(_normalized(poly))

	var unit := PackedFloat64Array()
	unit.resize(limit + 1)
	unit.fill(0.0)
	unit[0] = 1.0

	var prefix: Array = [unit]
	for i in m:
		prefix.append(_convolve(prefix[i], polys[i], limit))
	var suffix: Array = []
	suffix.resize(m + 1)
	suffix[m] = unit
	for i in range(m - 1, -1, -1):
		suffix[i] = _convolve(suffix[i + 1], polys[i], limit)

	var weights := _outside_weights(outside, target)

	var factors: Array = []
	for i in m:
		var others := _convolve(prefix[i], suffix[i + 1], limit)
		var factor: Dictionary = {}
		for k in (groups[i] as Dictionary).keys():
			var kk := int(k)
			var f := 0.0
			for s in range(0, mini(limit, target - kk) + 1):
				var rest := target - kk - s
				if rest < 0 or rest > outside:
					continue
				f += others[s] * weights[rest]
			factor[kk] = f
		factors.append(factor)
	return factors


## Bobot C(outside, r) untuk r = 0..target, dibagi nilai maksimumnya (via log).
func _outside_weights(outside: int, target: int) -> PackedFloat64Array:
	var weights := PackedFloat64Array()
	weights.resize(target + 1)
	weights.fill(0.0)

	var log_fact := PackedFloat64Array()
	log_fact.resize(outside + 1)
	log_fact[0] = 0.0
	for i in range(1, outside + 1):
		log_fact[i] = log_fact[i - 1] + log(float(i))

	var top := mini(outside, target)
	var best := -1.0e300
	var logs := PackedFloat64Array()
	logs.resize(top + 1)
	for r in top + 1:
		var l := log_fact[outside] - log_fact[r] - log_fact[outside - r]
		logs[r] = l
		if l > best:
			best = l
	for r in top + 1:
		weights[r] = exp(logs[r] - best)
	return weights


func _convolve(a: PackedFloat64Array, b: PackedFloat64Array, limit: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(limit + 1)
	out.fill(0.0)
	for i in a.size():
		var ai := a[i]
		if ai == 0.0:
			continue
		for j in range(0, mini(b.size(), limit + 1 - i)):
			out[i + j] += ai * b[j]
	return _normalized(out)


func _normalized(poly: PackedFloat64Array) -> PackedFloat64Array:
	var peak := 0.0
	for v in poly:
		if v > peak:
			peak = v
	if peak > 0.0:
		for i in poly.size():
			poly[i] = poly[i] / peak
	return poly


func _certain_move(stats: Array, width: int) -> AgentMove:
	var safe_cell := -1
	var mine_cell := -1
	for st in stats:
		if bool(st["truncated"]):
			continue
		if float(st["total"]) <= 0.0:
			continue
		var cells: Array = st["cells"]
		var tally: PackedFloat64Array = st["tally"]
		var safe: PackedFloat64Array = st["safe"]
		for j in cells.size():
			var cell: int = int(cells[j])
			# tally/safe adalah jumlah nilai >= 0, jadi nol berarti benar-benar nol.
			if tally[j] == 0.0:
				if safe_cell == -1 or cell < safe_cell:
					safe_cell = cell
			elif safe[j] == 0.0:
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


func _best_guess(
	stats: Array,
	outside_cells: Array,
	remaining_mines: int,
	ctx: Dictionary
) -> AgentMove:
	var width: int = ctx["width"]
	var height: int = ctx["height"]

	var risk_map: Dictionary = {}
	var expected_frontier := 0.0
	var min_risk := 2.0
	for st in stats:
		var cells: Array = st["cells"]
		var risks: PackedFloat64Array = st["risk"]
		for j in cells.size():
			risk_map[int(cells[j])] = risks[j]
			expected_frontier += risks[j]
			if risks[j] < min_risk:
				min_risk = risks[j]

	var outside_risk := 2.0
	if not outside_cells.is_empty():
		# Risiko luar memakai ekspektasi ranjau frontier yang sudah berbobot.
		outside_risk = clampf(
			(float(remaining_mines) - expected_frontier) / float(outside_cells.size()),
			0.0,
			1.0
		)

	# [Poin 10] Di antara sel berisiko (hampir) sama, pilih yang paling informatif.
	var best_cell := -1
	var best_info := Vector2(-1.0, -1.0)
	for key in risk_map.keys():
		var cell := int(key)
		var r: float = risk_map[key]
		if r > min_risk + EPS:
			continue
		var info := _guess_info(cell, r, risk_map, outside_risk, ctx)
		if best_cell == -1 or _info_better(info, cell, best_info, best_cell):
			best_cell = cell
			best_info = info
	var best_risk := min_risk
	if best_cell != -1:
		best_risk = float(risk_map[best_cell])

	if not outside_cells.is_empty():
		if best_cell == -1 or outside_risk < best_risk - EPS:
			return _outside_move(outside_cells, outside_risk, width, height)
		if outside_risk <= best_risk + EPS:
			var pick := _pick_outside(outside_cells, width, height)
			var pick_cell: int = pick["cell"]
			var pick_info := _guess_info(pick_cell, outside_risk, risk_map, outside_risk, ctx)
			if _info_better(pick_info, pick_cell, best_info, best_cell):
				return _outside_move_at(pick, outside_risk, width)

	if best_cell == -1:
		return AgentMove.none("Tidak ada kandidat langkah")

	var guess := AgentMove.reveal(
		best_cell,
		"Tebakan frontier berisiko %.1f%% pada sel (%d,%d) (peluang kosong %.0f%%)"
		% [best_risk * 100.0, best_cell % width, best_cell / width, best_info.x * 100.0],
		true,
		best_risk
	)
	guess.nodes = _nodes
	return guess


## [Poin 10] Skor informasi sel tebakan: x = peluang sel itu aman DAN angkanya 0
## (memicu cascade), y = jumlah tetangga tertutup (info baru bagi tetangga).
## Risiko tetangga dianggap independen; tetangga berbendera membuat peluang 0 = 0.
func _guess_info(
	cell: int,
	risk: float,
	risk_map: Dictionary,
	outside_risk: float,
	ctx: Dictionary
) -> Vector2:
	var values: PackedInt32Array = ctx["values"]
	var flags: PackedByteArray = ctx["flags"]
	var p_zero := 1.0 - risk
	var unknown := 0
	for nb in neighbor_indices(cell, int(ctx["width"]), int(ctx["height"])):
		if values[nb] >= 0:
			continue
		if flags[nb] == 1:
			p_zero = 0.0
			continue
		unknown += 1
		p_zero *= 1.0 - float(risk_map.get(nb, outside_risk))
	return Vector2(p_zero, float(unknown))


func _info_better(a: Vector2, a_cell: int, b: Vector2, b_cell: int) -> bool:
	if absf(a.x - b.x) > EPS:
		return a.x > b.x
	if a.y != b.y:
		return a.y > b.y
	return a_cell < b_cell


## [Poin 3] Deduksi dari total ranjau tersisa: jika semua konfigurasi valid
## menyisakan 0 ranjau untuk sel di luar frontier, semuanya aman; jika
## menyisakan tepat sebanyak jumlah selnya, semuanya ranjau.
func _outside_certain_move(
	rests: Array,
	outside_cells: Array,
	width: int,
	height: int
) -> AgentMove:
	if rests.is_empty() or outside_cells.is_empty():
		return null

	var all_safe := true
	var all_mines := true
	for r in rests:
		if int(r) != 0:
			all_safe = false
		if int(r) != outside_cells.size():
			all_mines = false

	if all_safe:
		var pick := _pick_outside(outside_cells, width, height)
		var cell: int = pick["cell"]
		var reveal_move := AgentMove.reveal(
			cell,
			"Hitungan ranjau global: semua sel di luar frontier aman, buka (%d,%d)"
			% [cell % width, cell / width]
		)
		reveal_move.nodes = _nodes
		return reveal_move

	if all_mines:
		var mine_cell := int(outside_cells[0])
		var flag_move := AgentMove.flag(
			mine_cell,
			"Hitungan ranjau global: semua sel di luar frontier ranjau, bendera (%d,%d)"
			% [mine_cell % width, mine_cell / width]
		)
		flag_move.nodes = _nodes
		return flag_move

	return null



func _outside_move(outside_cells: Array, risk: float, width: int, height: int) -> AgentMove:
	return _outside_move_at(_pick_outside(outside_cells, width, height), risk, width)


func _outside_move_at(pick: Dictionary, risk: float, width: int) -> AgentMove:
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
