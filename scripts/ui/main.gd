extends Control

## Antarmuka utama Minesweeper AI Lab.
##
## Pembagian peran:
##   - MinesweeperBoard : aturan permainan (scripts/core/minesweeper_board.gd)
##   - SolverManager    : memuat agen secara modular (scripts/agents/)
##   - CspAgent dkk.    : logika agen
##   - File ini         : UI, timer, X-Ray, Solver Control, metrik
##
## Penanda konsep di file ini:
##   [GOAL-BASED AGENT]   loop agen yang mengejar kondisi menang
##   [UTILITY-BASED AGENT] agen CSP + utilitas informasi
##   [X-RAY]              tampilan ranjau untuk pengamat, bukan untuk agen
##   [SOLVER MANAGER]     daftar agen dimuat tanpa kompilasi ulang
##   [SOLVER CONTROL]     opsi agen diatur dari UI
##   [METRICS]            rasio menang, tebakan, durasi, biaya node

const COL_BG := Color("e9e4da")
const COL_PANEL := Color("f7f3eb")
const COL_PANEL_ALT := Color("fbf8f2")
const COL_INK := Color("2b2722")
const COL_MUTED := Color("6f675c")
const COL_LINE := Color("cfc7b9")
const COL_ACCENT := Color("b0492f")
const COL_ACCENT_HOVER := Color("c25a3d")
const COL_ACCENT_PRESSED := Color("95402a")
const COL_TILE := Color("cbc3b5")
const COL_TILE_HOVER := Color("d7cfc2")
const COL_TILE_PRESSED := Color("bdb4a5")
const COL_OPEN := Color("ece7dd")
const COL_OPEN_LINE := Color("ded7ca")

const PRESETS := [
	{"name": "Beginner", "width": 9, "height": 9, "mines": 10},
	{"name": "Intermediate", "width": 16, "height": 16, "mines": 40},
	{"name": "Expert", "width": 30, "height": 16, "mines": 99},
	{"name": "Custom", "width": 9, "height": 9, "mines": 10},
]

var board: MinesweeperBoard
var cells: Array = []
var board_grid: GridContainer
var solver_manager := SolverManager.new()
var agents: Array = []
var active_agent_index: int = 0
var agent_settings: Dictionary = {}

var game_state: String = "ready"  # ready | playing | won | lost
var xray: bool = false
var autoplay: bool = false
var step_delay: float = 0.30
var end_recorded: bool = false
var _autoplay_stalls: int = 0

var elapsed_ms: int = 0
var timer_started_ms: int = 0
var timer_running: bool = false

var game_nodes: int = 0
var game_guesses: int = 0
var game_correct_guesses: int = 0
var game_moves: int = 0

var session_games: int = 0
var session_wins: int = 0
var session_guesses: int = 0
var session_correct_guesses: int = 0
var session_nodes: int = 0
var session_moves: int = 0

var _focused_index: int = -1
var _cell_size: int = 28
var _cell_font_size: int = 15
var _building_options: bool = false

# Node UI yang perlu diperbarui.
var mine_label: Label
var timer_label: Label
var status_label: Label
var reason_label: Label
var seed_used_label: Label
var metrics_label: Label
var solver_status_label: Label
var agent_desc_label: Label
var options_box: VBoxContainer
var agent_select: OptionButton
var difficulty_select: OptionButton
var width_edit: LineEdit
var height_edit: LineEdit
var mines_edit: LineEdit
var seed_edit: LineEdit
var benchmark_games_edit: LineEdit
var benchmark_output: RichTextLabel
var benchmark_button: Button
var autoplay_button: Button
var xray_button: Button
var step_button: Button
var speed_label: Label

var autoplay_timer: Timer

# Gaya yang dipakai ulang (dibuat sekali).
var _panel_style: StyleBoxFlat
var _stat_style: StyleBoxFlat
var _input_style: StyleBoxFlat
var _input_focus_style: StyleBoxFlat
var _btn_normal: StyleBoxFlat
var _btn_hover: StyleBoxFlat
var _btn_pressed: StyleBoxFlat
var _btn_disabled: StyleBoxFlat
var _primary_normal: StyleBoxFlat
var _primary_hover: StyleBoxFlat
var _primary_pressed: StyleBoxFlat
var _focus_style: StyleBoxFlat
var _cell_hidden: StyleBoxFlat
var _cell_hidden_hover: StyleBoxFlat
var _cell_hidden_pressed: StyleBoxFlat
var _cell_open: StyleBoxFlat
var _cell_mine: StyleBoxFlat
var _slider_track: StyleBoxFlat
var _slider_fill: StyleBoxFlat
var _slider_fill_highlight: StyleBoxFlat
var _grabber_icon: ImageTexture
var _grabber_icon_highlight: ImageTexture


func _ready() -> void:
	get_window().min_size = Vector2i(1220, 720)
	_build_styles()
	_install_theme()
	_build_ui()
	_discover_agents()
	_new_game()
	set_process(true)


func _process(_delta: float) -> void:
	if timer_label != null:
		timer_label.text = "%.1f" % _current_elapsed_s()


