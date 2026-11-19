class_name MinesweeperBoard
extends RefCounted

## Papan Minesweeper murni (tanpa UI).
##
## Kode ini adalah "lingkungan" yang dipersepsikan agen. Agen hanya boleh
## membaca agent_snapshot(); ia tidak pernah membaca array `mine` secara
## langsung. Fitur X-Ray di UI juga hanya membaca `mine` untuk pengamat.
##
## Penanda konsep:
##   [GOAL-BASED AGENT]      aturan menang / kondisi tujuan
##   [GAME RULES]            aturan 3.1 pada proposal
##   [BOARD GENERATION]      pembangkitan papan dengan seed (3.2.1)

const HIDDEN := -1

# ---------------------------------------------------------------------------
# [GAME RULES] State dasar papan. Satu indeks = satu sel, urutan baris-major.
# ---------------------------------------------------------------------------
var width: int = 9
var height: int = 9
var mine_total: int = 10
var seed_value: int = 0
var used_seed: int = 0

var mine := PackedByteArray()       # 1 = ranjau (rahasia, hanya untuk UI/pengamat)
var revealed := PackedByteArray()   # 1 = sudah dibuka
var flagged := PackedByteArray()    # 1 = ditandai bendera
var adjacent := PackedByteArray()   # 0..8, jumlah ranjau di 8 tetangga

var neighbors: Array[PackedInt32Array] = []

var generated: bool = false
var ended: bool = false
var won: bool = false
var exploded_index: int = -1
var revealed_safe: int = 0
var flags_used: int = 0

# ---------------------------------------------------------------------------
# [GAME RULES] Menyiapkan papan kosong. Ranjau baru dipasang saat klik pertama
# supaya sel pertama selalu aman (first-click safe).
# ---------------------------------------------------------------------------
func setup(p_width: int, p_height: int, p_mines: int, p_seed: int = 0) -> void:
	width = maxi(2, p_width)
	height = maxi(2, p_height)
	var cell_count := width * height
	mine_total = clampi(p_mines, 0, maxi(0, cell_count - 1))
	seed_value = p_seed

	mine.resize(cell_count)
	mine.fill(0)
	revealed.resize(cell_count)
	revealed.fill(0)
	flagged.resize(cell_count)
	flagged.fill(0)
	adjacent.resize(cell_count)
	adjacent.fill(0)

	generated = false
	ended = false
	won = false
	exploded_index = -1
	revealed_safe = 0
	flags_used = 0
	_build_neighbors()


# ---------------------------------------------------------------------------
# [BOARD GENERATION] Seed membuat susunan ranjau dapat direplikasi.
# ---------------------------------------------------------------------------
func generate(safe_index: int) -> void:
	if generated:
		return

	var rng := RandomNumberGenerator.new()
	if seed_value == 0:
		rng.randomize()
		used_seed = int(rng.seed)
	else:
		used_seed = seed_value
		rng.seed = used_seed

	# First-click safe: sel pertama dan 8 tetangganya bebas ranjau.
	var banned := {safe_index: true}
	for nb in neighbors[safe_index]:
		banned[nb] = true
	if width * height - banned.size() < mine_total:
		banned = {safe_index: true}

	var pool: Array[int] = []
	for i in width * height:
		if not banned.has(i):
			pool.append(i)

	# Fisher-Yates dengan RNG ber-seed agar urutan konsisten.
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := pool[i]
		pool[i] = pool[j]
		pool[j] = tmp

	for i in range(mini(mine_total, pool.size())):
		mine[pool[i]] = 1

	# Hitung angka petunjuk untuk setiap sel aman.
	for i in width * height:
		if mine[i] == 1:
			adjacent[i] = 0
			continue
		var count := 0
		for nb in neighbors[i]:
			if mine[nb] == 1:
				count += 1
		adjacent[i] = count

	generated = true


