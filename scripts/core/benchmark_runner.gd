class_name BenchmarkRunner
extends RefCounted

## [METRICS] Metrik komparasi agen (proposal 3.4):
##   1. Rasio kemenangan (%)
##   2. Frekuensi dan akurasi tebakan
##   3. Durasi permainan
##   4. Biaya algoritma (node yang dieksplorasi)
##
## Benchmark memberi seed yang sama ke semua agen supaya perbandingan adil.

static func run_agent(
	agent: SolverAgent,
	config: Dictionary,
	games: int,
	seed_base: int = 1
) -> Dictionary:
	var width: int = config.get("width", 9)
	var height: int = config.get("height", 9)
	var mines: int = config.get("mines", 10)
	var first_index := (height / 2) * width + (width / 2)

	var wins := 0
	var guesses := 0
	var correct_guesses := 0
	var moves := 0
	var nodes := 0
	var started := Time.get_ticks_msec()

	for game_index in games:
		agent.reset()

		var board := MinesweeperBoard.new()
		board.setup(width, height, mines, seed_base + game_index)
		board.reveal(first_index)

		var guard := 0
		var max_moves := width * height * 4
		while not board.ended and guard < max_moves:
			guard += 1
			var move := agent.next_move(board.agent_snapshot())
			if move == null or move.action == AgentMove.Action.NONE:
				break

			moves += 1
			nodes += move.nodes

			if move.is_guess and move.action == AgentMove.Action.REVEAL:
				guesses += 1
				if board.mine[move.index] == 0:
					correct_guesses += 1

			board.apply_agent_move(move)

		if board.won:
			wins += 1

	var elapsed := Time.get_ticks_msec() - started
	var guess_accuracy := 0.0
	if guesses > 0:
		guess_accuracy = float(correct_guesses) / float(guesses) * 100.0
	var guess_frequency := 0.0
	if moves > 0:
		guess_frequency = float(guesses) / float(moves) * 100.0

	return {
		"agent": agent.display_name,
		"games": games,
		"wins": wins,
		"win_rate": float(wins) / float(maxi(1, games)) * 100.0,
		"guesses": guesses,
		"correct_guesses": correct_guesses,
		"guess_accuracy": guess_accuracy,
		"guess_frequency": guess_frequency,
		"moves": moves,
		"nodes": nodes,
		"nodes_per_move": float(nodes) / float(maxi(1, moves)),
		"time_ms": elapsed,
		"avg_time_ms": float(elapsed) / float(maxi(1, games)),
	}


static func run_comparison(
	agents: Array,
	config: Dictionary,
	games: int,
	seed_base: int = 1
) -> Array:
	var results: Array = []
	for entry in agents:
		var agent: SolverAgent = entry["agent"] if entry is Dictionary else entry
		agent.reset()
		results.append(run_agent(agent, config, games, seed_base))
	return results