# ===========================================================================
# Tema dan gaya
# ===========================================================================
func _build_styles() -> void:
	_panel_style = _flat(COL_PANEL, COL_LINE, 1, 9, 14)
	_stat_style = _flat(COL_PANEL_ALT, COL_LINE, 1, 7, 10)
	_input_style = _flat(COL_PANEL_ALT, COL_LINE, 1, 5, 7)
	_input_focus_style = _flat(COL_PANEL_ALT, COL_ACCENT, 2, 5, 6)

	_btn_normal = _flat(Color("f1ece3"), COL_LINE, 1, 5, 8)
	_btn_hover = _flat(Color("e7e0d4"), Color("b9b0a2"), 1, 5, 8)
	_btn_pressed = _flat(Color("ddd4c6"), COL_LINE, 1, 5, 8)
	_btn_disabled = _flat(Color("e9e4da"), Color("ddd6c9"), 1, 5, 8)

	_primary_normal = _flat(COL_ACCENT, COL_ACCENT, 1, 5, 8)
	_primary_hover = _flat(COL_ACCENT_HOVER, COL_ACCENT_HOVER, 1, 5, 8)
	_primary_pressed = _flat(COL_ACCENT_PRESSED, COL_ACCENT_PRESSED, 1, 5, 8)

	_focus_style = _flat(Color(0, 0, 0, 0), COL_ACCENT, 2, 5, 0)

	_cell_hidden = _flat(COL_TILE, Color("b6ad9e"), 1, 3, 0)
	_cell_hidden.shadow_color = Color(0, 0, 0, 0.10)
	_cell_hidden.shadow_size = 1
	_cell_hidden.shadow_offset = Vector2(1, 1)
	_cell_hidden_hover = _flat(COL_TILE_HOVER, Color("aca294"), 1, 3, 0)
	_cell_hidden_pressed = _flat(COL_TILE_PRESSED, Color("a59b8c"), 1, 3, 0)
	_cell_open = _flat(COL_OPEN, COL_OPEN_LINE, 1, 3, 0)
	_cell_mine = _flat(COL_ACCENT, COL_ACCENT, 1, 3, 0)

	_slider_track = _slider_style(Color("d9d1c4"))
	_slider_fill = _slider_style(COL_ACCENT)
	_slider_fill_highlight = _slider_style(COL_ACCENT_HOVER)
	_grabber_icon = _circle_icon(14, COL_ACCENT, Color("fdf9f3"))
	_grabber_icon_highlight = _circle_icon(14, COL_ACCENT_HOVER, Color("fdf9f3"))


func _slider_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(4)
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s


