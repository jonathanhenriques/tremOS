# game_manager.gd - Logística, Finanças e Proteção Total (SEM ELIF)
extends Node2D

@export var tamanho_mapa: int = 20
@export var tile_size: int = 100
@export var velocidade_jogo: float = 1.0

var tile_scene = preload("res://scenes/tile/tile.tscn")
var matriz_mapa = []
var estado_selecionado = 3 
var astar = AStar2D.new()
var trens_ativos = {}
var info_label: Label
var sub_menu_container: HBoxContainer
var categoria_atual = "TRILHOS"
var popup_confirmacao: ConfirmationDialog
var popup_vitoria: ConfirmationDialog

# --- CRONÔMETRO E ECONOMIA ---
var tempo_fase: float = 0.0
var nivel_atual: int = 1
var dinheiro: int = 1500
var fase_concluida := false
var estoque = {"LEITE": 0, "MADEIRA": 0, "TRIGO": 0}
var metas = {"LEITE": 0, "MADEIRA": 0, "TRIGO": 0}
var recompensas = {"LEITE": 200, "MADEIRA": 150, "TRIGO": 180}
var custos_construcao = {3: 10, 4: 10, 18: 15, 19: 15, 20: 15, 21: 15, 5: 30, 6: 40, 7: 50, 12: 100, 13: 100, 15: 150, 16: 150, 23: 50, 24: 50}
var cores_carga = {"LEITE": Color.WHITE, "MADEIRA": Color("#8b5a2b"), "TRIGO": Color("#f5deb3")}
var estacoes_oferta = {} 

var categorias = {
	"TRILHOS": [22, 3, 4, 18, 19, 20, 21, 5, 6, 7, 23, 24],
	"BIOMAS": [2, 11, 14, 9, 10],
	"ESTRUTURAS": [17, 8, 12, 13, 15, 16]
}

var nomes_tiles = {
	0: "BORRACHA", 1: "SELEÇÃO", 2: "TERRA", 3: "TRILHO H", 4: "TRILHO V", 
	18: "┐ S-O", 19: "┘ N-O", 20: "└ N-L", 21: "┌ S-L",
	5: "BIFURC. Y", 6: "CRUZAM. H", 7: "CHAVE", 17: "PRINCIPAL", 8: "ESTAÇÃO", 
	9: "ÁRVORE", 10: "PEDRA", 11: "ÁGUA", 14: "MONTANHA", 22: "PINCEL MÁGICO",
	12: "PONTE H", 13: "PONTE V", 15: "TÚNEL H", 16: "TÚNEL V", 23: "SEMÁFORO H", 24: "SEMÁFORO V"
}

# DECLARAÇÃO ESSENCIAL DO MAPA
@onready var mapa_node = $"../Mapa"

func _ready():
	Engine.time_scale = velocidade_jogo
	_criar_ui_sistema_soko()
	_criar_matriz_vazia()
	_configurar_grid_visual()
	_criar_mapa()
	_setup_dialogos()
	_iniciar_fase(1) 

func _process(delta):
	if not fase_concluida:
		tempo_fase += delta
		_atualizar_status_bar()

func _setup_dialogos():
	popup_confirmacao = ConfirmationDialog.new(); add_child(popup_confirmacao)
	popup_confirmacao.title = "Aviso de Engenharia"; popup_confirmacao.dialog_text = "Deseja remover esta estação?"
	
	popup_vitoria = ConfirmationDialog.new(); add_child(popup_vitoria)
	popup_vitoria.title = "VITÓRIA!"; popup_vitoria.ok_button_text = "Próxima Fase"; popup_vitoria.cancel_button_text = "Continuar"
	popup_vitoria.confirmed.connect(func(): nivel_atual += 1; _iniciar_fase(nivel_atual))

