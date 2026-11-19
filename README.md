# Minesweeper AI Lab

Implementasi Kecerdasan Buatan untuk menyelesaikan permainan Minesweeper,
dibangun dengan Godot 4.7 dan GDScript. Proyek ini mengikuti `Proposal.pdf`
(Kelompok 2) sebagai acuan: permainan lengkap, tiga agen, fitur analisis
X-Ray, Solver Manager, dan metrik komparasi.

## Menjalankan

Prasyarat: Godot 4.7 atau lebih baru (standard build, bukan .NET).

```bash
# dari folder proyek
godot --path .
```

Atau buka `project.godot` lewat Godot Project Manager, lalu tekan F5.

Build yang dipakai saat pengembangan: Godot `4.7.2.stable`.

## Kontrol

| Input                       | Aksi                               |
| --------------------------- | ---------------------------------- |
| Klik kiri                   | Buka sel                           |
| Klik kanan                  | Pasang / lepas bendera             |
| Klik kiri + kanan bersamaan | Chording                           |
| Klik tengah                 | Chording                           |
| `F`                         | Bendera pada sel yang sedang fokus |
| `X`                         | Aktifkan / matikan X-Ray           |
| `A`                         | Mulai / jeda autoplay              |
| `R`                         | Permainan baru                     |
| `Esc`                       | Hentikan autoplay                  |

Sel dapat difokuskan dengan `Tab`, lalu dibuka dengan `Enter` atau `Space`.

## Fitur permainan (proposal 3.1 dan 3.2)

- Papan dengan preset Beginner, Intermediate, Expert, dan ukuran custom.
- Seed dapat diisi agar susunan ranjau dapat direplikasi.
- Sel pertama selalu aman: ranjau dipasang setelah klik pertama.
- Angka 1-8, flood fill untuk sel kosong, bendera, dan chording.
- Timer, sisa ranjau, status menang / kalah, dan pembongkaran seluruh ranjau
  saat kalah.
- X-Ray: pengamat melihat posisi ranjau, tetapi agen tidak. Agen hanya menerima
  `agent_snapshot()` yang tidak memuat array ranjau.
- Solver Manager: agen dimuat dari folder `scripts/agents/` tanpa kompilasi
  ulang. Tambah file, tekan **Rescan**.
- Solver Control: setiap agen mendeklarasikan opsinya lewat
  `get_options_schema()`, dan UI membuat kontrolnya otomatis.
- Benchmark: membandingkan semua agen pada ukuran papan dan seed yang sama.

## Tiga agen

1. **Rule-Based Inference** (`scripts/agents/rule_based_agent.gd`)
   Single Point Strategy: `MINES = NUMBER - ADJACENT_FLAGS`. Jika nilainya 0,
   sel di sekitar aman. Jika nilainya sama dengan jumlah sel tertutup, semuanya
   ranjau. Jika buntu, agen menebak.

2. **CSP** (`scripts/agents/csp_agent.gd`)
   Variabel = sel frontier, domain `{0,1}`, constraint = persamaan dari setiap
   angka. Constraint propagation mereduksi domain (aturan langsung dan aturan
   subset), lalu backtracking mengevaluasi seluruh solusi yang konsisten.
   Sel yang bernilai 0 di semua solusi dibuka; yang bernilai 1 ditandai.

3. **CSP + Utility** (`scripts/agents/csp_utility_agent.gd`)
   Sama seperti CSP, tetapi ketika tidak ada kepastian dan beberapa langkah
   memiliki risiko hampir sama, agen memilih langkah dengan estimasi jumlah
   sel terbuka terbesar.

## Penanda di source code

GDScript memakai `#` untuk komentar, bukan `//`. Setiap konsep diberi tag yang
sama di seluruh proyek:

