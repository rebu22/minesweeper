extends SceneTree

## Laporan benchmark headless untuk ketiga agen.
## Jalankan:
##   godot --headless --path . --script res://tests/bench_report.gd

const CONFIGS := [
	{"name": "Beginner", "width": 9, "height": 9, "mines": 10, "games": 50},
	{"name": "Intermediate", "width": 16, "height": 16, "mines": 40, "games": 20},
	{"name": "Expert", "width": 30, "height": 16, "mines": 99, "games": 5},
]


func _initialize() -> void:
	var agents: Array = [
		RuleBasedAgent.new(),
		CspAgent.new(),
		CspUtilityAgent.new(),
	]

	for config in CONFIGS:
		print("\n=== %s (%dx%d, %d ranjau) ===" % [
			config["name"], config["width"], config["height"], config["mines"]
		])
		for agent in agents:
			agent.reset()
			var result := BenchmarkRunner.run_agent(
				agent,
				config,
				config["games"],
				1
			)
			print(
				"%-26s menang %5.1f%% | tebakan %3d (%.0f%%, akurasi %.0f%%) | %6.1f ms/game | node %d"
				% [
					result["agent"],
					result["win_rate"],
					result["guesses"],
					result["guess_frequency"],
					result["guess_accuracy"],
					result["avg_time_ms"],
					result["nodes"],
				]
			)

	quit(0)
