# game_manager.gd - Malha Ferroviária de Alta Precisão
extends Node2D

@export var tamanho_mapa: int = 20
@export var tile_size: int = 100
@export var velocidade_jogo: float = 1.0

var tile_scene = preload("res://scenes/tile/tile.tscn")
var matriz_mapa = []
var estado_selecionado = 3 
var astar = AStar2D.new() # NOVO: Grafo customizado para conexões físicas precisas
var trens_ativos = {}
var info_label: Label
var sub_menu_container: HBoxContainer
var categoria_atual = "TRILHOS"
var popup_confirmacao: ConfirmationDialog

var categorias = {
	"TRILHOS": [22, 3, 4, 18, 19, 20, 21, 5, 6, 7],
	"BIOMAS": [2, 11, 14, 9, 10],
	"ESTRUTURAS": [17, 8]
}

var nomes_tiles = {
	0: "BORRACHA", 1: "SELEÇÃO", 2: "TERRA", 3: "TRILHO H", 4: "TRILHO V", 
	18: "┐ S-O", 19: "┘ N-O", 20: "└ N-L", 21: "┌ S-L",
	5: "BIFURC. Y", 6: "CRUZAM. H", 7: "CHAVE", 17: "PRINCIPAL", 8: "ESTAÇÃO", 
	9: "ÁRVORE", 10: "PEDRA", 11: "ÁGUA", 14: "MONTANHA", 22: "PINCEL MÁGICO"
}

@onready var mapa_node = $"../Mapa"

func _ready():
	Engine.time_scale = velocidade_jogo
	_criar_ui_sistema_soko()
	_criar_matriz_vazia()
	_configurar_grid_visual()
	_criar_mapa()
	_gerar_mapa_enriquecido()
	_setup_dialogos()

func _setup_dialogos():
	popup_confirmacao = ConfirmationDialog.new()
	popup_confirmacao.title = "Aviso de Engenharia"
	popup_confirmacao.dialog_text = "Deseja realmente remover esta estação estratégica?"
	add_child(popup_confirmacao)

func _criar_ui_sistema_soko():
	var canvas = CanvasLayer.new(); add_child(canvas)
	var topo = Panel.new(); topo.custom_minimum_size = Vector2(0, 90); topo.set_anchors_preset(Control.PRESET_TOP_WIDE); canvas.add_child(topo)
	info_label = Label.new(); topo.add_child(info_label); info_label.position = Vector2(160, 5)
	
	var scroll = ScrollContainer.new(); scroll.custom_minimum_size = Vector2(850, 60); scroll.position = Vector2(160, 30); topo.add_child(scroll)
	sub_menu_container = HBoxContainer.new(); sub_menu_container.add_theme_constant_override("separation", 10); scroll.add_child(sub_menu_container)

	var lateral = PanelContainer.new(); lateral.custom_minimum_size = Vector2(130, 0); lateral.set_anchors_preset(Control.PRESET_LEFT_WIDE); lateral.offset_top = 95; canvas.add_child(lateral)
	var vbox = VBoxContainer.new(); lateral.add_child(vbox)
	for n in ["BORRACHA", "SELEÇÃO"]:
		var b = Button.new(); b.text = n; b.custom_minimum_size = Vector2(110, 45); vbox.add_child(b); b.pressed.connect(_selecionar_ferramenta.bind(0 if n=="BORRACHA" else 1))
	for cat in categorias.keys():
		var btn = Button.new(); btn.text = cat; btn.custom_minimum_size = Vector2(110, 45); btn.pressed.connect(_abrir_sub_menu.bind(cat)); vbox.add_child(btn)
	_abrir_sub_menu("TRILHOS")

func _abrir_sub_menu(cat):
	categoria_atual = cat
	for n in sub_menu_container.get_children(): n.queue_free()
	for id in categorias[cat]:
		var btn = Button.new(); btn.text = nomes_tiles[id]; btn.custom_minimum_size = Vector2(120, 35); btn.pressed.connect(_selecionar_ferramenta.bind(id)); sub_menu_container.add_child(btn)

func _selecionar_ferramenta(id):
	estado_selecionado = id
	if info_label: info_label.text = "PLANOS: %dx%d | ATIVO: %s" % [tamanho_mapa, tamanho_mapa, nomes_tiles[id]]