| Tag                                                 | Arti                                             | Lokasi utama                                                                 |
| --------------------------------------------------- | ------------------------------------------------ | ---------------------------------------------------------------------------- |
| `[GOAL-BASED AGENT]`                                | Tujuan menang dan loop evaluasi aksi             | `minesweeper_board.gd` (`reveal`), `main.gd` (`_on_autoplay_tick`)           |
| `[UTILITY-BASED AGENT]`                             | Pemilihan langkah berdasarkan utilitas informasi | `csp_agent.gd`, `csp_utility_agent.gd`                                       |
| `[RULE-BASED INFERENCE]`                            | Inferensi aturan lokal                           | `rule_based_agent.gd`                                                        |
| `[SINGLE POINT STRATEGY]`                           | Rumus `MINES = NUMBER - ADJACENT_FLAGS`          | `rule_based_agent.gd`                                                        |
| `[CSP]` / `[CSP: VARIABLES]` / `[CSP: CONSTRAINTS]` | Model CSP                                        | `csp_agent.gd` (`next_move`)                                                 |
| `[CONSTRAINT PROPAGATION]`                          | Reduksi domain                                   | `csp_agent.gd` (`_propagate`)                                                |
| `[BACKTRACKING]`                                    | Pencarian seluruh solusi dan backbone            | `csp_agent.gd` (`_enumerate_component`, `_search`, `_compute_probabilities`) |
| `[DETERMINISTIC SOLUTION SEARCH]`                   | Enumerasi deterministik                          | `csp_agent.gd` (`_enumerate_component`)                                      |
| `[SOLVER MANAGER]`                                  | Pemuatan agen modular                            | `solver_manager.gd`, `main.gd` (`_discover_agents`)                          |
| `[SOLVER CONTROL]`                                  | Konfigurasi agen dari UI                         | `solver_agent.gd`, `main.gd` (`_build_agent_options`)                        |
| `[X-RAY]`                                           | Tampilan ranjau untuk pengamat                   | `main.gd` (`_on_xray_toggled`, `_update_cell`)                               |
| `[METRICS]`                                         | Rasio menang, tebakan, durasi, biaya node        | `benchmark_runner.gd`, `main.gd` (`_render_benchmark`)                       |
| `[GAME RULES]`                                      | Aturan permainan                                 | `minesweeper_board.gd`                                                       |
| `[BOARD GENERATION]`                                | Pembangkitan papan ber-seed                      | `minesweeper_board.gd` (`generate`)                                          |

Peta lengkap per sub-bab proposal ada di `CODE_MAP.md`.

## Menambah agen baru

1. Buat file di `scripts/agents/`, misalnya `random_agent.gd`.
2. Turunkan dari `SolverAgent` dan implementasikan `next_move()`.

```gdscript
class_name RandomAgent
extends SolverAgent

func _init() -> void:
    display_name = "Random"
    description = "Contoh agen baru"

func next_move(state: Dictionary) -> AgentMove:
    var values: PackedInt32Array = state["values"]
    for i in values.size():
        if values[i] < 0:
            return AgentMove.reveal(i, "Pilih sel tertutup pertama", true, 0.5)
    return AgentMove.none()
```

3. Tekan **Rescan** di panel Solver. Agen langsung muncul tanpa kompilasi ulang.

Agen yang butuh parameter dapat mengoverride `get_options_schema()` dan
`configure()`. Contohnya ada di `csp_agent.gd` dan `csp_utility_agent.gd`.

## Pengujian

```bash
# logika papan + tiga agen (100 game per agen)
godot --headless --path . --script res://tests/run_headless.gd

# smoke test UI: scene, klik, X-Ray, autoplay, benchmark, preset Expert
godot --headless --path . --script res://tests/run_ui_test.gd

# laporan benchmark lengkap
godot --headless --path . --script res://tests/bench_report.gd
```

Hasil yang diharapkan dari `run_headless.gd`: semua tes lulus, dan tidak ada
langkah "pasti" dari CSP yang justru mengenai ranjau.

## Contoh hasil benchmark

Diukur dengan `tests/bench_report.gd` pada Godot 4.7.2, seed 1..N, agen
menjalankan konfigurasi yang sama:

| Papan                         | Game | Rule-Based |   CSP | CSP + Utility |
| ----------------------------- | ---: | ---------: | ----: | ------------: |
| Beginner 9x9, 10 ranjau       |   50 |      88.0% | 94.0% |         94.0% |
| Intermediate 16x16, 40 ranjau |   20 |      50.0% | 75.0% |         75.0% |
| Expert 30x16, 99 ranjau       |    5 |       0.0% | 60.0% |         60.0% |

Angka di atas berasal dari satu run dan bukan klaim tetap. Pada run 100 game
Intermediate dengan seed berbeda, CSP dan CSP + Utility sama-sama menang 81%,
tetapi akurasi tebakan CSP + Utility sedikit lebih tinggi (72.6% vs 70.7%).
Utilitas mengubah pilihan sel pada sebagian keadaan, tetapi tidak selalu
mengubah hasil akhir permainan.

## Struktur folder

```
project.godot
scenes/main.tscn
scripts/
  core/minesweeper_board.gd      aturan permainan + snapshot agen
  core/benchmark_runner.gd       metrik komparasi
  agents/solver_agent.gd         kontrak agen
  agents/agent_move.gd           representasi aksi
  agents/rule_based_agent.gd     agen 1
  agents/csp_agent.gd            agen 2
  agents/csp_utility_agent.gd    agen 3
  agents/solver_manager.gd       pemuatan agen modular
  ui/cell_button.gd              kontrol per sel
  ui/main.gd                     UI, timer, X-Ray, benchmark
tests/
  run_headless.gd
  run_ui_test.gd
  bench_report.gd
```
