class_name CspAgent
extends SolverAgent

## [CSP] Constraint Satisfaction Problem untuk Minesweeper (proposal 2.1.5-2.1.7)
##
## Model CSP:
##   X = sel frontier (sel tertutup yang bersebelahan dengan angka)
##   D = {0, 1}  (0 aman, 1 ranjau)
##   C = untuk setiap angka n: jumlah ranjau pada tetangga tertutupnya = n
##
## Alur next_move():
##   1. Bangun variabel + constraint dari persepsi papan.
##   2. [CONSTRAINT PROPAGATION] reduksi domain (aturan langsung + aturan subset).
##   3. [BACKTRACKING] enumerasi seluruh solusi yang konsisten (per komponen).
##   4. Sel yang bernilai 0 di semua solusi -> pasti aman; 1 -> pasti ranjau.
##   5. Jika tidak ada kepastian, pilih tebakan dengan risiko terkecil.
##
## Subclass CspUtilityAgent menambahkan [UTILITY-BASED AGENT] pada langkah 5.

var enumeration_limit: int = 120000
var use_subset_rule: bool = true
var use_utility: bool = false
var utility_margin: float = 0.02

# State sementara untuk backtracking (dipakai _search).
var _e_order: Array[int] = []
var _e_vc: Array = []
var _e_rem_sum := PackedInt32Array()
var _e_rem_un := PackedInt32Array()
var _e_current := PackedByteArray()
var _e_solutions: Array = []
var _e_limit: int = 0
var _e_node_limit: int = 0
var _e_nodes: int = 0
var _e_truncated: bool = false

var _nodes: int = 0
var _log_fact: PackedFloat64Array = PackedFloat64Array()


func _init() -> void:
	display_name = "CSP"
	description = "Constraint propagation + backtracking (proposal 3.3.2)"


