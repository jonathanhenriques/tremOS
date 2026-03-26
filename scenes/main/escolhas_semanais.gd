# escolhas_semanais.gd
extends Control

signal recompensa_escolhida(tipo, quantidade)

# Lista de recompensas sem madeira
var opcoes_possiveis = [
	{"nome": "+25 Aço", "tipo": "aco", "qtd": 25},
	{"nome": "+40 Concreto", "tipo": "concreto", "qtd": 40},
	{"nome": "+30 Metal", "tipo": "metal", "qtd": 30}
]

@onready var container = find_child("HBoxContainer", true, false)

func gerar_cards():
	if not container: return
	for child in container.get_children(): child.queue_free()
	
	opcoes_possiveis.shuffle()
	
	for i in range(3):
		var opcao = opcoes_possiveis[i]
		var btn = Button.new()
		btn.text = opcao["nome"]
		btn.custom_minimum_size = Vector2(200, 300)
		btn.pressed.connect(_on_card_pressed.bind(opcao["tipo"], opcao["qtd"]))
		container.add_child(btn)
	
	self.show()

func _on_card_pressed(tipo, qtd):
	recompensa_escolhida.emit(tipo, qtd)
	self.hide()
