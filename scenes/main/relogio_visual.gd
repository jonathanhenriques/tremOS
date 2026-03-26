extends TextureProgressBar

@export var tempo_total: float = 10.0 # segundos para completar o círculo

var tempo_atual: float = 0.0

func _process(delta):
	tempo_atual += delta
	
	# Loop infinito (tipo relógio)
	if tempo_atual >= tempo_total:
		tempo_atual = 0
	
	value = (tempo_atual / tempo_total) * max_value
