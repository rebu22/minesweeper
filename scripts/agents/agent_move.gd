class_name AgentMove
extends RefCounted

## Satu keputusan agen: buka sel, pasang bendera, atau berhenti.
##
## `is_guess` dipakai metrik "frekuensi dan akurasi tebakan" (proposal 3.4).
## `nodes` dipakai metrik "biaya algoritma" (node yang dieksplorasi).
## `probability` adalah estimasi risiko ranjau pada sel yang dipilih.

enum Action { NONE, REVEAL, FLAG }

var action: int = Action.NONE
var index: int = -1
var reason: String = ""
var is_guess: bool = false
var probability: float = 0.0
var nodes: int = 0
var expected_reveal: int = 0


static func none(reason_text: String = "Tidak ada langkah") -> AgentMove:
	var move := AgentMove.new()
	move.action = Action.NONE
	move.reason = reason_text
	return move


static func reveal(p_index: int, reason_text: String, guess: bool = false, risk: float = 0.0) -> AgentMove:
	var move := AgentMove.new()
	move.action = Action.REVEAL
	move.index = p_index
	move.reason = reason_text
	move.is_guess = guess
	move.probability = risk
	return move


static func flag(p_index: int, reason_text: String) -> AgentMove:
	var move := AgentMove.new()
	move.action = Action.FLAG
	move.index = p_index
	move.reason = reason_text
	return move
