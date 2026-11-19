class_name RuleBasedAgent
extends SolverAgent

## [RULE-BASED INFERENCE] / [SINGLE POINT STRATEGY]
##
## Dua aturan lokal dari proposal 3.3.1:
##   1. MINES = NUMBER - ADJACENT_FLAGS
##   2. Jika MINES == 0, semua sel tertutup di sekitar aman -> buka.
##   3. Jika MINES == jumlah sel tertutup, semuanya ranjau -> tandai.
##
## Aturan diulang setiap kali next_move() dipanggil. Jika tidak ada aturan yang
## cocok, agen terpaksa menebak (dan tebakan itu dicatat sebagai metrik).

func _init() -> void:
	display_name = "Rule-Based Inference"
	description = "Single Point Strategy: MINES = NUMBER - ADJACENT_FLAGS"


func next_move(state: Dictionary) -> AgentMove:
	var width: int = state["width"]
	var height: int = state["height"]
	var values: PackedInt32Array = state["values"]
	var flags: PackedByteArray = state["flags"]
	var total := width * height

	var any_revealed := false
	for i in total:
		if values[i] >= 0:
			any_revealed = true
			break

	if not any_revealed:
		var center := (height / 2) * width + (width / 2)
		var opening := AgentMove.reveal(center, "Papan kosong: buka sel tengah")
		opening.is_guess = true
		opening.probability = 0.0
		return opening

	var nodes := 0
	var first_hidden := -1

	# -------------------------------------------------------------------
	# [RULE-BASED INFERENCE] Evaluasi setiap angka yang sudah terbuka.
	# -------------------------------------------------------------------
	for i in total:
		if values[i] < 0:
			if first_hidden == -1 and flags[i] == 0:
				first_hidden = i
			continue

		nodes += 1
		if values[i] == 0:
			continue

		var hidden: Array[int] = []
		var adjacent_flags := 0
		for nb in neighbor_indices(i, width, height):
			if flags[nb] == 1:
				adjacent_flags += 1
			elif values[nb] < 0:
				hidden.append(nb)

		if hidden.is_empty():
			continue

		# Rumus inti proposal: Mines = Number - AdjacentFlags
		var mines_left := values[i] - adjacent_flags

		if mines_left <= 0:
			var move := AgentMove.reveal(
				hidden[0],
				"Angka %d - %d bendera = 0, sel (%d,%d) pasti aman"
				% [values[i], adjacent_flags, hidden[0] % width, hidden[0] / width]
			)
			move.nodes = nodes
			return move

		if mines_left >= hidden.size():
			var move := AgentMove.flag(
				hidden[0],
				"Angka %d - %d bendera = %d, semua %d sel tertutup pasti ranjau"
				% [values[i], adjacent_flags, mines_left, hidden.size()]
			)
			move.nodes = nodes
			return move

	# -------------------------------------------------------------------
	# [RULE-BASED INFERENCE] Tidak ada langkah pasti: pilih risiko lokal
	# terkecil, lalu buka. Keputusan ini ditandai sebagai tebakan.
	# -------------------------------------------------------------------
	var best_index := -1
	var best_risk := 2.0
	for i in total:
		if values[i] <= 0:
			continue
		var hidden: Array[int] = []
		var adjacent_flags := 0
		for nb in neighbor_indices(i, width, height):
			if flags[nb] == 1:
				adjacent_flags += 1
			elif values[nb] < 0:
				hidden.append(nb)
		if hidden.is_empty():
			continue
		var risk := float(values[i] - adjacent_flags) / float(hidden.size())
		if risk < best_risk:
			best_risk = risk
			best_index = hidden[0]

	if best_index == -1:
		best_index = first_hidden

	if best_index == -1:
		return AgentMove.none("Tidak ada sel tertutup")

	var guess := AgentMove.reveal(
		best_index,
		"Tidak ada aturan pasti, menebak sel dengan risiko lokal terkecil",
		true,
		clampf(best_risk, 0.0, 1.0)
	)
	guess.nodes = nodes
	return guess