func _circle_icon(size: int, fill: Color, border: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := (float(size) - 1.0) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(float(x) - center, float(y) - center).length()
			if d <= 5.2:
				img.set_pixel(x, y, fill)
			elif d <= 6.4:
				img.set_pixel(x, y, border)
	return ImageTexture.create_from_image(img)


func _install_theme() -> void:
	var t := Theme.new()
	t.default_font_size = 14
	t.set_color("font_color", "Label", COL_INK)
	t.set_color("font_color", "Button", COL_INK)
	t.set_color("font_color", "OptionButton", COL_INK)
	t.set_color("font_color", "LineEdit", COL_INK)
	t.set_color("font_color", "RichTextLabel", COL_INK)
	t.set_color("default_color", "RichTextLabel", COL_INK)
	t.set_color("font_color", "PopupMenu", COL_INK)
	self.theme = t


func _flat(bg: Color, border: Color, border_width: int, radius: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin
	s.content_margin_bottom = margin
	return s


# ===========================================================================
# Membangun UI
# ===========================================================================
func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	margin.add_child(columns)

	# ---------------------------------------------------------------
	# Kolom kiri: judul, papan, status
	# ---------------------------------------------------------------
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	columns.add_child(left)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	left.add_child(header)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 0)
	header.add_child(title_box)

	var title := Label.new()
	title.text = "Minesweeper"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", COL_INK)
	title_box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "AI Solver Lab / Kelompok 2"
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", COL_MUTED)
	title_box.add_child(subtitle)

	var mines_stat := _create_stat("MINES LEFT")
	mine_label = mines_stat["value"]
	header.add_child(mines_stat["panel"])

	var time_stat := _create_stat("TIME (S)")
	timer_label = time_stat["value"]
	header.add_child(time_stat["panel"])

	var new_game_header := _button("New game", true)
	new_game_header.pressed.connect(_new_game)
	header.add_child(new_game_header)

	var board_frame := PanelContainer.new()
	board_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_frame.add_theme_stylebox_override("panel", _panel_style)
	left.add_child(board_frame)

	var board_margin := MarginContainer.new()
	board_margin.add_theme_constant_override("margin_left", 14)
	board_margin.add_theme_constant_override("margin_right", 14)
	board_margin.add_theme_constant_override("margin_top", 14)
	board_margin.add_theme_constant_override("margin_bottom", 14)
	board_frame.add_child(board_margin)

	var center := CenterContainer.new()
	board_margin.add_child(center)

	board_grid = GridContainer.new()
	board_grid.add_theme_constant_override("h_separation", 2)
	board_grid.add_theme_constant_override("v_separation", 2)
	center.add_child(board_grid)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	left.add_child(footer)

	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", COL_MUTED)
	footer.add_child(status_label)

	var hint := Label.new()
	hint.text = "Kiri: buka / Kanan: bendera / Kiri+Kanan: chord / F, X, A, R"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", COL_MUTED)
	footer.add_child(hint)

	# ---------------------------------------------------------------
	# Sidebar kanan
	# ---------------------------------------------------------------
	var sidebar := PanelContainer.new()
	sidebar.custom_minimum_size = Vector2(348, 0)
	sidebar.size_flags_horizontal = Control.SIZE_FILL
	sidebar.add_theme_stylebox_override("panel", _panel_style)
	columns.add_child(sidebar)

	var sidebar_margin := MarginContainer.new()
	sidebar_margin.add_theme_constant_override("margin_left", 14)
	sidebar_margin.add_theme_constant_override("margin_right", 14)
	sidebar_margin.add_theme_constant_override("margin_top", 12)
	sidebar_margin.add_theme_constant_override("margin_bottom", 12)
	sidebar.add_child(sidebar_margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar_margin.add_child(scroll)

	var _scrollbar := scroll.get_v_scroll_bar()
	_scrollbar.add_theme_stylebox_override("scroll", _flat(Color("e4ded2"), Color(0, 0, 0, 0), 0, 4, 2))
	_scrollbar.add_theme_stylebox_override("grabber", _flat(Color("b7ad9d"), Color(0, 0, 0, 0), 0, 4, 2))
	_scrollbar.add_theme_stylebox_override("grabber_highlight", _flat(Color("a79d8c"), Color(0, 0, 0, 0), 0, 4, 2))

	var sidebar_box := VBoxContainer.new()
	sidebar_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar_box.custom_minimum_size = Vector2(300, 0)
	sidebar_box.add_theme_constant_override("separation", 16)
	scroll.add_child(sidebar_box)

	_build_game_section(sidebar_box)
	_build_solver_section(sidebar_box)
	_build_analysis_section(sidebar_box)

	autoplay_timer = Timer.new()
	autoplay_timer.one_shot = false
	autoplay_timer.timeout.connect(_on_autoplay_tick)
	add_child(autoplay_timer)


func _build_game_section(parent: VBoxContainer) -> void:
	var section := _section("Game")
	parent.add_child(section)

	var form := GridContainer.new()
	form.columns = 2
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("h_separation", 10)
	form.add_theme_constant_override("v_separation", 8)
	section.add_child(form)

	difficulty_select = _option()
	for preset in PRESETS:
		difficulty_select.add_item(preset["name"])
	difficulty_select.select(0)
	difficulty_select.item_selected.connect(_on_difficulty_changed)
	_form_row(form, "Preset", difficulty_select)

	width_edit = _line_edit("9")
	height_edit = _line_edit("9")
	mines_edit = _line_edit("10")
	seed_edit = _line_edit("", "random")

	_form_row(form, "Width", width_edit)
	_form_row(form, "Height", height_edit)
	_form_row(form, "Mines", mines_edit)
	_form_row(form, "Seed", seed_edit)

	seed_used_label = Label.new()
	seed_used_label.text = "Seed: menunggu klik pertama"
	seed_used_label.add_theme_font_size_override("font_size", 11)
	seed_used_label.add_theme_color_override("font_color", COL_MUTED)
	section.add_child(seed_used_label)

	var new_game := _button("New game", true)
	new_game.pressed.connect(_new_game)
	section.add_child(new_game)


func _build_solver_section(parent: VBoxContainer) -> void:
	var section := _section("Solver")
	parent.add_child(section)

	agent_select = _option()
	agent_select.item_selected.connect(_on_agent_selected)
	section.add_child(agent_select)

	agent_desc_label = Label.new()
	agent_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	agent_desc_label.add_theme_font_size_override("font_size", 11)
	agent_desc_label.add_theme_color_override("font_color", COL_MUTED)
	section.add_child(agent_desc_label)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	section.add_child(controls)

	autoplay_button = _button("Play", true)
	autoplay_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	autoplay_button.pressed.connect(_toggle_autoplay)
	controls.add_child(autoplay_button)

	step_button = _button("Step", false)
	step_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	step_button.pressed.connect(_on_step_pressed)
	controls.add_child(step_button)

	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 6)
	section.add_child(speed_row)

	speed_label = Label.new()
	speed_label.text = "Speed"
	speed_label.add_theme_font_size_override("font_size", 11)
	speed_label.add_theme_color_override("font_color", COL_MUTED)
	speed_label.custom_minimum_size = Vector2(48, 0)
	speed_row.add_child(speed_label)

	var speed_group := ButtonGroup.new()
	_speed_button(speed_row, "Slow", 0.60, speed_group, false)
	_speed_button(speed_row, "Normal", 0.30, speed_group, true)
	_speed_button(speed_row, "Fast", 0.10, speed_group, false)

	reason_label = Label.new()
	reason_label.text = "Menunggu langkah pertama."
	reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason_label.custom_minimum_size = Vector2(0, 46)
	reason_label.add_theme_font_size_override("font_size", 11)
	reason_label.add_theme_color_override("font_color", COL_MUTED)
	section.add_child(reason_label)

	# ---------------------------------------------------------------
	# [SOLVER CONTROL] Opsi agen dibuat otomatis dari get_options_schema().
	# ---------------------------------------------------------------
	var control_title := Label.new()
	control_title.text = "Solver control"
	control_title.add_theme_font_size_override("font_size", 11)
	control_title.add_theme_color_override("font_color", COL_MUTED)
	section.add_child(control_title)

	options_box = VBoxContainer.new()
	options_box.add_theme_constant_override("separation", 8)
	section.add_child(options_box)

	var rescan_row := HBoxContainer.new()
	rescan_row.add_theme_constant_override("separation", 8)
	section.add_child(rescan_row)

	solver_status_label = Label.new()
	solver_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	solver_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	solver_status_label.add_theme_font_size_override("font_size", 11)
	solver_status_label.add_theme_color_override("font_color", COL_MUTED)
	rescan_row.add_child(solver_status_label)

	var rescan := _button("Rescan", false)
	rescan.custom_minimum_size = Vector2(82, 30)
	rescan.pressed.connect(_discover_agents)
	rescan_row.add_child(rescan)


func _build_analysis_section(parent: VBoxContainer) -> void:
	var section := _section("Analysis")
	parent.add_child(section)

	# ---------------------------------------------------------------
	# [X-RAY] Tombol ini hanya mengubah tampilan pengamat.
	# ---------------------------------------------------------------
	xray_button = _button("X-Ray: OFF", false)
	xray_button.toggle_mode = true
	xray_button.toggled.connect(_on_xray_toggled)
	section.add_child(xray_button)

	var bench_row := HBoxContainer.new()
	bench_row.add_theme_constant_override("separation", 8)
	section.add_child(bench_row)

	var bench_label := Label.new()
	bench_label.text = "Games"
	bench_label.add_theme_font_size_override("font_size", 11)
	bench_label.add_theme_color_override("font_color", COL_MUTED)
	bench_label.custom_minimum_size = Vector2(48, 0)
	bench_row.add_child(bench_label)

	benchmark_games_edit = _line_edit("30")
	benchmark_games_edit.custom_minimum_size = Vector2(64, 30)
	bench_row.add_child(benchmark_games_edit)

	benchmark_button = _button("Run benchmark", false)
	benchmark_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	benchmark_button.pressed.connect(_on_benchmark_pressed)
	bench_row.add_child(benchmark_button)

	benchmark_output = RichTextLabel.new()
	benchmark_output.bbcode_enabled = true
	benchmark_output.fit_content = true
	benchmark_output.scroll_active = false
	benchmark_output.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	benchmark_output.custom_minimum_size = Vector2(0, 200)
	benchmark_output.add_theme_stylebox_override("normal", _flat(COL_PANEL_ALT, COL_LINE, 1, 6, 10))
	benchmark_output.add_theme_font_size_override("normal_font_size", 11)
	benchmark_output.add_theme_color_override("default_color", COL_INK)
	benchmark_output.text = "Belum ada benchmark. Tekan Run benchmark untuk membandingkan semua agen."
	section.add_child(benchmark_output)

	# ---------------------------------------------------------------
	# [METRICS] Ringkasan sesi dan permainan saat ini.
	# ---------------------------------------------------------------
	metrics_label = Label.new()
	metrics_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	metrics_label.add_theme_font_size_override("font_size", 11)
	metrics_label.add_theme_color_override("font_color", COL_MUTED)
	section.add_child(metrics_label)


func _section(title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", COL_MUTED)
	box.add_child(label)

	var line := HSeparator.new()
	var line_style := StyleBoxLine.new()
	line_style.color = COL_LINE
	line_style.thickness = 1
	line.add_theme_stylebox_override("separator", line_style)
	box.add_child(line)
	return box


func _create_stat(title: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(96, 0)
	panel.add_theme_stylebox_override("panel", _stat_style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)

	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 9)
	title_label.add_theme_color_override("font_color", COL_MUTED)
	box.add_child(title_label)

	var value_label := Label.new()
	value_label.text = "0"
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 20)
	value_label.add_theme_color_override("font_color", COL_INK)
	box.add_child(value_label)

	return {"panel": panel, "value": value_label}


func _form_row(form: GridContainer, text: String, control: Control) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", COL_MUTED)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	form.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(control)


func _button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 34)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_stylebox_override("focus", _focus_style)

	if primary:
		button.add_theme_stylebox_override("normal", _primary_normal)
		button.add_theme_stylebox_override("hover", _primary_hover)
		button.add_theme_stylebox_override("pressed", _primary_pressed)
		button.add_theme_stylebox_override("disabled", _btn_disabled)
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(key, Color("fdf9f3"))
	else:
		button.add_theme_stylebox_override("normal", _btn_normal)
		button.add_theme_stylebox_override("hover", _btn_hover)
		button.add_theme_stylebox_override("pressed", _btn_pressed)
		button.add_theme_stylebox_override("disabled", _btn_disabled)
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(key, COL_INK)

	return button


