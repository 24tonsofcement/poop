extends Node
# Dedicated analysis bus: only song audio drives these effects, never hit sounds.
const BANDS: int = 24
var levels: Array[Vector2] = []
var bass: float = 0.0
var bus_name: String = ""
var analyzer: AudioEffectSpectrumAnalyzerInstance

func _ready() -> void:
	levels.resize(BANDS)
	levels.fill(Vector2.ZERO)
	bus_name = "PulseSong_%d" % get_instance_id()
	var index: int = AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")
	var effect = AudioEffectSpectrumAnalyzer.new()
	effect.buffer_length = 0.15
	effect.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_1024
	effect.tap_back_pos = 0.01
	AudioServer.add_bus_effect(index, effect)
	analyzer = AudioServer.get_bus_effect_instance(index, 0) as AudioEffectSpectrumAnalyzerInstance

func amplitude(value: float) -> float:
	return clampf((linear_to_db(maxf(value, 0.000001)) + 65.0) / 55.0, 0.0, 1.0)

func sample(delta: float, active: bool) -> void:
	var bass_target: float = 0.0
	for i in range(BANDS):
		var target = Vector2.ZERO
		if active and analyzer != null:
			var low: float = 45.0 * pow(16000.0 / 45.0, float(i) / BANDS)
			var high: float = 45.0 * pow(16000.0 / 45.0, float(i + 1) / BANDS)
			var magnitude: Vector2 = analyzer.get_magnitude_for_frequency_range(low, high)
			target = Vector2(amplitude(magnitude.x), amplitude(magnitude.y))
		var old: Vector2 = levels[i]
		var attack: float = 1.0 - exp(-delta * 35.0)
		var release: float = 1.0 - exp(-delta * 9.0)
		levels[i] = Vector2(lerpf(old.x, target.x, attack if target.x > old.x else release), lerpf(old.y, target.y, attack if target.y > old.y else release))
		if i < 5:
			bass_target = maxf(bass_target, maxf(target.x, target.y))
	bass = lerpf(bass, bass_target, 1.0 - exp(-delta * (28.0 if bass_target > bass else 8.0)))

func _exit_tree() -> void:
	analyzer = null
	var index: int = AudioServer.get_bus_index(bus_name)
	if index > 0:
		AudioServer.remove_bus(index)
