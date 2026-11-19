class_name MineCellButton
extends Button

## Tombol satu sel. Menangani tiga mekanisme kontrol proposal 3.1:
##   klik kiri        -> reveal
##   klik kanan       -> flag
##   kiri + kanan     -> chording (atau klik tengah)

signal reveal_requested(index: int)
signal flag_requested(index: int)
signal chord_requested(index: int)
signal cell_focused(index: int)

var index: int = -1

var _left_down := false
var _right_down := false
var _suppress_pressed := false


func _ready() -> void:
	pressed.connect(_on_pressed)
	focus_entered.connect(func() -> void: cell_focused.emit(index))


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return

	var mb := event as InputEventMouseButton

	if mb.button_index == MOUSE_BUTTON_LEFT:
		_left_down = mb.pressed
		if mb.pressed and _right_down:
			_suppress_pressed = true
			chord_requested.emit(index)
			accept_event()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_right_down = mb.pressed
		if mb.pressed:
			if _left_down:
				_suppress_pressed = true
				chord_requested.emit(index)
			else:
				flag_requested.emit(index)
			accept_event()
	elif mb.button_index == MOUSE_BUTTON_MIDDLE and mb.pressed:
		chord_requested.emit(index)
		accept_event()


func _on_pressed() -> void:
	# Setelah chord, jangan ikut membuka sel saat tombol kiri dilepas.
	if _suppress_pressed:
		_suppress_pressed = false
		return
	reveal_requested.emit(index)