func _option() -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(0, 32)
	option.add_theme_font_size_override("font_size", 12)
	option.add_theme_stylebox_override("normal", _btn_normal)
	option.add_theme_stylebox_override("hover", _btn_hover)
	option.add_theme_stylebox_override("pressed", _btn_pressed)
	option.add_theme_stylebox_override("focus", _focus_style)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		option.add_theme_color_override(key, COL_INK)
	for key in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		option.add_theme_color_override(key, COL_INK)

	var popup := option.get_popup()
	popup.add_theme_stylebox_override("panel", _flat(COL_PANEL, COL_LINE, 1, 6, 4))
	popup.add_theme_stylebox_override("hover", _flat(COL_ACCENT, COL_ACCENT, 0, 4, 4))
	popup.add_theme_color_override("font_color", COL_INK)
	popup.add_theme_color_override("font_hover_color", Color("fdf9f3"))
	popup.add_theme_font_size_override("font_size", 12)
	return option


func _line_edit(text: String, placeholder: String = "") -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(0, 30)
	edit.add_theme_stylebox_override("normal", _input_style)
	edit.add_theme_stylebox_override("focus", _input_focus_style)
	edit.add_theme_color_override("font_color", COL_INK)
	edit.add_theme_color_override("font_placeholder_color", COL_MUTED)
	edit.add_theme_color_override("caret_color", COL_ACCENT)
	edit.add_theme_color_override("selection_color", Color(0.69, 0.29, 0.18, 0.22))
	edit.add_theme_font_size_override("font_size", 12)
	return edit