func _input(event):
	if event is InputEventMouseButton and event.pressed and not Input.is_key_pressed(KEY_CTRL):
		if get_viewport().get_mouse_position().x > 130:
			var lista = categorias[categoria_atual]
			var idx = lista.find(estado_selecionado)
			if idx != -1:
				if event.button_index == MOUSE_BUTTON_WHEEL_UP: idx = (idx - 1 + lista.size()) % lista.size(); _selecionar_ferramenta(lista[idx])
				if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: idx = (idx + 1) % lista.size(); _selecionar_ferramenta(lista[idx])

func _criar_matriz_vazia():
	matriz_mapa.clear()
	for x in range(tamanho_mapa):
		matriz_mapa.append([]); for y in range(tamanho_mapa): matriz_mapa[x].append(2) 

func _criar_mapa():
	for n in mapa_node.get_children(): if n.name != "LinhasDoGrid": n.queue_free()
	for x in range(tamanho_mapa):
		for y in range(tamanho_mapa):
			var t = tile_scene.instantiate(); t.position = Vector2(x*100, y*100); t.configurar(x, y, self); mapa_node.add_child(t)

func _configurar_grid_visual():
	var l = mapa_node.get_node_or_null("LinhasDoGrid"); if l: l.configurar(tamanho_mapa, tile_size)

func atualizar_matriz(x, y, estado):
	if x >= 0 and x < tamanho_mapa and y >= 0 and y < tamanho_mapa:
		matriz_mapa[x][y] = estado; _reconstruir_malha()

func _get_id(x: int, y: int) -> int:
	return x + y * tamanho_mapa

func _eh_trilho_ou_estacao(tipo) -> bool:
	return tipo in [3, 4, 18, 19, 20, 21, 5, 6, 7, 8, 17, 12, 13, 15, 16]

# --- O NOVO CÉREBRO FÍSICO DO JOGO ---
func _reconstruir_malha():
	astar.clear()
	# 1. Cria os Pontos Existentes
	for x in range(tamanho_mapa):
		for y in range(tamanho_mapa):
			var tipo = matriz_mapa[x][y]
			if not _eh_trilho_ou_estacao(tipo): continue
			if tipo == 7:
				var t = _get_tile_at(x, y); if t and not t.chave_aberta: continue
			
			var id = _get_id(x, y)
			astar.add_point(id, Vector2(x, y))
			if tipo == 6: # Cruzamento H isola linhas horizontais de verticais (ID+1000)
				astar.add_point(id + 1000, Vector2(x, y))
	
	# 2. Conecta Pontos Apenas se houver Encaixe Físico
	var dirs = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
	for x in range(tamanho_mapa):
		for y in range(tamanho_mapa):
			var tipo_a = matriz_mapa[x][y]
			if not _eh_trilho_ou_estacao(tipo_a): continue
			if tipo_a == 7:
				var t = _get_tile_at(x, y); if t and not t.chave_aberta: continue
			
			for d in dirs:
				var nx = x + d.x; var ny = y + d.y
				if nx >= 0 and nx < tamanho_mapa and ny >= 0 and ny < tamanho_mapa:
					var tipo_b = matriz_mapa[nx][ny]
					if not _eh_trilho_ou_estacao(tipo_b): continue
					if tipo_b == 7:
						var tb = _get_tile_at(nx, ny); if tb and not tb.chave_aberta: continue
					
					_tentar_conectar(x, y, tipo_a, nx, ny, tipo_b, d)
	
	_verificar_integridade_trens()

func _tentar_conectar(ax, ay, tipo_a, bx, by, tipo_b, dir):
	if not _tem_saida(tipo_a, dir): return
	if not _tem_saida(tipo_b, -dir): return
	
	var id_a = _get_id(ax, ay)
	var id_b = _get_id(bx, by)
	
	if tipo_a == 6 and dir.y != 0: id_a += 1000 # Usa canal Vertical do Cruzamento
	if tipo_b == 6 and dir.y != 0: id_b += 1000 # Usa canal Vertical do Cruzamento
	
	if astar.has_point(id_a) and astar.has_point(id_b):
		if not astar.are_points_connected(id_a, id_b):
			astar.connect_points(id_a, id_b, true)

func _tem_saida(tipo, dir) -> bool:
	match tipo:
		3, 12, 15: return dir.x != 0 # H, Ponte H, Túnel H
		4, 13, 16: return dir.y != 0 # V, Ponte V, Túnel V
		18: return dir in [Vector2i(0, 1), Vector2i(-1, 0)] # ┐
		19: return dir in [Vector2i(0, -1), Vector2i(-1, 0)] # ┘
		20: return dir in [Vector2i(0, -1), Vector2i(1, 0)] # └
		21: return dir in [Vector2i(0, 1), Vector2i(1, 0)] # ┌
		5, 6, 7, 8, 17: return true
	return false

