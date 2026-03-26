extends CharacterBody2D
# trabalhador.gd - IA Unificada de Extração e Construção

# --- ESTADOS ---
enum Estado { IDLE, MOVENDO, TRABALHANDO }
var estado_atual = Estado.IDLE

# --- CONFIGURAÇÕES ---
@export var velocidade: float = 200.0
var alvo_atual: Node2D = null
var progresso_trabalho: float = 0.0

# --- REFERÊNCIAS ---
@onready var gm = get_node("/root/TremOS_Main/MesaDoSecretario")

func _process(delta):
	match estado_atual:
		Estado.IDLE:
			_buscar_tarefa_proxima()
		Estado.MOVENDO:
			_mover_para_alvo(delta)
		Estado.TRABALHANDO:
			_processar_trabalho(delta)

func _buscar_tarefa_proxima():
	var mapa = get_node("../Mapa")
	var menor_distancia = INF
	var candidato = null

	# O trabalhador agora busca QUALQUER recurso disponível (Árvore ou Pedra)
	for recurso in mapa.get_children():
		if (recurso.is_in_group("arvores") or recurso.is_in_group("pedras")) and not recurso.get_meta("ocupado", false):
			var dist = position.distance_to(recurso.position)
			if dist < menor_distancia:
				menor_distancia = dist
				candidato = recurso

	if candidato:
		alvo_atual = candidato
		alvo_atual.set_meta("ocupado", true)
		estado_atual = Estado.MOVENDO

func _mover_para_alvo(delta):
	if not is_instance_valid(alvo_atual):
		estado_atual = Estado.IDLE
		return

	var direcao = (alvo_atual.position - position).normalized()
	velocity = direcao * velocidade
	move_and_slide()

	if position.distance_to(alvo_atual.position) < 15:
		estado_atual = Estado.TRABALHANDO

func _processar_trabalho(delta):
	# A velocidade de trabalho depende de quantos trabalhadores estão na mesma área (Lógica 1x, 2x, 3x)
	# Por enquanto, em extração simples, usamos a base de 1:1
	progresso_trabalho += delta
	
	if progresso_trabalho >= 5.0: # 5 segundos para extrair 1 item
		_finalizar_tarefa()

func _finalizar_tarefa():
	# Identifica o que foi coletado para atualizar o estoque correto
	if alvo_atual.is_in_group("arvores"):
		gm.adicionar_material("madeira", 1)
		alvo_atual.tornar_toco() # Transforma Triângulo em Círculo
	elif alvo_atual.is_in_group("pedras"):
		gm.adicionar_material("pedra", 1)
		alvo_atual.queue_free() # Remove Retângulo
	
	progresso_trabalho = 0.0
	estado_atual = Estado.IDLE