func _iniciar_fase(num):
	fase_concluida = false; tempo_fase = 0.0; dinheiro = 1500 + (num * 500); estoque = {"LEITE": 0, "MADEIRA": 0, "TRIGO": 0}
	estacoes_oferta.clear(); astar.clear()
	for id in trens_ativos.keys(): if is_instance_valid(trens_ativos[id]): trens_ativos[id].queue_free()
	trens_ativos.clear()
	for x in range(tamanho_mapa):
		for y in range(tamanho_mapa): _aplicar_no_mapa(x, y, 2)
	if num == 1: _gerar_mapa_nivel_1()
	if num >= 2: _gerar_mapa_nivel_2()
	_atualizar_status_bar()

func _criar_ui_sistema_soko():
	var canvas = CanvasLayer.new(); add_child(canvas)
	var topo = Panel.new(); topo.custom_minimum_size = Vector2(0, 90); topo.set_anchors_preset(Control.PRESET_TOP_WIDE); canvas.add_child(topo)
	info_label = Label.new(); topo.add_child(info_label); info_label.position = Vector2(160, 5)
	var scroll = ScrollContainer.new(); scroll.custom_minimum_size = Vector2(850, 60); scroll.position = Vector2(160, 30); topo.add_child(scroll)
	sub_menu_container = HBoxContainer.new(); scroll.add_child(sub_menu_container)
	var lateral = PanelContainer.new(); lateral.custom_minimum_size = Vector2(130, 0); lateral.set_anchors_preset(Control.PRESET_LEFT_WIDE); lateral.offset_top = 95; canvas.add_child(lateral)
	var vbox = VBoxContainer.new(); lateral.add_child(vbox)
	for n in ["BORRACHA", "SELEÇÃO"]:
		var b = Button.new(); b.text = n; b.custom_minimum_size = Vector2(110, 45); vbox.add_child(b)
		b.pressed.connect(_selecionar_ferramenta.bind(0 if n=="BORRACHA" else 1))
	for cat in categorias.keys():
		var btn = Button.new(); btn.text = cat; btn.custom_minimum_size = Vector2(110, 45); btn.pressed.connect(_abrir_sub_menu.bind(cat)); vbox.add_child(btn)
	_abrir_sub_menu("TRILHOS")

func _abrir_sub_menu(cat):
	categoria_atual = cat
	for n in sub_menu_container.get_children(): n.queue_free()
	for id in categorias[cat]:
		var btn = Button.new(); btn.text = nomes_tiles[id]; btn.custom_minimum_size = Vector2(120, 35)
		btn.pressed.connect(_selecionar_ferramenta.bind(id)); sub_menu_container.add_child(btn)

func _selecionar_ferramenta(id):
	estado_selecionado = id; _atualizar_status_bar()

func _get_tempo_formatado() -> String:
	var minutos = int(tempo_fase / 60)
	var segundos = int(tempo_fase) % 60
	return "%02d:%02d" % [minutos, segundos]

func _atualizar_status_bar():
	if info_label: 
		info_label.text = "TEMPO: %s | $ %d | FASE %d | ATIVO: %s | L: %d/%d | M: %d/%d" % [
			_get_tempo_formatado(), dinheiro, nivel_atual, nomes_tiles[estado_selecionado], 
			estoque["LEITE"], metas["LEITE"], estoque["MADEIRA"], metas["MADEIRA"]
		]

func gastar_dinheiro(id_ferramenta, pos_tela: Vector2 = Vector2.ZERO) -> bool:
	var custo = custos_construcao.get(id_ferramenta, 0)
	if custo == 0: return true
	if dinheiro >= custo:
		dinheiro -= custo; _atualizar_status_bar()
		if pos_tela != Vector2.ZERO: _spawn_floating_text(pos_tela, "- $" + str(custo), Color.RED)
		return true
	return false

func reembolsar_dinheiro(id_ferramenta, pos_tela: Vector2):
	var valor = custos_construcao.get(id_ferramenta, 0)
	if valor > 0:
		dinheiro += valor; _atualizar_status_bar()
		if pos_tela != Vector2.ZERO: _spawn_floating_text(pos_tela, "+ $" + str(valor), Color.GREEN)