func _verificar_integridade_trens():
	var p_rem = []
	for id in trens_ativos.keys():
		var t_node = trens_ativos[id]
		var o = t_node.get_meta("origem"); var d = t_node.get_meta("destino")
		if astar.get_id_path(_get_id(o.x, o.y), _get_id(d.x, d.y)).size() < 2: p_rem.append(id)
	for id in p_rem:
		if is_instance_valid(trens_ativos[id]): trens_ativos[id].queue_free()
		trens_ativos.erase(id)

func tentar_lancar_trem():
	var principal = Vector2i(-1, -1); var alvos = []
	for x in range(tamanho_mapa):
		for y in range(tamanho_mapa):
			if matriz_mapa[x][y] == 17: principal = Vector2i(x, y)
			if matriz_mapa[x][y] == 8: alvos.append(Vector2i(x, y))
	
	if principal == Vector2i(-1, -1): return
	
	var enviados = 0
	for d in alvos:
		var path_ids = astar.get_id_path(_get_id(principal.x, principal.y), _get_id(d.x, d.y))
		if path_ids.size() > 1:
			var pts = []
			for pid in path_ids: pts.append(astar.get_point_position(pid))
			
			var id = "T_%d_%d_to_%d_%d" % [principal.x, principal.y, d.x, d.y]
			if not trens_ativos.has(id): 
				var t = _spawnar_trem(pts, id)
				t.set_meta("origem", principal); t.set_meta("destino", d)
			enviados += 1

	if enviados > 0: info_label.text = "TRENS LANÇADOS!"
	else: info_label.text = "ERRO: MALHA FERROVIÁRIA QUEBRADA!"

func aplicar_pincel_magico(x, y):
	var dirs = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
	var v = []
	for d in dirs:
		var n = Vector2i(x,y)+d
		if n.x>=0 and n.x<tamanho_mapa and n.y>=0 and n.y<tamanho_mapa:
			if _eh_trilho_ou_estacao(matriz_mapa[n.x][n.y]): v.append(d)
	var tipo = 3
	if v.size() == 2:
		var d1=v[0]; var d2=v[1]
		if d1.x!=0 and d2.x!=0: tipo=3
		if d1.y!=0 and d2.y!=0: tipo=4
		if (d1==Vector2i(0,1) and d2==Vector2i(-1,0)) or (d2==Vector2i(0,1) and d1==Vector2i(-1,0)): tipo=18
		if (d1==Vector2i(0,-1) and d2==Vector2i(-1,0)) or (d2==Vector2i(0,-1) and d1==Vector2i(-1,0)): tipo=19
		if (d1==Vector2i(0,-1) and d2==Vector2i(1,0)) or (d2==Vector2i(0,-1) and d1==Vector2i(1,0)): tipo=20
		if (d1==Vector2i(0,1) and d2==Vector2i(1,0)) or (d2==Vector2i(0,1) and d1==Vector2i(1,0)): tipo=21
	if v.size() == 3: tipo=5
	if v.size() == 4: tipo=6
	atualizar_matriz(x,y,tipo); var t = _get_tile_at(x,y); if t: t.estado_atual=tipo; t.queue_redraw()

func _spawnar_trem(pontos, id):
	var t = ColorRect.new(); t.name = id; t.size = Vector2(70, 35); t.color = Color.BLACK; t.z_index = 20
	add_child(t); trens_ativos[id] = t; _animar_trem(t, pontos); return t

func _animar_trem(t, pontos):
	var pts = []; for p in pontos: pts.append(Vector2(p.x*100 + 15, p.y*100 + 32))
	var tween = create_tween().set_loops()
	for p in pts: tween.tween_property(t, "position", p, 0.4)
	pts.reverse(); for p in pts: tween.tween_property(t, "position", p, 0.4)

func _get_tile_at(x, y):
	for t in mapa_node.get_children():
		if t.has_method("get_grid_pos") and t.get_grid_pos() == Vector2i(x, y): return t
	return null

func _gerar_mapa_enriquecido():
	_aplicar_no_mapa(2, 2, 17); _aplicar_no_mapa(15, 15, 8)
	for x in range(5, 14): _aplicar_no_mapa(x, 8, 11)
	for y in range(9, 17): _aplicar_no_mapa(10, y, 14)

func _aplicar_no_mapa(x, y, estado):
	atualizar_matriz(x, y, estado); var t = _get_tile_at(x, y); if t: t.estado_atual = estado; t.queue_redraw()