func _speed_button(
	row: HBoxContainer,
	text: String,
	value: float,
	group: ButtonGroup,
	pressed_by_default: bool
) -> void:
	var button := _button(text, false)
	button.toggle_mode = true
	button.button_group = group
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 28)
	button.button_pressed = pressed_by_default
	button.add_theme_font_size_override("font_size", 11)
	button.pressed.connect(func() -> void:
		step_delay = value
		if autoplay_timer != null and autoplay:
			autoplay_timer.wait_time = step_delay
	)
	row.add_child(button)


# ===========================================================================
# [SOLVER MANAGER] Memuat agen dari folder tanpa kompilasi ulang.
# ===========================================================================
func _discover_agents() -> void:
	var previous_id := ""
	if active_agent_index >= 0 and active_agent_index < agents.size():
		previous_id = agents[active_agent_index]["id"]

	agents = solver_manager.discover()
	agent_select.clear()

	if agents.is_empty():
		agent_select.add_item("Tidak ada agen")
		agent_select.disabled = true
		solver_status_label.text = "Tidak ada file agen ditemukan."
		return

	agent_select.disabled = false
	for entry in agents:
		agent_select.add_item(entry["agent"].display_name)

	var target := 0
	if previous_id != "":
		for i in agents.size():
			if agents[i]["id"] == previous_id:
				target = i
				break
	active_agent_index = target
	agent_select.select(target)
	_on_agent_selected(target)

	solver_status_label.text = "%d agen dimuat dari scripts/agents/. Tambah file .gd lalu Rescan." % agents.size()


func _on_agent_selected(index: int) -> void:
	if index < 0 or index >= agents.size():
		return
	active_agent_index = index
	var entry: Dictionary = agents[index]
	agent_desc_label.text = entry["agent"].description
	_build_agent_options(entry)


# ===========================================================================
# [SOLVER CONTROL] Kontrol opsi dibuat dari skema agen.
# ===========================================================================
func _build_agent_options(entry: Dictionary) -> void:
	_building_options = true
	for child in options_box.get_children():
		options_box.remove_child(child)
		child.queue_free()

	var agent: SolverAgent = entry["agent"]
	var schema: Array = agent.get_options_schema()
	var agent_id: String = entry["id"]

	var settings: Dictionary = {}
	for spec in schema:
		settings[spec["key"]] = spec["default"]
	var stored: Dictionary = agent_settings.get(agent_id, {})
	for key in stored.keys():
		if settings.has(key):
			settings[key] = stored[key]
	agent_settings[agent_id] = settings.duplicate(true)
	agent.configure(settings)

	if schema.is_empty():
		var empty := Label.new()
		empty.text = "Agen ini tidak punya parameter."
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", COL_MUTED)
		options_box.add_child(empty)
		_building_options = false
		return

	for spec in schema:
		_add_option_control(agent_id, spec, settings[spec["key"]])

	_building_options = false


func _add_option_control(agent_id: String, spec: Dictionary, value: Variant) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 3)

	var head := HBoxContainer.new()
	var label := Label.new()
	label.text = spec["label"]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", COL_MUTED)
	head.add_child(label)

	var value_label := Label.new()
	value_label.add_theme_font_size_override("font_size", 11)
	value_label.add_theme_color_override("font_color", COL_INK)
	head.add_child(value_label)
	row.add_child(head)

	if spec["type"] == "bool":
		var toggle := _button("On" if bool(value) else "Off", false)
		toggle.toggle_mode = true
		toggle.button_pressed = bool(value)
		toggle.custom_minimum_size = Vector2(0, 28)
		toggle.toggled.connect(func(on: bool) -> void:
			toggle.text = "On" if on else "Off"
			_on_option_changed(agent_id, spec["key"], on)
		)
		row.add_child(toggle)
	else:
		var slider := HSlider.new()
		slider.min_value = float(spec.get("min", 0))
		slider.max_value = float(spec.get("max", 100))
		slider.step = float(spec.get("step", 1))
		slider.value = float(value)
		slider.custom_minimum_size = Vector2(0, 20)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.add_theme_stylebox_override("slider", _slider_track)
		slider.add_theme_stylebox_override("grabber_area", _slider_fill)
		slider.add_theme_stylebox_override("grabber_area_highlight", _slider_fill_highlight)
		slider.add_theme_icon_override("grabber", _grabber_icon)
		slider.add_theme_icon_override("grabber_highlight", _grabber_icon_highlight)
		slider.add_theme_stylebox_override("focus", _focus_style)

		var is_int: bool = spec["type"] == "int"
		value_label.text = _format_option(slider.value, is_int)
		slider.value_changed.connect(func(v: float) -> void:
			value_label.text = _format_option(v, is_int)
			_on_option_changed(agent_id, spec["key"], int(v) if is_int else v)
		)
		row.add_child(slider)

	options_box.add_child(row)


