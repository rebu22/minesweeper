class_name CspUtilityAgent
extends CspAgent

## [UTILITY-BASED AGENT]
##
## Sama seperti CspAgent, tetapi pada langkah terakhir (ketika tidak ada lagi
## kepastian deduktif) agen menghitung utilitas: berapa banyak sel yang
## diperkirakan terbuka. Di antara langkah dengan risiko hampir sama, agen
## memilih yang utilitasnya paling tinggi (proposal 3.3.3).

func _init() -> void:
	super()
	display_name = "CSP + Utility (Information)"
	description = "CSP, lalu pilih risiko terkecil dengan utilitas informasi tertinggi"
	use_utility = true


func get_options_schema() -> Array:
	var schema := super.get_options_schema()
	schema.append({
		"key": "utility_margin",
		"label": "Toleransi risiko utilitas",
		"type": "float",
		"default": 0.02,
		"min": 0.0,
		"max": 0.20,
		"step": 0.01,
	})
	return schema


func configure(p_options: Dictionary) -> void:
	super.configure(p_options)
	utility_margin = clampf(float(p_options.get("utility_margin", utility_margin)), 0.0, 0.20)
