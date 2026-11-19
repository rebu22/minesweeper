extends SceneTree

## Uji headless: logika papan + ketiga agen.
## Jalankan:
##   godot --headless --path . --script res://tests/run_headless.gd

var failures: Array[String] = []


func _initialize() -> void:
	print("=== Minesweeper AI Lab: headless test ===")

	_test_board_generation()
	_test_reveal_and_win()
	_test_flags_and_snapshot()

	_play_games("Rule-Based", RuleBasedAgent.new(), 100)
	_play_games("CSP", CspAgent.new(), 100)
	_play_games("CSP + Utility", CspUtilityAgent.new(), 100)

	if failures.is_empty():
		print("\nALL TESTS PASSED")
		quit(0)
	else:
		print("\nFAILURES (%d):" % failures.size())
		for f in failures:
			print("  - " + f)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _test_board_generation() -> void:
	var board := MinesweeperBoard.new()
	board.setup(9, 9, 10, 12345)
	board.reveal(40)

	var mines := 0
	for i in 81:
		if board.mine[i] == 1:
			mines += 1
	_check(mines == 10, "jumlah ranjau harus 10, dapat %d" % mines)
	_check(board.mine[40] == 0, "sel pertama harus aman")
	for nb in board.neighbors[40]:
		_check(board.mine[nb] == 0, "tetangga sel pertama harus aman")

	# Seed yang sama harus menghasilkan papan yang sama.
	var board2 := MinesweeperBoard.new()
	board2.setup(9, 9, 10, 12345)
	board2.reveal(40)
	var same := true
	for i in 81:
		if board.mine[i] != board2.mine[i]:
			same = false
	_check(same, "seed yang sama harus menghasilkan papan yang sama")
	print("OK: board generation + seed")


func _test_reveal_and_win() -> void:
	var board := MinesweeperBoard.new()
	board.setup(9, 9, 10, 999)
	board.reveal(40)

	for i in 81:
		if board.mine[i] == 0 and board.revealed[i] == 0:
			board.reveal(i)

	_check(board.won, "membuka semua sel aman harus menang")
	_check(board.ended, "permainan harus berakhir setelah menang")
	print("OK: reveal, flood fill, win condition")


func _test_flags_and_snapshot() -> void:
	var board := MinesweeperBoard.new()
	board.setup(9, 9, 10, 7)
	board.reveal(40)

	var hidden := -1
	for i in 81:
		if board.revealed[i] == 0:
			hidden = i
			break
	_check(hidden != -1, "harus ada sel tertutup")

	board.toggle_flag(hidden)
	_check(board.flags_used == 1, "flag harus terpasang")
	var snapshot := board.agent_snapshot()
	_check(snapshot["flags"][hidden] == 1, "snapshot harus memuat flag")
	_check(snapshot["values"][hidden] == -1, "snapshot tidak boleh membocorkan isi sel")
	_check(not snapshot.has("mine"), "snapshot tidak boleh memuat array ranjau")
	board.toggle_flag(hidden)
	_check(board.flags_used == 0, "flag harus bisa dilepas")
	print("OK: flags + agent snapshot (tanpa kebocoran ranjau)")


func _play_games(label: String, agent: SolverAgent, games: int) -> void:
	var wins := 0
	var guesses := 0
	var correct_guesses := 0
	var illegal_certain := 0
	var total_moves := 0
	var started := Time.get_ticks_msec()

	for game_index in games:
		agent.reset()
		var board := MinesweeperBoard.new()
		board.setup(9, 9, 10, 1000 + game_index)
		board.reveal(40)

		var guard := 0
		while not board.ended and guard < 400:
			guard += 1
			var move := agent.next_move(board.agent_snapshot())
			if move == null or move.action == AgentMove.Action.NONE:
				break
			total_moves += 1

			if move.is_guess and move.action == AgentMove.Action.REVEAL:
				guesses += 1

			if move.action == AgentMove.Action.REVEAL and not move.is_guess:
				if board.mine[move.index] == 1:
					illegal_certain += 1

			if move.is_guess and move.action == AgentMove.Action.REVEAL and board.mine[move.index] == 0:
				correct_guesses += 1

			board.apply_agent_move(move)

		if board.won:
			wins += 1

	var elapsed := Time.get_ticks_msec() - started
	var accuracy := 0.0
	if guesses > 0:
		accuracy = float(correct_guesses) / float(guesses) * 100.0

	print(
		"OK: %-14s menang %3d/%d (%.0f%%), tebakan %d (akurasi %.0f%%), langkah %d, %d ms"
		% [label, wins, games, float(wins) / games * 100.0, guesses, accuracy, total_moves, elapsed]
	)
	_check(illegal_certain == 0, "%s: ada langkah 'pasti' yang justru mengenai ranjau" % label)
	_check(wins > 0, "%s: agen harus menang minimal satu kali" % label)
	_check(total_moves > 0, "%s: agen tidak menghasilkan langkah" % label)