func _format_option(value: float, is_int: bool) -> String:
	if is_int:
		return str(int(value))
	return "%.2f" % value


func _on_option_changed(agent_id: String, key: String, value: Variant) -> void:
	if _building_options:
		return

	var settings: Dictionary = agent_settings.get(agent_id, {})
	settings[key] = value
	agent_settings[agent_id] = settings

	for entry in agents:
		if entry["id"] == agent_id:
			entry["agent"].configure(settings)
			break


# ===========================================================================
# Permainan baru dan konfigurasi
# ===========================================================================
func _new_game() -> void:
	_stop_autoplay()

	var config := _current_config()
	width_edit.text = str(config["width"])
	height_edit.text = str(config["height"])
	mines_edit.text = str(config["mines"])

	board = MinesweeperBoard.new()
	board.setup(config["width"], config["height"], config["mines"], config["seed"])

	game_state = "ready"
	xray = false
	if xray_button != null:
		xray_button.button_pressed = false
		xray_button.text = "X-Ray: OFF"
	end_recorded = false
	elapsed_ms = 0
	timer_running = false
	game_nodes = 0
	game_guesses = 0
	game_correct_guesses = 0
	game_moves = 0
	_autoplay_stalls = 0

	_build_grid()
	_update_counters()
	_update_metrics()
	seed_used_label.text = "Seed: menunggu klik pertama"
	reason_label.text = "Menunggu langkah pertama."
	status_label.text = "Klik sel mana pun untuk mulai. Papan dibuat setelah klik pertama, jadi sel pertama selalu aman."
	if timer_label != null:
		timer_label.text = "0.0"


func _current_config() -> Dictionary:
	var width := clampi(_parse_int(width_edit.text, 9), 5, 40)
	var height := clampi(_parse_int(height_edit.text, 9), 5, 30)
	var max_mines := maxi(1, width * height - 9)
	var mines := clampi(_parse_int(mines_edit.text, 10), 1, max_mines)
	var seed := _parse_int(seed_edit.text, 0)
	if seed < 0:
		seed = 0
	return {"width": width, "height": height, "mines": mines, "seed": seed}


func _parse_int(text: String, fallback: int) -> int:
	var clean := text.strip_edges()
	if clean == "" or not clean.is_valid_int():
		return fallback
	return int(clean)


func _on_difficulty_changed(index: int) -> void:
	if index < 0 or index >= PRESETS.size():
		return
	var preset: Dictionary = PRESETS[index]
	width_edit.text = str(preset["width"])
	height_edit.text = str(preset["height"])
	mines_edit.text = str(preset["mines"])
	var custom := index == PRESETS.size() - 1
	width_edit.editable = custom
	height_edit.editable = custom
	mines_edit.editable = custom


# ===========================================================================
# Papan dan tampilan sel
# ===========================================================================
func _build_grid() -> void:
	for child in board_grid.get_children():
		board_grid.remove_child(child)
		child.queue_free()
	cells.clear()

	board_grid.columns = board.width
	var size_by_width := 730.0 / float(board.width)
	var size_by_height := 540.0 / float(board.height)
	_cell_size = int(clampf(minf(size_by_width, size_by_height), 18.0, 36.0))
	_cell_font_size = int(clampf(float(_cell_size) * 0.52, 11.0, 19.0))

	for i in board.width * board.height:
		var cell := MineCellButton.new()
		cell.index = i
		cell.custom_minimum_size = Vector2(_cell_size, _cell_size)
		cell.focus_mode = Control.FOCUS_ALL
		cell.add_theme_font_size_override("font_size", _cell_font_size)
		cell.tooltip_text = "Kiri: buka / Kanan: bendera / Kiri+Kanan: chord"
		cell.reveal_requested.connect(_on_cell_reveal)
		cell.flag_requested.connect(_on_cell_flag)
		cell.chord_requested.connect(_on_cell_chord)
		cell.cell_focused.connect(_on_cell_focused)
		board_grid.add_child(cell)
		cells.append(cell)

	_refresh_cells()


func _refresh_cells() -> void:
	if board == null:
		return
	for i in cells.size():
		_update_cell(i)