# ---------------------------------------------------------------------------
# [GAME RULES] Membuka satu sel. Jika sel kosong (angka 0), lakukan flood fill
# berantai sampai menyentuh sel berangka (sesuai proposal 3.1 nomor 3B).
# ---------------------------------------------------------------------------
func reveal(index: int) -> Dictionary:
	var result := {
		"changed": false,
		"hit_mine": false,
		"opened": PackedInt32Array(),
		"won": false,
	}
	if ended or index < 0 or index >= width * height:
		return result
	if revealed[index] == 1 or flagged[index] == 1:
		return result

	if not generated:
		generate(index)

	if mine[index] == 1:
		revealed[index] = 1
		exploded_index = index
		ended = true
		won = false
		result.changed = true
		result.hit_mine = true
		result.opened.append(index)
		return result

	var opened: PackedInt32Array = []
	var stack: Array[int] = [index]

	while not stack.is_empty():
		var current: int = stack.pop_back()
		if revealed[current] == 1 or flagged[current] == 1:
			continue
		if mine[current] == 1:
			# Hanya mungkin terjadi lewat chording; ditangani di atas.
			continue

		revealed[current] = 1
		opened.append(current)
		revealed_safe += 1

		if adjacent[current] == 0:
			for nb in neighbors[current]:
				if revealed[nb] == 0 and flagged[nb] == 0:
					stack.append(nb)

	result.changed = not opened.is_empty()
	result.opened = opened

	# -----------------------------------------------------------------
	# [GOAL-BASED AGENT] Kondisi tujuan: semua sel aman terbuka.
	# -----------------------------------------------------------------
	if revealed_safe >= width * height - mine_total:
		ended = true
		won = true
	result.won = won
	return result


# ---------------------------------------------------------------------------
# [GAME RULES] Klik kanan: pasang / lepas bendera.
# ---------------------------------------------------------------------------
func toggle_flag(index: int) -> bool:
	if ended or index < 0 or index >= width * height or revealed[index] == 1:
		return false
	if flagged[index] == 1:
		flagged[index] = 0
		flags_used -= 1
	else:
		flagged[index] = 1
		flags_used += 1
	return true


# ---------------------------------------------------------------------------
# [GAME RULES] Chording: klik kiri + kanan pada angka. Jika jumlah bendera di
# sekitarnya sama dengan angka, buka semua tetangga yang masih tertutup.
# ---------------------------------------------------------------------------
func chord(index: int) -> bool:
	if ended or index < 0 or index >= width * height:
		return false
	if revealed[index] == 0 or adjacent[index] <= 0:
		return false

	var flag_count := 0
	for nb in neighbors[index]:
		if flagged[nb] == 1:
			flag_count += 1
	if flag_count != adjacent[index]:
		return false

	for nb in neighbors[index]:
		if revealed[nb] == 0 and flagged[nb] == 0:
			reveal(nb)
			if ended and not won:
				break
	return true


# ---------------------------------------------------------------------------
# [GOAL-BASED AGENT] Persepsi agen. Sengaja TIDAK memuat array `mine`, jadi
# X-Ray di UI tidak bisa "dibaca" oleh agen.
# ---------------------------------------------------------------------------
func agent_snapshot() -> Dictionary:
	var values := PackedInt32Array()
	values.resize(width * height)
	values.fill(HIDDEN)
	for i in width * height:
		if revealed[i] == 1 and mine[i] == 0:
			values[i] = adjacent[i]

	return {
		"width": width,
		"height": height,
		"values": values,
		"flags": flagged.duplicate(),
		"mines_total": mine_total,
		"revealed_count": revealed_safe,
		"safe_total": width * height - mine_total,
	}


# ---------------------------------------------------------------------------
# [GOAL-BASED AGENT] Eksekusi aksi agen pada lingkungan. Satu fungsi dipakai
# oleh autoplay di UI maupun benchmark, sehingga keduanya berperilaku sama.
# ---------------------------------------------------------------------------
func apply_agent_move(move: AgentMove) -> Dictionary:
	if move == null or move.action == AgentMove.Action.NONE:
		return {"applied": false}
	if move.action == AgentMove.Action.REVEAL:
		var result := reveal(move.index)
		result["applied"] = result.changed
		return result
	if move.action == AgentMove.Action.FLAG:
		return {"applied": toggle_flag(move.index), "flagged": true}
	return {"applied": false}


func remaining_mines() -> int:
	return mine_total - flags_used


func index_of(x: int, y: int) -> int:
	return y * width + x


func is_inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


# ---------------------------------------------------------------------------
# Internal: daftar 8 tetangga untuk setiap indeks (dipakai semua agen).
# ---------------------------------------------------------------------------
func _build_neighbors() -> void:
	neighbors.clear()
	for y in height:
		for x in width:
			var list: PackedInt32Array = []
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var nx := x + dx
					var ny := y + dy
					if nx >= 0 and ny >= 0 and nx < width and ny < height:
						list.append(ny * width + nx)
			neighbors.append(list)
