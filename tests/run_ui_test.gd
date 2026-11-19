extends SceneTree

## Uji UI headless: scene utama, klik, X-Ray, autoplay, benchmark.
## Jalankan:
##   godot --headless --path . --script res://tests/run_ui_test.gd

var failures: Array[String] = []


func _initialize() -> void:
	await _run()


func _run() -> void:
	print("=== Minesweeper AI Lab: UI smoke test ===")

	var scene := load("res://scenes/main.tscn")
	_check(scene != null, "main.tscn harus bisa dimuat")
	if scene == null:
		_finish()
		return

	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	_check(main.agents.size() == 3, "harus ada 3 agen, dapat %d" % main.agents.size())
	_check(main.cells.size() == 81, "papan beginner harus 81 sel")
	_check(main.mine_label != null, "label mines harus ada")
	_check(main.agent_select.item_count == 3, "dropdown agen harus berisi 3 item")

	# Klik manual di tengah.
	main._on_cell_reveal(40)
	await process_frame
	_check(main.board.generated, "klik pertama harus membangkitkan papan")
	_check(main.game_state == "playing", "status harus playing setelah klik")
	_check(main.board.revealed[40] == 1, "sel yang diklik harus terbuka")
	_check(main.seed_used_label.text.begins_with("Seed: "), "seed yang dipakai harus ditampilkan")

	# Bendera + X-Ray.
	var flag_target := -1
	for i in 81:
		if main.board.revealed[i] == 0:
			flag_target = i
			break
	main._on_cell_flag(flag_target)
	_check(main.board.flags_used == 1, "bendera harus terpasang lewat UI")
	main._on_xray_toggled(true)
	_check(main.xray, "X-Ray harus aktif")
	_check(main.cells[flag_target].text == "F", "sel berbendera harus menampilkan F")
	main._on_xray_toggled(false)

	# Ganti ke agen CSP, mainkan lewat Step sampai selesai.
	main._on_agent_selected(1)
	main._new_game()
	await process_frame
	var guard := 0
	while not main.board.ended and guard < 300:
		guard += 1
		main._on_step_pressed()
	_check(main.board.ended, "permainan autoplay harus selesai")
	_check(main.game_state == "won" or main.game_state == "lost", "status akhir harus won/lost")
	_check(main.reason_label.text.length() > 0, "alasan langkah agen harus terlihat")

	# Rescan agen.
	main._discover_agents()
	_check(main.agents.size() == 3, "rescan harus tetap menemukan 3 agen")

	# Benchmark kecil.
	main.benchmark_games_edit.text = "5"
	await main._on_benchmark_pressed()
	_check(main.benchmark_output.text.length() > 80, "output benchmark harus terisi")
	_check(main.benchmark_output.text.contains("Menang"), "output benchmark harus memuat metrik menang")

	# Ganti preset dan pastikan konfigurasi masuk.
	main._on_difficulty_changed(2)
	main._new_game()
	await process_frame
	_check(main.board.width == 30 and main.board.height == 16, "preset Expert harus 30x16")
	_check(main.cells.size() == 480, "papan Expert harus 480 sel")

	main.queue_free()
	await process_frame
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)
	else:
		print("OK: " + message)


func _finish() -> void:
	if failures.is_empty():
		print("\nUI SMOKE TEST PASSED")
		quit(0)
	else:
		print("\nUI FAILURES (%d):" % failures.size())
		for f in failures:
			print("  - " + f)
		quit(1)