func _update_cell(index: int) -> void:
	var cell: MineCellButton = cells[index]
	var is_revealed := board.revealed[index] == 1
	var is_flag := board.flagged[index] == 1
	var is_mine := board.mine[index] == 1

	var text := ""
	var color := COL_INK
	var normal := _cell_hidden
	var hover := _cell_hidden_hover
	var pressed := _cell_hidden_pressed

	if is_revealed:
		normal = _cell_open
		hover = _cell_open
		pressed = _cell_open
		if is_mine:
			normal = _cell_mine
			hover = _cell_mine
			pressed = _cell_mine
			text = "*"
			color = Color("fdf9f3")
		elif board.adjacent[index] > 0:
			text = str(board.adjacent[index])
			color = _number_color(board.adjacent[index])
	elif is_flag:
		if board.ended and not board.won and not is_mine:
			text = "X"
		else:
			text = "F"
		color = COL_ACCENT
	elif board.ended and not board.won and is_mine:
		text = "*"
		color = COL_ACCENT
	elif board.won and is_mine:
		text = "F"
		color = COL_ACCENT
	elif xray and board.generated and is_mine:
		# [X-RAY] Pengamat melihat ranjau; nilai ini tidak pernah masuk
		# ke agent_snapshot(), jadi agen tetap buta.
		text = "*"
		color = Color(0.69, 0.29, 0.18, 0.45)

	cell.add_theme_stylebox_override("normal", normal)
	cell.add_theme_stylebox_override("hover", hover)
	cell.add_theme_stylebox_override("pressed", pressed)
	cell.add_theme_stylebox_override("focus", _focus_style)

	if cell.text != text:
		cell.text = text
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		cell.add_theme_color_override(key, color)

	cell.mouse_default_cursor_shape = (
		Control.CURSOR_ARROW if is_revealed else Control.CURSOR_POINTING_HAND
	)


func _number_color(value: int) -> Color:
	match value:
		1:
			return Color("2f5f9e")
		2:
			return Color("3a7a3f")
		3:
			return Color("b0492f")
		4:
			return Color("4a3f86")
		5:
			return Color("8a3b2a")
		6:
			return Color("2c7878")
		7:
			return Color("2b2722")
		8:
			return Color("6f675c")
		_:
			return COL_INK


# ===========================================================================
# Aksi pemain
# ===========================================================================
func _on_cell_reveal(index: int) -> void:
	if board == null or board.ended:
		return
	if board.revealed[index] == 1 or board.flagged[index] == 1:
		return

	_stop_autoplay()
	if game_state == "ready":
		game_state = "playing"
		_start_timer()

	board.reveal(index)
	_after_action("Kamu membuka (%d,%d)." % [index % board.width, index / board.width])


func _on_cell_flag(index: int) -> void:
	if board == null or board.ended:
		return
	_stop_autoplay()
	board.toggle_flag(index)
	_after_action("Bendera diperbarui.")


func _on_cell_chord(index: int) -> void:
	if board == null or board.ended:
		return
	_stop_autoplay()
	if board.chord(index):
		_after_action("Chording di (%d,%d)." % [index % board.width, index / board.width])


func _on_cell_focused(index: int) -> void:
	_focused_index = index


func _after_action(reason: String) -> void:
	if board.generated:
		seed_used_label.text = "Seed: %d" % board.used_seed
	reason_label.text = reason
	_refresh_cells()
	_update_counters()
	_update_metrics()

	if board.ended:
		_finish_game()
	else:
		_update_status()


# ===========================================================================
# [GOAL-BASED AGENT] Autoplay: agen memilih aksi, game mengeksekusi, lalu
# mengevaluasi apakah tujuan (semua sel aman terbuka) sudah tercapai.
# ===========================================================================
func _toggle_autoplay() -> void:
	if autoplay:
		_stop_autoplay()
	else:
		_start_autoplay()


func _start_autoplay() -> void:
	if agents.is_empty():
		return
	if game_state == "won" or game_state == "lost":
		_new_game()

	autoplay = true
	_autoplay_stalls = 0
	autoplay_button.text = "Pause"
	autoplay_timer.wait_time = step_delay
	autoplay_timer.start()
	_on_autoplay_tick()


func _stop_autoplay() -> void:
	autoplay = false
	if autoplay_timer != null:
		autoplay_timer.stop()
	if autoplay_button != null:
		autoplay_button.text = "Play"


func _on_autoplay_tick() -> void:
	if not autoplay or board == null or board.ended:
		_stop_autoplay()
		return

	# [GOAL-BASED AGENT] Persepsi -> pilih aksi -> eksekusi -> evaluasi goal.
	var progressed := _perform_agent_step()
	if progressed:
		_autoplay_stalls = 0
	else:
		_autoplay_stalls += 1
		if _autoplay_stalls >= 3:
			_stop_autoplay()
			reason_label.text = "Autoplay dihentikan: agen tidak membuat kemajuan."


func _on_step_pressed() -> void:
	_stop_autoplay()
	if agents.is_empty():
		return
	if game_state == "won" or game_state == "lost":
		_new_game()
	_perform_agent_step()


func _perform_agent_step() -> bool:
	if agents.is_empty() or board == null or board.ended:
		return false

	var entry: Dictionary = agents[active_agent_index]
	var agent: SolverAgent = entry["agent"]

	var move := agent.next_move(board.agent_snapshot())
	if move == null or move.action == AgentMove.Action.NONE:
		_stop_autoplay()
		reason_label.text = "Agen berhenti: " + (move.reason if move != null else "tidak ada langkah")
		return false

	if move.is_guess and move.action == AgentMove.Action.REVEAL:
		game_guesses += 1
		if board.mine[move.index] == 0:
			game_correct_guesses += 1

	game_nodes += move.nodes
	game_moves += 1

	if game_state == "ready" and move.action == AgentMove.Action.REVEAL:
		game_state = "playing"
		_start_timer()

	var result := board.apply_agent_move(move)
	if board.generated:
		seed_used_label.text = "Seed: %d" % board.used_seed

	reason_label.text = move.reason
	_refresh_cells()
	_update_counters()
	_update_metrics()

	if board.ended:
		_finish_game()
	else:
		_update_status()

	return bool(result.get("applied", false))


