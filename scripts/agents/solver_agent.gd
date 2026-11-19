class_name SolverAgent
extends RefCounted

## Kontrak dasar semua agen.
##
## [SOLVER MANAGER] Setiap file .gd di scripts/agents/ yang memiliki method
## next_move() akan ditemukan otomatis tanpa kompilasi ulang game.
##
## [GOAL-BASED AGENT] next_move() memilih aksi berikutnya berdasarkan
## persepsi papan, dengan tujuan akhir: seluruh sel aman terbuka.

var display_name: String = "Solver"
var description: String = ""
var options: Dictionary = {}


func _init() -> void:
	pass


## Kembalikan daftar opsi agar UI bisa membuat kontrol konfigurasi otomatis.
## [SOLVER CONTROL] Format: {key, label, type, default, min, max, step}
func get_options_schema() -> Array:
	return []


## [SOLVER CONTROL] Terapkan konfigurasi dari UI tanpa mengubah source code.
func configure(p_options: Dictionary) -> void:
	options = p_options.duplicate(true)


## Dipanggil sebelum setiap permainan baru (dipakai benchmark).
func reset() -> void:
	pass


## [GOAL-BASED AGENT] Inti agen. `state` adalah hasil MinesweeperBoard.agent_snapshot().
func next_move(_state: Dictionary) -> AgentMove:
	return AgentMove.none("Agen dasar tidak punya strategi")


# ---------------------------------------------------------------------------
# Helper bersama: daftar tetangga valid dan utilitas kecil.
# ---------------------------------------------------------------------------
func neighbor_indices(index: int, width: int, height: int) -> PackedInt32Array:
	var x := index % width
	var y := index / width
	var result: PackedInt32Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx := x + dx
			var ny := y + dy
			if nx >= 0 and ny >= 0 and nx < width and ny < height:
				result.append(ny * width + nx)
	return result
