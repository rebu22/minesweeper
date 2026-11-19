# Peta Kode ke Proposal

Dokumen ini memetakan setiap bagian proposal ke file dan fungsi di proyek.
Tag komentar di source code memakai `#` karena GDScript tidak memakai `//`.

## Bab I - Pendahuluan

| Konsep proposal | Implementasi |
|---|---|
| Minesweeper sebagai lingkungan agen | `scripts/core/minesweeper_board.gd` |
| Aturan menang: semua sel aman terbuka | `MinesweeperBoard.reveal()` - tag `[GOAL-BASED AGENT]` |

## Bab II - Landasan Teori

| Sub-bab proposal | File / fungsi | Tag |
|---|---|---|
| 2.1.1 Minesweeper inference | `scripts/agents/csp_agent.gd` (`next_move`) | `[CSP]` |
| 2.1.2 Decision version | `scripts/core/benchmark_runner.gd` (validasi hasil permainan) | `[METRICS]` |
| 2.1.3 Search version / DSS | `CspAgent._enumerate_component()` dan `_compute_probabilities()` | `[DETERMINISTIC SOLUTION SEARCH]`, `[BACKTRACKING]` |
| 2.1.4 Goal-Based Agent | `MinesweeperBoard.reveal()` (kondisi tujuan), `main.gd` (`_on_autoplay_tick`, `_perform_agent_step`) | `[GOAL-BASED AGENT]` |
| 2.1.4 Utility-Based Agent | `CspAgent.next_move()` bagian pemilihan tebakan, `csp_utility_agent.gd` | `[UTILITY-BASED AGENT]` |
| 2.1.5 CSP: variabel | `CspAgent.next_move()` bagian `var_cells` / frontier | `[CSP: VARIABLES]` |
| 2.1.5 CSP: domain `{0,1}` | `CspAgent` - nilai `assigned` 0 = aman, 1 = ranjau | `[CSP]` |
| 2.1.5 CSP: constraint | `CspAgent.next_move()` bagian `constraints` | `[CSP: CONSTRAINTS]` |
| 2.1.6 Constraint propagation | `CspAgent._propagate()` dan `_effective_constraints()` | `[CONSTRAINT PROPAGATION]` |
| 2.1.7 Backtracking | `CspAgent._search()` dan `_enumerate_component()` | `[BACKTRACKING]` |

## Bab III - Rancangan dan Implementasi

### 3.1 Aturan permainan

| Aturan | Implementasi |
|---|---|
| Membuka sel | `MinesweeperBoard.reveal()` |
| Klik kiri | `main.gd` (`_on_cell_reveal`) |
| Klik kanan (bendera) | `MinesweeperBoard.toggle_flag()`, `main.gd` (`_on_cell_flag`) |
| Chording | `MinesweeperBoard.chord()`, `main.gd` (`_on_cell_chord`), `scripts/ui/cell_button.gd` |
| Angka 1-8 | `MinesweeperBoard.adjacent`, tampilan di `main.gd` (`_update_cell`) |
| Sel kosong + flood fill | `MinesweeperBoard.reveal()` |
| Kondisi menang | `MinesweeperBoard.reveal()` - tag `[GOAL-BASED AGENT]` |
| Kondisi kalah + tampilkan ranjau | `MinesweeperBoard.reveal()`, `main.gd` (`_update_cell`) |

### 3.2 Rancangan game

| Fitur | Implementasi | Tag |
|---|---|---|
| Board generation + preset + custom | `main.gd` (`_current_config`, `_on_difficulty_changed`, `_new_game`) | `[BOARD GENERATION]` |
| Seed untuk replikasi | `MinesweeperBoard.generate()` | `[BOARD GENERATION]` |
| Timer | `main.gd` (`_start_timer`, `_stop_timer`, `_process`) | `[GAME RULES]` |
| Sisa ranjau | `MinesweeperBoard.remaining_mines()`, `main.gd` (`_update_counters`) | `[GAME RULES]` |
| X-Ray | `main.gd` (`_on_xray_toggled`, `_update_cell`) | `[X-RAY]` |
| Solver Manager | `scripts/agents/solver_manager.gd`, `main.gd` (`_discover_agents`) | `[SOLVER MANAGER]` |
| Solver Control | `SolverAgent.get_options_schema()`, `main.gd` (`_build_agent_options`) | `[SOLVER CONTROL]` |

### 3.3 Rancangan agen

| Agen | File | Tag utama |
|---|---|---|
| 3.3.1 Rule-based inference | `scripts/agents/rule_based_agent.gd` | `[RULE-BASED INFERENCE]`, `[SINGLE POINT STRATEGY]` |
| 3.3.2 CSP | `scripts/agents/csp_agent.gd` | `[CSP]`, `[CONSTRAINT PROPAGATION]`, `[BACKTRACKING]` |
| 3.3.3 CSP + utilitas informasi | `scripts/agents/csp_utility_agent.gd` | `[UTILITY-BASED AGENT]` |
| Kontrak modular agen | `scripts/agents/solver_agent.gd`, `scripts/agents/agent_move.gd` | `[SOLVER MANAGER]` |

### 3.4 Metrik komparasi

| Metrik | Implementasi |
|---|---|
| Rasio kemenangan (%) | `scripts/core/benchmark_runner.gd` (`win_rate`) |
| Frekuensi tebakan | `BenchmarkRunner.run_agent()` (`guess_frequency`) |
| Akurasi tebakan | `BenchmarkRunner.run_agent()` (`guess_accuracy`) |
| Durasi permainan | `BenchmarkRunner.run_agent()` (`avg_time_ms`) |
| Biaya algoritma / node | `AgentMove.nodes`, `BenchmarkRunner.run_agent()` (`nodes`, `nodes_per_move`) |
| Tampilan hasil | `main.gd` (`_render_benchmark`) |

## Alur satu langkah agen

```
main.gd  _perform_agent_step()
   -> MinesweeperBoard.agent_snapshot()      # persepsi, tanpa data ranjau
   -> SolverAgent.next_move(state)            # agen memilih aksi
        -> CspAgent: constraint propagation
        -> CspAgent: backtracking / enumerasi solusi
        -> CspAgent: pilih risiko terkecil (atau utilitas)
   -> MinesweeperBoard.apply_agent_move()     # eksekusi di lingkungan
   -> cek board.ended / board.won             # evaluasi goal
```

## Cara membaca penanda

Contoh di `csp_agent.gd`:

```gdscript
# -------------------------------------------------------------------
# [CONSTRAINT PROPAGATION] Reduksi domain sebelum pencarian.
# -------------------------------------------------------------------
var assigned: Dictionary = {}
if not _propagate(constraints, assigned):
    return _fallback_guess(...)
```

Artinya blok tersebut adalah implementasi Constraint Propagation yang dimaksud
proposal pada sub-bab 2.1.6, dan dipakai oleh agen CSP pada sub-bab 3.3.2.