func _spawn_floating_text(pos: Vector2, txt: String, col: Color):
	var l = Label.new(); l.text = txt; l.add_theme_color_override("font_color", col); l.add_theme_font_size_override("font_size", 22)
	var jitter = Vector2(randf_range(-15, 15), randf_range(-15, 15)) 
	l.position = pos + jitter; l.z_index = 50; add_child(l)
	var tw = create_tween(); tw.tween_property(l, "position", pos + jitter + Vector2(0,-60), 1.0); tw.parallel().tween_property(l, "modulate:a", 0.0, 1.0); tw.tween_callback(l.queue_free)

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if get_viewport().get_mouse_position().x > 130:
				var lista = categorias.get(categoria_atual, [])
				if lista.size() > 1 and estado_selecionado in lista:
					var idx = lista.find(estado_selecionado)
					if event.button_index == MOUSE_BUTTON_WHEEL_UP: idx = (idx - 1 + lista.size()) % lista.size()
					if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: idx = (idx + 1) % lista.size()
					_selecionar_ferramenta(lista[idx]); get_viewport().set_input_as_handled()

func _criar_matriz_vazia():
	matriz_mapa.clear()
	for x in range(tamanho_mapa):
		matriz_mapa.append([])
		for y in range(tamanho_mapa): matriz_mapa[x].append(2) 

func _criar_mapa():
	for n in mapa_node.get_children(): if n.name != "LinhasDoGrid": n.queue_free()
	for x in range(tamanho_mapa):
		for y in range(tamanho_mapa):
			var t = tile_scene.instantiate(); t.position = Vector2(x*100, y*100); t.configurar(x, y, self); mapa_node.add_child(t)

func _configurar_grid_visual():
	var l = mapa_node.get_node_or_null("LinhasDoGrid"); if l: l.configurar(tamanho_mapa, tile_size)

func atualizar_matriz(x, y, estado):
	if x >= 0 and x < tamanho_mapa and y >= 0 and y < tamanho_mapa: matriz_mapa[x][y] = estado; _reconstruir_malha()

func _eh_trilho_ou_estacao(tipo) -> bool:
	return tipo in [3, 4, 18, 19, 20, 21, 5, 6, 7, 8, 17, 12, 13, 15, 16, 23, 24]

func _reconstruir_malha():
	astar.clear()
	for x in range(tamanho_mapa):
		for y in range(tamanho_mapa):
			var tipo = matriz_mapa[x][y]
			if not _eh_trilho_ou_estacao(tipo): continue
			if tipo == 7:
				var t = _get_tile_at(x, y); if t and not t.chave_aberta: continue
			var id = x + y * tamanho_mapa; astar.add_point(id, Vector2(x, y))
			if tipo == 6: astar.add_point(id + 1000, Vector2(x, y))
	
	var dirs = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
	for x in range(tamanho_mapa):
		for y in range(tamanho_mapa):
			var ta = matriz_mapa[x][y]
			if not _eh_trilho_ou_estacao(ta): continue
			for d in dirs:
				var nx = x+d.x; var ny = y+d.y
				if nx>=0 and nx<tamanho_mapa and ny>=0 and ny<tamanho_mapa:
					var tb = matriz_mapa[nx][ny]
					if _eh_trilho_ou_estacao(tb): _tentar_conectar(x,y,ta,nx,ny,tb,d)
	_verificar_integridade_trens()

func _tentar_conectar(ax, ay, ta, bx, by, tb, d):
	if not _tem_saida(ta, d): return
	if not _tem_saida(tb, -d): return
	var ida = ax + ay * tamanho_mapa; var idb = bx + by * tamanho_mapa
	if ta == 6 and d.y != 0: ida += 1000
	if tb == 6 and d.y != 0: idb += 1000
	if astar.has_point(ida) and astar.has_point(idb): astar.connect_points(ida, idb, true)