# ===========================================================================
# Status, timer, metrik
# ===========================================================================
func _start_timer() -> void:
	if not timer_running:
		timer_started_ms = Time.get_ticks_msec()
		timer_running = true


func _stop_timer() -> void:
	if timer_running:
		elapsed_ms += Time.get_ticks_msec() - timer_started_ms
		timer_running = false


func _current_elapsed_s() -> float:
	var total := elapsed_ms
	if timer_running:
		total += Time.get_ticks_msec() - timer_started_ms
	return float(total) / 1000.0


func _update_counters() -> void:
	if board == null:
		return
	mine_label.text = str(board.remaining_mines())


func _update_status() -> void:
	if board == null:
		return
	if game_state == "ready":
		status_label.text = "Klik sel mana pun untuk mulai. Papan dibuat setelah klik pertama, jadi sel pertama selalu aman."
	elif game_state == "playing":
		status_label.text = (
			"Bendera %d dari %d ranjau. Sel aman terbuka: %d / %d."
			% [
				board.flags_used,
				board.mine_total,
				board.revealed_safe,
				board.width * board.height - board.mine_total,
			]
		)
	elif game_state == "won":
		status_label.text = (
			"Bersih! Semua sel aman terbuka dalam %.1f detik, %d node, %d tebakan."
			% [_current_elapsed_s(), game_nodes, game_guesses]
		)
	else:
		status_label.text = (
			"Ranjau meledak di (%d,%d). Waktu %.1f detik. Tekan New game untuk mencoba lagi."
			% [
				board.exploded_index % board.width,
				board.exploded_index / board.width,
				_current_elapsed_s(),
			]
		)


func _finish_game() -> void:
	if end_recorded:
		return
	end_recorded = true

	_stop_timer()
	_stop_autoplay()
	game_state = "won" if board.won else "lost"

	session_games += 1
	if board.won:
		session_wins += 1
	session_guesses += game_guesses
	session_correct_guesses += game_correct_guesses
	session_nodes += game_nodes
	session_moves += game_moves

	_update_status()
	_update_metrics()


func _update_metrics() -> void:
	if metrics_label == null:
		return
	var session_accuracy := 0.0
	if session_guesses > 0:
		session_accuracy = float(session_correct_guesses) / float(session_guesses) * 100.0

	metrics_label.text = (
		"Game ini: %d langkah, %d node, %d tebakan.\n"
		+ "Sesi: %d game, %d menang, akurasi tebakan %.0f%%."
	) % [
		game_moves,
		game_nodes,
		game_guesses,
		session_games,
		session_wins,
		session_accuracy,
	]


# ===========================================================================
# [X-RAY] Hanya tampilan. Agen tetap memakai agent_snapshot().
# ===========================================================================
func _on_xray_toggled(pressed: bool) -> void:
	xray = pressed
	xray_button.text = "X-Ray: ON" if pressed else "X-Ray: OFF"
	_refresh_cells()


# ===========================================================================
# [METRICS] Benchmark semua agen pada konfigurasi dan seed yang sama.
# ===========================================================================
func _on_benchmark_pressed() -> void:
	if agents.is_empty():
		return

	_stop_autoplay()
	var games := clampi(_parse_int(benchmark_games_edit.text, 30), 5, 200)
	benchmark_games_edit.text = str(games)
	var config := _current_config()

	benchmark_button.disabled = true
	benchmark_output.text = "[color=#6f675c]Menjalankan %d game per agen...[/color]" % games
	await get_tree().process_frame

	var results := BenchmarkRunner.run_comparison(agents, config, games, 1)
	_render_benchmark(results, config, games)
	benchmark_button.disabled = false


func _render_benchmark(results: Array, config: Dictionary, games: int) -> void:
	var text := "[b]Benchmark %d game[/b]  [color=#6f675c]%dx%d, %d ranjau, seed 1..%d[/color]\n\n" % [
		games,
		config["width"],
		config["height"],
		config["mines"],
		games,
	]

	for result in results:
		text += "[b]%s[/b]\n" % result["agent"]
		text += "  Menang: %.0f%% (%d/%d)\n" % [
			result["win_rate"], result["wins"], result["games"]
		]
		text += "  Tebakan: %d (%.0f%% langkah), akurasi %.0f%%\n" % [
			result["guesses"], result["guess_frequency"], result["guess_accuracy"]
		]
		text += "  Waktu: %.1f ms/game (%d ms total)\n" % [
			result["avg_time_ms"], result["time_ms"]
		]
		text += "  Node: %d (%.1f per langkah)\n\n" % [
			result["nodes"], result["nodes_per_move"]
		]

	benchmark_output.text = text


# ===========================================================================
# Keyboard
# ===========================================================================
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return

	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner is LineEdit:
		return

	match key.keycode:
		KEY_F:
			if _focused_index >= 0:
				_on_cell_flag(_focused_index)
		KEY_X:
			_on_xray_toggled(not xray)
			xray_button.button_pressed = xray
		KEY_A:
			_toggle_autoplay()
		KEY_R:
			_new_game()
		KEY_ESCAPE:
			_stop_autoplay()