func get_options_schema() -> Array:
	return [
		{
			"key": "enumeration_limit",
			"label": "Batas solusi enumerasi",
			"type": "int",
			"default": 120000,
			"min": 1000,
			"max": 2000000,
			"step": 1000,
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
	enumeration_limit = clampi(int(p_options.get("enumeration_limit", enumeration_limit)), 1000, 2000000)
	use_subset_rule = bool(p_options.get("use_subset_rule", use_subset_rule))


# ===========================================================================
# [CSP] Langkah utama agen.
# ===========================================================================
func next_move(state: Dictionary) -> AgentMove:
	_nodes = 0
	var width: int = state["width"]
	var height: int = state["height"]
	var values: PackedInt32Array = state["values"]
	var flags: PackedByteArray = state["flags"]
	var mines_total: int = state["mines_total"]
	var total := width * height

	var revealed_count := 0
	var flagged_count := 0
	var hidden_cells: Array[int] = []
	for i in total:
		if values[i] >= 0:
			revealed_count += 1
		else:
			hidden_cells.append(i)
			if flags[i] == 1:
				flagged_count += 1

	var remaining_mines := mines_total - flagged_count

	if revealed_count == 0:
		var center := (height / 2) * width + (width / 2)
		var opening := AgentMove.reveal(center, "Papan kosong: buka sel tengah")
		opening.is_guess = true
		opening.nodes = _nodes
		return opening

	if hidden_cells.is_empty() or remaining_mines < 0:
		return AgentMove.none("Tidak ada sel tersisa yang bisa dibuka")

	# -------------------------------------------------------------------
	# [CSP: VARIABLES] Frontier = sel tertutup di sekitar angka.
	# -------------------------------------------------------------------
	var frontier: Dictionary = {}
	for i in total:
		if values[i] <= 0:
			continue
		for nb in neighbor_indices(i, width, height):
			if values[nb] < 0 and flags[nb] == 0:
				frontier[nb] = true

	var var_cells: Array[int] = []
	for cell in frontier.keys():
		var_cells.append(int(cell))
	var_cells.sort()

	if var_cells.is_empty():
		return _fallback_guess(state, hidden_cells, remaining_mines, "Tidak ada frontier, menebak sel tersembunyi")

	var pos: Dictionary = {}
	for i in var_cells.size():
		pos[var_cells[i]] = i

	# -------------------------------------------------------------------
	# [CSP: CONSTRAINTS] Setiap angka menghasilkan satu persamaan linear.
	# -------------------------------------------------------------------
	var constraints: Array = []
	for i in total:
		if values[i] < 0:
			continue

		var local_vars: Array[int] = []
		var adjacent_flags := 0
		for nb in neighbor_indices(i, width, height):
			if flags[nb] == 1:
				adjacent_flags += 1
			elif values[nb] < 0 and pos.has(nb):
				local_vars.append(int(pos[nb]))

		var mine_sum: int = values[i] - adjacent_flags
		if mine_sum < 0 or mine_sum > local_vars.size():
			return _fallback_guess(state, hidden_cells, remaining_mines, "Constraint tidak konsisten")

		if local_vars.is_empty():
			# Semua tetangga sudah terbuka / ditandai. Jika sisanya bukan 0,
			# berarti ada bendera yang salah: CSP tidak bisa dipercaya.
			if mine_sum != 0:
				return _fallback_guess(state, hidden_cells, remaining_mines, "Bendera tidak konsisten dengan angka")
			continue

		constraints.append({"vars": local_vars, "sum": mine_sum})

	# -------------------------------------------------------------------
	# [CONSTRAINT PROPAGATION] Reduksi domain sebelum pencarian.
	# -------------------------------------------------------------------
	var assigned: Dictionary = {}
	if not _propagate(constraints, assigned):
		return _fallback_guess(state, hidden_cells, remaining_mines, "Propagasi menemukan kontradiksi")

	# Domain yang tersisa: 0 = aman, 1 = ranjau.
	var certain_safe := -1
	var certain_mine := -1
	for v in var_cells.size():
		if not assigned.has(v):
			continue
		if int(assigned[v]) == 0 and certain_safe == -1:
			certain_safe = v
		elif int(assigned[v]) == 1 and certain_mine == -1:
			certain_mine = v

	if certain_safe != -1:
		var move := AgentMove.reveal(
			var_cells[certain_safe],
			"Constraint propagation: sel (%d,%d) pasti aman"
			% [var_cells[certain_safe] % width, var_cells[certain_safe] / width]
		)
		move.nodes = _nodes
		return move

	if certain_mine != -1:
		var move := AgentMove.flag(
			var_cells[certain_mine],
			"Constraint propagation: sel (%d,%d) pasti ranjau"
			% [var_cells[certain_mine] % width, var_cells[certain_mine] / width]
		)
		move.nodes = _nodes
		return move

	# -------------------------------------------------------------------
	# [BACKTRACKING] Tidak ada hasil propagasi: cari seluruh solusi CSP.
	# -------------------------------------------------------------------
	var effective := _effective_constraints(constraints, assigned)
	if not effective["ok"]:
		return _fallback_guess(state, hidden_cells, remaining_mines, "Constraint tidak konsisten")

	var remaining_constraints: Array = effective["constraints"]
	var unassigned: Array[int] = []
	for v in var_cells.size():
		if not assigned.has(v):
			unassigned.append(v)

	if unassigned.is_empty():
		return _fallback_guess(state, hidden_cells, remaining_mines, "Tidak ada variabel tersisa")

	# Bagi frontier menjadi komponen yang saling lepas (pemisahan komponen).
	var union_parent := _build_union(unassigned, remaining_constraints)
	var grouped: Dictionary = {}
	for v in unassigned:
		var root := _find(union_parent, int(v))
		if not grouped.has(root):
			grouped[root] = []
		grouped[root].append(int(v))

	var components: Array = []
	for root in grouped.keys():
		var cells: Array = grouped[root]
		cells.sort()
		var comp_constraints: Array = []
		for c in remaining_constraints:
			if _find(union_parent, int(c["vars"][0])) == int(root):
				comp_constraints.append(c)
		components.append({
			"cells": cells,
			"constraints": comp_constraints,
		})

	var outside_cells: Array[int] = []
	for cell in hidden_cells:
		if flags[cell] == 1:
			continue
		if not pos.has(cell):
			outside_cells.append(cell)
	outside_cells.sort()

	# Enumerasi solusi per komponen.
	var comp_data: Array = []
	for comp in components:
		var enum_result := _enumerate_component(comp["cells"], comp["constraints"])
		if enum_result["solutions"].is_empty() and not enum_result["truncated"]:
			return _fallback_guess(state, hidden_cells, remaining_mines, "Tidak ada solusi CSP yang konsisten")

		var solutions: Array = enum_result["solutions"]
		var n_vars: int = comp["cells"].size()
		var by_mines: Dictionary = {}
		for sol in solutions:
			var mine_count := 0
			for v in n_vars:
				if int(sol[v]) == 1:
					mine_count += 1
			if not by_mines.has(mine_count):
				var per_var: Array[int] = []
				per_var.resize(n_vars)
				per_var.fill(0)
				by_mines[mine_count] = {"count": 0, "per_var": per_var}
			var group: Dictionary = by_mines[mine_count]
			group["count"] = int(group["count"]) + 1
			var per_var: Array = group["per_var"]
			for v in n_vars:
				if int(sol[v]) == 1:
					per_var[v] = int(per_var[v]) + 1

		var counts: Dictionary = {}
		for k in by_mines.keys():
			counts[int(k)] = int(by_mines[k]["count"])

		comp_data.append({
			"cells": comp["cells"],
			"by_mines": by_mines,
			"counts": counts,
		})

	# -------------------------------------------------------------------
	# [BACKTRACKING] Gabungkan probabilitas seluruh komponen + sel di luar
	# frontier, lalu tentukan sel "backbone" (pasti 0 atau pasti 1).
	# -------------------------------------------------------------------
	var probability_result := _compute_probabilities(
		comp_data, var_cells, outside_cells, remaining_mines, total + 1
	)
	if not probability_result["ok"]:
		return _fallback_guess(state, hidden_cells, remaining_mines, "Tidak ada konfigurasi ranjau yang valid")

	var probabilities: Dictionary = probability_result["probabilities"]

	for cell in var_cells:
		var p: float = float(probabilities.get(cell, 0.5))
		if p <= 0.000000001:
			var move := AgentMove.reveal(
				cell,
				"Backtracking: sel (%d,%d) aman di semua solusi" % [cell % width, cell / width]
			)
			move.nodes = _nodes
			return move
		if p >= 0.999999999:
			var move := AgentMove.flag(
				cell,
				"Backtracking: sel (%d,%d) ranjau di semua solusi" % [cell % width, cell / width]
			)
			move.nodes = _nodes
			return move

	# -------------------------------------------------------------------
	# Tidak ada kepastian: pilih sel dengan probabilitas ranjau terkecil.
	# -------------------------------------------------------------------
	var candidates: Array[int] = []
	for cell in var_cells:
		candidates.append(cell)
	for cell in outside_cells:
		candidates.append(cell)

	if candidates.is_empty():
		return AgentMove.none("Tidak ada kandidat langkah")

	var best_probability := 1.0
	for cell in candidates:
		var p: float = float(probabilities.get(cell, 0.5))
		if p < best_probability:
			best_probability = p

	var chosen := -1
	var chosen_estimate := 0.0

	if use_utility:
		# ---------------------------------------------------------------
		# [UTILITY-BASED AGENT] Risiko hampir sama -> pilih langkah yang
		# diperkirakan membuka paling banyak sel.
		# ---------------------------------------------------------------
		for cell in candidates:
			var p: float = float(probabilities.get(cell, 0.5))
			if p > best_probability + utility_margin:
				continue
			var estimate := _estimate_reveal(cell, values, flags, width, height, p)
			if estimate > chosen_estimate:
				chosen_estimate = estimate
				chosen = cell
	else:
		for cell in candidates:
			var p: float = float(probabilities.get(cell, 0.5))
			if p <= best_probability + 0.000000001:
				chosen = cell
				break

	if chosen == -1:
		chosen = candidates[0]

	var guess := AgentMove.reveal(
		chosen,
		"Tebakan berisiko %.1f%% pada sel (%d,%d)%s"
		% [
			best_probability * 100.0,
			chosen % width,
			chosen / width,
			(" dengan estimasi %d sel terbuka" % int(round(chosen_estimate))) if use_utility else "",
		],
		true,
		best_probability
	)
	guess.nodes = _nodes
	guess.expected_reveal = int(round(chosen_estimate))
	return guess


# ===========================================================================
# [CONSTRAINT PROPAGATION]
# Reduksi domain: aturan langsung dan aturan subset (A subset B).
# ===========================================================================
func _propagate(constraints: Array, assigned: Dictionary) -> bool:
	var passes := 0
	while passes < 40:
		passes += 1
		_nodes += 1

		var effective := _effective_constraints(constraints, assigned)
		if not effective["ok"]:
			return false
		var eff: Array = effective["constraints"]

		var changed := false
		for c in eff:
			var total: int = int(c["sum"])
			var vs: Array = c["vars"]
			if total == 0:
				for v in vs:
					if not assigned.has(v):
						assigned[v] = 0
						changed = true
			elif total == vs.size():
				for v in vs:
					if not assigned.has(v):
						assigned[v] = 1
						changed = true

		if changed:
			continue
		if not use_subset_rule:
			break

		var signatures: Dictionary = {}
		for c in eff:
			signatures[_signature(c["vars"], int(c["sum"]))] = true

		var added := false
		for ai in eff.size():
			var a: Dictionary = eff[ai]
			for bi in eff.size():
				if ai == bi:
					continue
				var b: Dictionary = eff[bi]
				if a["vars"].size() >= b["vars"].size():
					continue
				if not _is_subset(a["vars"], b["vars"]):
					continue

				var diff: Array[int] = []
				for v in b["vars"]:
					if not a["vars"].has(v):
						diff.append(int(v))
				var new_sum: int = int(b["sum"]) - int(a["sum"])
				if new_sum < 0 or new_sum > diff.size():
					return false

				var sig := _signature(diff, new_sum)
				if not signatures.has(sig):
					constraints.append({"vars": diff, "sum": new_sum})
					signatures[sig] = true
					added = true
					if constraints.size() > 4000:
						break
			if constraints.size() > 4000:
				break

		if not added:
			break

	return true


func _effective_constraints(constraints: Array, assigned: Dictionary) -> Dictionary:
	var out: Array = []
	for c in constraints:
		var remaining: int = int(c["sum"])
		var vs: Array[int] = []
		for v in c["vars"]:
			if assigned.has(v):
				remaining -= int(assigned[v])
			else:
				vs.append(int(v))
		if remaining < 0 or remaining > vs.size():
			return {"ok": false, "constraints": []}
		if not vs.is_empty():
			out.append({"vars": vs, "sum": remaining})
	return {"ok": true, "constraints": out}


func _is_subset(a: Array, b: Array) -> bool:
	for v in a:
		if not b.has(v):
			return false
	return true


func _signature(vars: Array, total: int) -> String:
	var sorted_vars: Array[int] = []
	for v in vars:
		sorted_vars.append(int(v))
	sorted_vars.sort()
	return "%s|%d" % [str(sorted_vars), total]


# ===========================================================================
# [BACKTRACKING] Pemisahan komponen + enumerasi solusi.
# ===========================================================================
func _build_union(vars: Array, constraints: Array) -> Dictionary:
	var parent: Dictionary = {}
	for v in vars:
		parent[int(v)] = int(v)
	for c in constraints:
		var first: int = int(c["vars"][0])
		for i in range(1, c["vars"].size()):
			_union(parent, first, int(c["vars"][i]))
	return parent


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


func _enumerate_component(cells: Array, constraints: Array) -> Dictionary:
	# [DETERMINISTIC SOLUTION SEARCH] Enumerasi deterministik seluruh susunan
	# ranjau yang konsisten pada satu komponen frontier (proposal 2.1.3/2.1.7).
	var n := cells.size()
	var pos: Dictionary = {}
	for i in n:
		pos[int(cells[i])] = i

	var local_constraints: Array = []
	for c in constraints:
		var local_vars: Array[int] = []
		for v in c["vars"]:
			local_vars.append(int(pos[int(v)]))
		local_constraints.append({"vars": local_vars, "sum": int(c["sum"])})

	var var_constraints: Array = []
	for i in n:
		var_constraints.append([])

	var rem_sum := PackedInt32Array()
	var rem_un := PackedInt32Array()
	for ci in local_constraints.size():
		rem_sum.append(int(local_constraints[ci]["sum"]))
		rem_un.append(local_constraints[ci]["vars"].size())
		for lv in local_constraints[ci]["vars"]:
			var_constraints[int(lv)].append(ci)

	# Urutkan variabel dengan derajat constraint tertinggi lebih dulu (pruning).
	var order: Array[int] = []
	for i in n:
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var da: int = var_constraints[a].size()
		var db: int = var_constraints[b].size()
		if da == db:
			return a < b
		return da > db
	)

	_e_order = order
	_e_vc = var_constraints
	_e_rem_sum = rem_sum
	_e_rem_un = rem_un
	_e_current = PackedByteArray()
	_e_current.resize(n)
	_e_current.fill(0)
	_e_solutions = []
	_e_limit = enumeration_limit
	_e_node_limit = enumeration_limit * 20
	_e_nodes = 0
	_e_truncated = false

	_search(0)
	_nodes += _e_nodes

	return {
		"solutions": _e_solutions,
		"nodes": _e_nodes,
		"truncated": _e_truncated,
	}


func _search(depth: int) -> void:
	if _e_truncated:
		return
	if _e_nodes > _e_node_limit:
		_e_truncated = true
		return

	if depth >= _e_order.size():
		for v in _e_rem_sum:
			if v != 0:
				return
		_e_solutions.append(_e_current.duplicate())
		if _e_solutions.size() >= _e_limit:
			_e_truncated = true
		return

	var var_index: int = _e_order[depth]

	for value in [0, 1]:
		var viable := true
		for ci in _e_vc[var_index]:
			_e_rem_sum[ci] -= value
			_e_rem_un[ci] -= 1
			if _e_rem_sum[ci] < 0 or _e_rem_sum[ci] > _e_rem_un[ci]:
				viable = false

		_e_current[var_index] = value
		if viable:
			_search(depth + 1)

		for ci in _e_vc[var_index]:
			_e_rem_sum[ci] += value
			_e_rem_un[ci] += 1
		_e_current[var_index] = 0
		_e_nodes += 1
		if _e_truncated:
			return


# ===========================================================================
# [BACKTRACKING] Probabilitas setiap sel dari seluruh solusi yang ditemukan.
# Bobot memperhitungkan kombinasi sel di luar frontier (C(outside, mines)).
# ===========================================================================
func _compute_probabilities(
	comp_data: Array,
	var_cells: Array,
	outside_cells: Array,
	remaining_mines: int,
	max_n: int
) -> Dictionary:
	var n_comp := comp_data.size()
	if n_comp == 0:
		return {"ok": false, "probabilities": {}}

	var outside := outside_cells.size()
	if remaining_mines < 0 or remaining_mines > var_cells.size() + outside:
		return {"ok": false, "probabilities": {}}

	_build_log_factorials(max_n)

	# DP jumlah ranjau untuk komponen di kiri dan kanan.
	var prefix: Array = []
	prefix.append({0: 1.0})
	for ci in n_comp:
		var counts: Dictionary = comp_data[ci]["counts"]
		var nxt: Dictionary = {}
		var prev: Dictionary = prefix[ci]
		for a in prev.keys():
			for b in counts.keys():
				var key: int = int(a) + int(b)
				nxt[key] = float(nxt.get(key, 0.0)) + float(prev[a]) * float(counts[b])
		prefix.append(nxt)

	var suffix: Array = []
	suffix.resize(n_comp + 1)
	suffix[n_comp] = {0: 1.0}
	for ci in range(n_comp - 1, -1, -1):
		var counts: Dictionary = comp_data[ci]["counts"]
		var nxt: Dictionary = {}
		var after: Dictionary = suffix[ci + 1]
		for a in after.keys():
			for b in counts.keys():
				var key: int = int(a) + int(b)
				nxt[key] = float(nxt.get(key, 0.0)) + float(after[a]) * float(counts[b])
		suffix[ci] = nxt

	var probabilities: Dictionary = {}
	var total_log_denominator := -INF

	for ci in n_comp:
		var comp: Dictionary = comp_data[ci]
		var counts: Dictionary = comp["counts"]
		var by_mines: Dictionary = comp["by_mines"]
		var cells: Array = comp["cells"]

		var other: Dictionary = {}
		var left: Dictionary = prefix[ci]
		var right: Dictionary = suffix[ci + 1]
		for a in left.keys():
			for b in right.keys():
				var key: int = int(a) + int(b)
				other[key] = float(other.get(key, 0.0)) + float(left[a]) * float(right[b])

		var log_denominator := -INF
		for kc in counts.keys():
			for ko in other.keys():
				var outside_mines: int = remaining_mines - int(kc) - int(ko)
				if outside_mines < 0 or outside_mines > outside:
					continue
				var log_weight := (
					log(float(counts[kc]))
					+ log(float(other[ko]))
					+ _log_choose(outside, outside_mines)
				)
				log_denominator = _log_add(log_denominator, log_weight)

		if log_denominator == -INF:
			continue
		total_log_denominator = _log_add(total_log_denominator, log_denominator)

		for vi in cells.size():
			var cell: int = int(cells[vi])
			var log_numerator := -INF
			for kc in counts.keys():
				var group: Dictionary = by_mines[kc]
				var per_var: Array = group["per_var"]
				var mine_solutions: int = int(per_var[vi])
				if mine_solutions <= 0:
					continue
				for ko in other.keys():
					var outside_mines: int = remaining_mines - int(kc) - int(ko)
					if outside_mines < 0 or outside_mines > outside:
						continue
					var log_weight := (
						log(float(mine_solutions))
						+ log(float(other[ko]))
						+ _log_choose(outside, outside_mines)
					)
					log_numerator = _log_add(log_numerator, log_weight)

			if log_numerator == -INF:
				probabilities[cell] = 0.0
			else:
				probabilities[cell] = clampf(exp(log_numerator - log_denominator), 0.0, 1.0)

	if total_log_denominator == -INF:
		return {"ok": false, "probabilities": {}}

	# Probabilitas sel di luar frontier (sel yang tidak menyentuh angka).
	var expected_frontier := 0.0
	for cell in var_cells:
		expected_frontier += float(probabilities.get(cell, 0.0))
	var outside_probability := 0.0
	if outside > 0:
		outside_probability = clampf((remaining_mines - expected_frontier) / float(outside), 0.0, 1.0)
	for cell in outside_cells:
		probabilities[int(cell)] = outside_probability

	return {"ok": true, "probabilities": probabilities}


func _build_log_factorials(n: int) -> void:
	_log_fact = PackedFloat64Array()
	_log_fact.resize(n + 1)
	_log_fact[0] = 0.0
	for i in range(1, n + 1):
		_log_fact[i] = _log_fact[i - 1] + log(float(i))


func _log_choose(n: int, k: int) -> float:
	if k < 0 or k > n or n < 0:
		return -INF
	return _log_fact[n] - _log_fact[k] - _log_fact[n - k]


func _log_add(a: float, b: float) -> float:
	if a == -INF:
		return b
	if b == -INF:
		return a
	var m := maxf(a, b)
	return m + log(exp(a - m) + exp(b - m))


# ===========================================================================
# [UTILITY-BASED AGENT] Estimasi jumlah sel yang terbuka.
#
# Sel frontier (menyentuh angka) bila dibuka hanya menghasilkan 1 sel, karena
# sel itu pasti berangka. Sel di luar frontier bisa bernilai 0 sehingga
# memicu flood fill. Estimasi optimistis: peluang sel itu 0 dikali ukuran
# wilayah terhubung di sekitarnya.
# ===========================================================================
func _estimate_reveal(
	start: int,
	values: PackedInt32Array,
	flags: PackedByteArray,
	width: int,
	height: int,
	risk: float
) -> float:
	var safe_probability := clampf(1.0 - risk, 0.0, 1.0)

	for nb in neighbor_indices(start, width, height):
		if values[nb] >= 0:
			return safe_probability

	var region := _hidden_region_size(start, values, flags, width, height)

	var adjacent_hidden := 0
	for nb in neighbor_indices(start, width, height):
		if values[nb] < 0 and flags[nb] == 0:
			adjacent_hidden += 1

	# Peluang semua tetangga aman (sel bernilai 0), pendekatan binomial.
	var p_zero := pow(safe_probability, float(adjacent_hidden))
	return safe_probability * (p_zero * float(region) + (1.0 - p_zero))


func _hidden_region_size(
	start: int,
	values: PackedInt32Array,
	flags: PackedByteArray,
	width: int,
	height: int
) -> int:
	var seen: Dictionary = {start: true}
	var queue: Array[int] = [start]
	var count := 0
	var cap := width * height

	while not queue.is_empty() and count < cap:
		var current: int = queue.pop_front()
		count += 1

		var touches_clue := false
		for nb in neighbor_indices(current, width, height):
			if values[nb] >= 0:
				touches_clue = true
				break
		if touches_clue:
			continue

		for nb in neighbor_indices(current, width, height):
			if values[nb] < 0 and flags[nb] == 0 and not seen.has(nb):
				seen[nb] = true
				queue.append(nb)

	return count


# ===========================================================================
# Fallback: dipakai saat CSP tidak bisa memberi kepastian.
# ===========================================================================
func _fallback_guess(
	state: Dictionary,
	hidden_cells: Array[int],
	remaining_mines: int,
	reason_text: String
) -> AgentMove:
	if hidden_cells.is_empty():
		return AgentMove.none("Tidak ada sel tertutup")

	var flags: PackedByteArray = state["flags"]
	var candidates: Array[int] = []
	for cell in hidden_cells:
		if flags[cell] == 0:
			candidates.append(cell)
	if candidates.is_empty():
		return AgentMove.none("Semua sel tertutup sudah ditandai")

	var probability := 0.0
	if not candidates.is_empty():
		probability = clampf(float(remaining_mines) / float(candidates.size()), 0.0, 1.0)

	var move := AgentMove.reveal(candidates[0], reason_text, true, probability)
	move.nodes = _nodes
	return move