func _tem_saida(tipo, dir) -> bool:
	if tipo in [3, 12, 15, 23]: return dir.x != 0
	if tipo in [4, 13, 16, 24]: return dir.y != 0
	if tipo == 18: return dir in [Vector2i(0, 1), Vector2i(-1, 0)]
	if tipo == 19: return dir in [Vector2i(0, -1), Vector2i(-1, 0)]
	if tipo == 20: return dir in [Vector2i(0, -1), Vector2i(1, 0)]
	if tipo == 21: return dir in [Vector2i(0, 1), Vector2i(1, 0)]
	if tipo in [5, 6, 7, 8, 17]: return true
	return false

func _verificar_integridade_trens():
	var rem = []
	for id in trens_ativos.keys():
		var t = trens_ativos[id]; var o = t.get_meta("origem"); var d = t.get_meta("destino")
		if astar.get_id_path(o.x + o.y*tamanho_mapa, d.x + d.y*tamanho_mapa).size() < 2: rem.append(id)
	for id in rem: if is_instance_valid(trens_ativos[id]): trens_ativos[id].queue_free(); trens_ativos.erase(id)

func tentar_lancar_trem():
	var principal = Vector2i(-1, -1); var alvos = []
	for x in range(tamanho_mapa):
		for y in range(tamanho_mapa):
			if matriz_mapa[x][y] == 17: principal = Vector2i(x, y)
			if matriz_mapa[x][y] == 8: alvos.append(Vector2i(x, y))
	if principal == Vector2i(-1, -1): return
	for d in alvos:
		var p_ids = astar.get_id_path(principal.x + principal.y*tamanho_mapa, d.x + d.y*tamanho_mapa)
		if p_ids.size() > 1:
			var pts = []; for pid in p_ids: pts.append(astar.get_point_position(pid))
			var id = "T_%d_%d_%d" % [d.x, d.y, Time.get_ticks_msec()]
			_spawnar_trem(pts, id, estacoes_oferta.get(d, "LEITE"), principal, d)
	_atualizar_status_bar()

# PINCEL MÁGICO PROTEGIDO CONTRA SOBREPOSIÇÃO DE ESTAÇÕES
func aplicar_pincel_magico(x, y):
	if x < 0 or x >= tamanho_mapa or y < 0 or y >= tamanho_mapa: return
	if matriz_mapa[x][y] in [17, 8, 10]: return # BLOQUEIO DE ESTRUTURAS
	
	var dirs = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]; var v = []
	for d in dirs:
		var n = Vector2i(x,y)+d
		if n.x>=0 and n.x<tamanho_mapa and n.y>=0 and n.y<tamanho_mapa:
			if _eh_trilho_ou_estacao(matriz_mapa[n.x][n.y]): v.append(d)
	
	var tipo = 3
	if v.size() == 2:
		var d1 = v[0]; var d2 = v[1]
		if d1.x != 0 and d2.x != 0: tipo = 3
		if d1.y != 0 and d2.y != 0: tipo = 4
		if (d1 == Vector2i(0,1) and d2 == Vector2i(-1,0)) or (d2 == Vector2i(0,1) and d1 == Vector2i(-1,0)): tipo = 18
		if (d1 == Vector2i(0,-1) and d2 == Vector2i(-1,0)) or (d2 == Vector2i(0,-1) and d1 == Vector2i(-1,0)): tipo = 19
		if (d1 == Vector2i(0,-1) and d2 == Vector2i(1,0)) or (d2 == Vector2i(0,-1) and d1 == Vector2i(1,0)): tipo = 20
		if (d1 == Vector2i(0,1) and d2 == Vector2i(1,0)) or (d2 == Vector2i(0,1) and d1 == Vector2i(1,0)): tipo = 21
	if v.size() == 3: tipo = 5
	if v.size() == 4: tipo = 6
	
	if matriz_mapa[x][y] != tipo:
		var tile_antigo = matriz_mapa[x][y]
		var pos_tela = Vector2(x*100+25, y*100)
		if gastar_dinheiro(tipo, pos_tela):
			if tile_antigo not in [2, 11, 14, 9, 10]: reembolsar_dinheiro(tile_antigo, pos_tela)
			atualizar_matriz(x,y,tipo); var t=_get_tile_at(x,y); if t: t.estado_atual=tipo; t.queue_redraw()

func _spawnar_trem(pontos, id, carga, o, d):
	var t = Node2D.new(); t.name = id; t.z_index = 20; add_child(t); trens_ativos[id] = t
	var loc = ColorRect.new(); loc.size = Vector2(40, 30); loc.color = Color(0.1, 0.1, 0.1); t.add_child(loc)
	var vag = ColorRect.new(); vag.name = "Vagao"; vag.size = Vector2(25, 20); vag.color = Color(0.3, 0.3, 0.3); vag.position = Vector2(42, 5); t.add_child(vag)
	t.set_meta("origem", o); t.set_meta("destino", d); t.set_meta("carga", carga)
	var pts = []; for p in pontos: pts.append(Vector2(p.x*100 + 10, p.y*100 + 35))
	var p_rev = pts.duplicate(); p_rev.reverse(); var tw = create_tween().set_loops()
	for p in pts: tw.tween_property(t, "position", p, 0.4)
	tw.tween_callback(func(): if is_instance_valid(t): t.get_node("Vagao").color = cores_carga[carga])
	for p in p_rev: tw.tween_property(t, "position", p, 0.4)
	tw.tween_callback(func():
		if is_instance_valid(t):
			t.get_node("Vagao").color = Color(0.3, 0.3, 0.3); estoque[carga] += 1; dinheiro += recompensas[carga]
			_spawn_floating_text(t.position, "+ $" + str(recompensas[carga]), Color.GREEN); _atualizar_status_bar(); _checar_vitoria())
	return t

func _checar_vitoria():
	if fase_concluida: return
	var ok = true
	if estoque["LEITE"] < metas["LEITE"]: ok = false
	if estoque["MADEIRA"] < metas["MADEIRA"]: ok = false
	if ok: fase_concluida = true; popup_vitoria.dialog_text = "Metas atingidas!\nTempo Final: %s" % _get_tempo_formatado(); popup_vitoria.popup_centered()

func _get_tile_at(x, y):
	for t in mapa_node.get_children(): if t.has_method("get_grid_pos") and t.get_grid_pos() == Vector2i(x, y): return t
	return null

func _gerar_mapa_nivel_1():
	metas = {"LEITE": 3, "MADEIRA": 2, "TRIGO": 0}
	for x in range(tamanho_mapa): _aplicar_no_mapa(x, 9, 11); _aplicar_no_mapa(x, 10, 11)
	_aplicar_no_mapa(2, 2, 17); _aplicar_estacao_oferta(17, 17, "LEITE"); _aplicar_estacao_oferta(4, 15, "MADEIRA")
	var arvores = [Vector2i(2, 5), Vector2i(2, 6), Vector2i(17, 13), Vector2i(17, 14)]
	for a in arvores: _aplicar_no_mapa(a.x, a.y, 9)

func _gerar_mapa_nivel_2():
	metas = {"LEITE": 2, "MADEIRA": 4, "TRIGO": 2}
	for y in range(tamanho_mapa): _aplicar_no_mapa(8, y, 11)
	_aplicar_no_mapa(17, 2, 17); _aplicar_estacao_oferta(2, 17, "LEITE"); _aplicar_estacao_oferta(2, 2, "MADEIRA")
	var arvores = [Vector2i(16, 2), Vector2i(17, 3), Vector2i(8, 8)]
	for a in arvores: _aplicar_no_mapa(a.x, a.y, 9)

func _aplicar_estacao_oferta(x, y, tipo): estacoes_oferta[Vector2i(x, y)] = tipo; _aplicar_no_mapa(x, y, 8)
func _aplicar_no_mapa(x, y, estado):
	matriz_mapa[x][y] = estado; var t = _get_tile_at(x, y)
	if t: t.estado_atual = estado; t.base_bioma = estado if estado in [2,11,14] else 2; t.queue_redraw()
	_reconstruir_malha()
