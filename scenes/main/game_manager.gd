# game_manager.gd - Colisões Físicas, Fila de Lançamento e Game Over
extends Node2D

# --- CONFIGURAÇÕES GERAIS E EXPORTS ---
@export var tamanho_mapa: int = 20
@export var tile_size: int = 100
@export var velocidade_jogo: float = 1.0

@export var modo_dev: bool = true # Ativa abas de Biomas/Estruturas e botão Continuar no Game Over

# --- REFERÊNCIAS E NODES ---
var tile_scene = preload("res://scenes/tile/tile.tscn")
@onready var mapa_node = $"../Mapa"

var info_label: Label
var sub_menu_container: HBoxContainer
var popup_confirmacao: ConfirmationDialog
var popup_vitoria: ConfirmationDialog
var popup_relatorio: AcceptDialog 
var popup_orcamento: AcceptDialog
var popup_game_over: ConfirmationDialog
var botao_pause: Button

# --- VARIÁVEIS DE ESTADO E LÓGICA ---
var matriz_mapa = []
var estado_selecionado = 22 # Inicia no Pincel Mágico
var astar = AStar2D.new()
var trens_ativos = {}
var jogo_perdido: bool = false
var ultima_pos_pincel: Vector2i = Vector2i(-1, -1)
var categoria_atual = "TRILHOS"

# --- FILA DE TRENS E COLISÕES ---
var fila_trens_pendentes = []
var tempo_prox_trem: float = 0.0
var ignorar_colisao_timer: float = 0.0

# --- ORÇAMENTO E DESASTRES ---
var verba_vias: float = 100.0 
var verba_trens: float = 100.0 
var limite_seguro_vias: float = 50.0 
var trilhos_quebrados = [] 
var dinheiro: int = 2000 

# --- TEMPO ---
var tempo_fase: float = 0.0
var tempo_semana: float = 0.0
var duracao_semana: float = 30.0 
var semana_atual: int = 1
var receita_semanal: int = 0 

# --- DICIONÁRIOS E RECURSOS ---
var fase_concluida := false
var nivel_atual: int = 1
var estoque = {"LEITE": 0, "MADEIRA": 0, "TRIGO": 0, "ACO": 0, "CARVAO": 0}
var metas = {"LEITE": 0, "MADEIRA": 0, "TRIGO": 0, "ACO": 0, "CARVAO": 0}
var recompensas = {"LEITE": 200, "MADEIRA": 150, "TRIGO": 180, "ACO": 300, "CARVAO": 250}
var cores_carga = {"LEITE": Color.WHITE, "MADEIRA": Color("#8b5a2b"), "TRIGO": Color("#f5deb3"), "ACO": Color("#a9a9a9"), "CARVAO": Color("#2f4f4f")}
var custos_construcao = {3: 10, 4: 10, 18: 15, 19: 15, 20: 15, 21: 15, 5: 30, 6: 40, 7: 50, 12: 100, 13: 100, 15: 150, 16: 150, 23: 50, 24: 50}
var estacoes_oferta = {} 

# --- UI LIMPA ---
var categorias = {"TRILHOS": [22, 7, 23], "BIOMAS": [2, 11, 14, 9, 10], "ESTRUTURAS": [17, 8]}
var nomes_tiles = {0: "BORRACHA", 1: "SELEÇÃO", 2: "TERRA", 3: "TRILHO H", 4: "TRILHO V", 18: "┐ S-O", 19: "┘ N-O", 20: "└ N-L", 21: "┌ S-L", 5: "BIFURC. Y", 6: "CRUZAM. H", 7: "CHAVE", 17: "PRINCIPAL", 8: "ESTAÇÃO", 9: "ÁRVORE", 10: "PEDRA", 11: "ÁGUA", 14: "MONTANHA", 22: "PINCEL MÁGICO", 12: "PONTE H", 13: "PONTE V", 15: "TÚNEL H", 16: "TÚNEL V", 23: "SEMÁFORO", 24: "SEMÁFORO V"}

# ==========================================
# FUNÇÕES LIFECYCLE E UPDATE
# ==========================================
func _ready():
	Engine.time_scale = velocidade_jogo
	_criar_ui_sistema_soko()
	_criar_matriz_vazia()
	_configurar_grid_visual()
	_criar_mapa()
	_setup_dialogos()
	_iniciar_fase(1) 

func _process(delta):
	if not fase_concluida and not jogo_perdido:
		if not get_tree().paused:
			tempo_fase += delta
			tempo_semana += delta
			if tempo_semana >= duracao_semana:
				_gerar_relatorio_semanal()
			
			# --- LANÇAMENTO DE TRENS COM DELAY ---
			if fila_trens_pendentes.size() > 0:
				tempo_prox_trem -= delta
				if tempo_prox_trem <= 0.0:
					var trem_data = fila_trens_pendentes.pop_front()
					_spawnar_trem(trem_data.pts, trem_data.id, trem_data.carga, trem_data.o, trem_data.d)
					tempo_prox_trem = 2.0 # 2 segundos de intervalo de saída da estação
			
			_processar_movimento_trens(delta)
			
			# --- VERIFICAÇÃO DE COLISÕES FÍSICAS ---
			if ignorar_colisao_timer > 0:
				ignorar_colisao_timer -= delta
			else:
				_verificar_colisoes()
			
		_atualizar_status_bar()
		
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		ultima_pos_pincel = Vector2i(-1, -1)

func _input(event):
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_P):
		_alternar_pause()

	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if get_viewport().get_mouse_position().x > 130:
				var lista = categorias.get(categoria_atual, [])
				if lista.size() > 1 and estado_selecionado in lista:
					var idx = lista.find(estado_selecionado)
					if event.button_index == MOUSE_BUTTON_WHEEL_UP: idx = (idx - 1 + lista.size()) % lista.size()
					if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: idx = (idx + 1) % lista.size()
					_selecionar_ferramenta(lista[idx]); get_viewport().set_input_as_handled()

# ==========================================
# SISTEMA DE DIÁLOGOS E UI
# ==========================================
func _setup_dialogos():
	popup_confirmacao = ConfirmationDialog.new(); add_child(popup_confirmacao)
	popup_confirmacao.title = "Aviso de Engenharia"; popup_confirmacao.dialog_text = "Deseja remover esta estrutura?"
	popup_confirmacao.process_mode = Node.PROCESS_MODE_ALWAYS
	
	popup_vitoria = ConfirmationDialog.new(); add_child(popup_vitoria)
	popup_vitoria.title = "VITÓRIA!"; popup_vitoria.ok_button_text = "Próxima Fase"; popup_vitoria.cancel_button_text = "Continuar"
	popup_vitoria.confirmed.connect(_avancar_fase)
	popup_vitoria.process_mode = Node.PROCESS_MODE_ALWAYS

	popup_relatorio = AcceptDialog.new(); add_child(popup_relatorio)
	popup_relatorio.title = "Balanço Financeiro Semanal"
	popup_relatorio.ok_button_text = "Iniciar Nova Semana"
	popup_relatorio.exclusive = true 
	popup_relatorio.confirmed.connect(_iniciar_nova_semana)
	popup_relatorio.process_mode = Node.PROCESS_MODE_ALWAYS
	
	popup_game_over = ConfirmationDialog.new()
	add_child(popup_game_over)
	popup_game_over.title = "💥 COLISÃO FERROVIÁRIA! 💥"
	popup_game_over.dialog_text = "Dois trens colidiram na sua malha!\n\nVocê deve planejar desvios, cruzamentos e semáforos para evitar acidentes."
	popup_game_over.ok_button_text = "Reiniciar Fase"
	popup_game_over.cancel_button_text = "Abandonar Jogo"
	popup_game_over.process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Só adiciona o botão de continuar (trapaça) se estiver no modo de desenvolvimento
	if modo_dev:
		var btn_dev = popup_game_over.add_button("Modo Dev: Ignorar", false, "continuar_dev")
		btn_dev.pressed.connect(func():
			jogo_perdido = false
			get_tree().paused = false
			ignorar_colisao_timer = 3.0 # Ficam intangíveis por 3s para se soltarem
			popup_game_over.hide()
		)
	
	popup_game_over.confirmed.connect(func(): _iniciar_fase(nivel_atual))
	popup_game_over.canceled.connect(func(): get_tree().quit())
	
	_construir_painel_orcamento()

func _construir_painel_orcamento():
	popup_orcamento = AcceptDialog.new(); add_child(popup_orcamento)
	popup_orcamento.title = "Orçamento de Utilidades e Transportes"
	popup_orcamento.ok_button_text = "Aplicar Verbas"
	popup_orcamento.exclusive = true
	popup_orcamento.process_mode = Node.PROCESS_MODE_ALWAYS
	
	var vbox = VBoxContainer.new(); popup_orcamento.add_child(vbox)
	
	var label_vias = Label.new(); label_vias.text = "Despesas: Manutenção de Vias"; vbox.add_child(label_vias)
	var slider_vias = HSlider.new(); slider_vias.min_value = 0; slider_vias.max_value = 100; slider_vias.value = verba_vias; vbox.add_child(slider_vias)
	var val_vias = Label.new(); val_vias.text = "Verba: 100%"; vbox.add_child(val_vias)
	slider_vias.value_changed.connect(func(v): verba_vias = v; val_vias.text = "Verba: " + str(v) + "%")
	
	var separador = HSeparator.new(); vbox.add_child(separador)
	
	var label_trens = Label.new(); label_trens.text = "Despesas: Operação da Frota"; vbox.add_child(label_trens)
	var slider_trens = HSlider.new(); slider_trens.min_value = 0; slider_trens.max_value = 100; slider_trens.value = verba_trens; vbox.add_child(slider_trens)
	var val_trens = Label.new(); val_trens.text = "Verba: 100%"; vbox.add_child(val_trens)
	slider_trens.value_changed.connect(func(v): verba_trens = v; val_trens.text = "Verba: " + str(v) + "%")
	
	popup_orcamento.confirmed.connect(func(): if not get_tree().paused: Engine.time_scale = velocidade_jogo)

func _criar_ui_sistema_soko():
	var canvas = CanvasLayer.new(); add_child(canvas)
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	
	var topo = Panel.new(); topo.custom_minimum_size = Vector2(0, 90); topo.set_anchors_preset(Control.PRESET_TOP_WIDE); canvas.add_child(topo)
	info_label = Label.new(); topo.add_child(info_label); info_label.position = Vector2(160, 5)
	
	var btn_orc = Button.new(); btn_orc.text = "ORÇAMENTO"; btn_orc.position = Vector2(20, 5); btn_orc.custom_minimum_size = Vector2(120, 30)
	btn_orc.add_theme_color_override("font_color", Color.YELLOW)
	btn_orc.pressed.connect(func(): popup_orcamento.popup_centered())
	topo.add_child(btn_orc)
	
	botao_pause = Button.new(); botao_pause.text = "PAUSE"; botao_pause.position = Vector2(20, 45); botao_pause.custom_minimum_size = Vector2(120, 35)
	botao_pause.pressed.connect(_alternar_pause)
	topo.add_child(botao_pause)
	
	var scroll = ScrollContainer.new(); scroll.custom_minimum_size = Vector2(850, 60); scroll.position = Vector2(160, 30); topo.add_child(scroll)
	sub_menu_container = HBoxContainer.new(); scroll.add_child(sub_menu_container)
	var lateral = PanelContainer.new(); lateral.custom_minimum_size = Vector2(130, 0); lateral.set_anchors_preset(Control.PRESET_LEFT_WIDE); lateral.offset_top = 95; canvas.add_child(lateral)
	
	var vbox = VBoxContainer.new(); lateral.add_child(vbox)
	
	for n in ["BORRACHA", "SELEÇÃO"]:
		var b = Button.new(); b.text = n; b.custom_minimum_size = Vector2(110, 45); vbox.add_child(b)
		b.pressed.connect(_selecionar_ferramenta.bind(0 if n=="BORRACHA" else 1))
	
	for cat in categorias.keys():
		if not modo_dev and (cat == "BIOMAS" or cat == "ESTRUTURAS"):
			continue
		var btn = Button.new(); btn.text = cat; btn.custom_minimum_size = Vector2(110, 45); btn.pressed.connect(_abrir_sub_menu.bind(cat)); vbox.add_child(btn)
	
	_abrir_sub_menu("TRILHOS")

func _alternar_pause():
	if get_tree().paused == true:
		get_tree().paused = false
		botao_pause.text = "PAUSE"
		botao_pause.add_theme_color_override("font_color", Color.WHITE)
	else:
		get_tree().paused = true
		botao_pause.text = "CONTINUAR"
		botao_pause.add_theme_color_override("font_color", Color.GREEN)

func _abrir_sub_menu(cat):
	categoria_atual = cat
	for n in sub_menu_container.get_children(): n.queue_free()
	for id in categorias[cat]:
		if id == 24: continue 
		
		var btn = Button.new(); btn.text = nomes_tiles[id]; btn.custom_minimum_size = Vector2(120, 35)
		btn.pressed.connect(_selecionar_ferramenta.bind(id)); sub_menu_container.add_child(btn)

func _selecionar_ferramenta(id):
	estado_selecionado = id; _atualizar_status_bar()

func _get_tempo_formatado() -> String:
	var minutos = int(tempo_fase / 60); var segundos = int(tempo_fase) % 60
	return "%02d:%02d" % [minutos, segundos]

func _atualizar_status_bar():
	if info_label: 
		var string_metas = ""
		for k in metas.keys():
			if metas[k] > 0: string_metas += k.left(3) + ": " + str(estoque[k]) + "/" + str(metas[k]) + " | "
		var status_texto = "PLAY" if not get_tree().paused else "PLANEJAMENTO"
		info_label.text = "[%s] T: %s | $ %d | FASE %d | ATIVO: %s | %s" % [status_texto, _get_tempo_formatado(), dinheiro, nivel_atual, nomes_tiles[estado_selecionado], string_metas]

# ==========================================
# LÓGICA DE JOGO, PROGRESSÃO E ECONOMIA
# ==========================================
func gastar_dinheiro(id_ferramenta, pos_tela: Vector2 = Vector2.ZERO) -> bool:
	var custo = custos_construcao.get(id_ferramenta, 0)
	if custo == 0: return true
	if dinheiro < custo: return false
	dinheiro -= custo; _atualizar_status_bar()
	if pos_tela != Vector2.ZERO: _spawn_floating_text(pos_tela, "- $" + str(custo), Color.RED)
	return true

func gastar_dinheiro_especifico(valor: int, pos_tela: Vector2) -> bool:
	if dinheiro < valor: return false
	dinheiro -= valor; _atualizar_status_bar()
	if pos_tela != Vector2.ZERO: _spawn_floating_text(pos_tela, "- $" + str(valor), Color.RED)
	return true

func reembolsar_dinheiro(id_ferramenta, pos_tela: Vector2):
	var valor = custos_construcao.get(id_ferramenta, 0)
	if valor > 0:
		dinheiro += valor; _atualizar_status_bar()
		if pos_tela != Vector2.ZERO: _spawn_floating_text(pos_tela, "+ $" + str(valor), Color.GREEN)

func _spawn_floating_text(pos: Vector2, txt: String, col: Color):
	var l = Label.new(); l.text = txt; l.add_theme_color_override("font_color", col); l.add_theme_font_size_override("font_size", 22)
	l.position = pos + Vector2(randf_range(-15, 15), randf_range(-15, 15)); l.z_index = 50; add_child(l)
	l.process_mode = Node.PROCESS_MODE_ALWAYS
	var tw = create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS) 
	tw.tween_property(l, "position", l.position + Vector2(0,-60), 1.0)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)

func _avancar_fase():
	nivel_atual += 1
	if nivel_atual > 3: nivel_atual = 1 
	_iniciar_fase(nivel_atual)

func _gerar_relatorio_semanal():
	get_tree().paused = true
	var principal_pos = Vector2i(-1, -1); var alvos = []
	for x in range(tamanho_mapa):
		for y in range(tamanho_mapa):
			if matriz_mapa[x][y] == 17: principal_pos = Vector2i(x,y)
			if matriz_mapa[x][y] == 8: alvos.append(Vector2i(x,y))
	
	var tiles_ativos_pos = [] 
	if principal_pos != Vector2i(-1,-1):
		for a in alvos:
			var path = astar.get_id_path(principal_pos.x + principal_pos.y*tamanho_mapa, a.x + a.y*tamanho_mapa)
			for id in path:
				var px = id % 1000 % tamanho_mapa
				var py = id % 1000 / tamanho_mapa
				var pos = Vector2i(px, py)
				if not tiles_ativos_pos.has(pos): tiles_ativos_pos.append(pos)
	
	var custo_trilhos_ideal = tiles_ativos_pos.size() * 1.0
	var custo_trilhos_real = int(custo_trilhos_ideal * (verba_vias / 100.0))
	
	var qtd_trens = trens_ativos.size()
	var custo_trens_ideal = qtd_trens * 10.0 
	var custo_trens_real = int(custo_trens_ideal * (verba_trens / 100.0))
	
	var custo_total = custo_trilhos_real + custo_trens_real
	dinheiro -= custo_total 
	
	var vias_quebradas_agora = 0
	var deficit_critico = limite_seguro_vias - verba_vias
	
	if deficit_critico > 0.0: 
		var chance_quebra = (deficit_critico / 50.0) * 0.40 
		for pos in tiles_ativos_pos:
			if randf() < chance_quebra:
				if not trilhos_quebrados.has(pos):
					trilhos_quebrados.append(pos)
					vias_quebradas_agora += 1
					var t = _get_tile_at(pos.x, pos.y)
					if t: t.queue_redraw()
	_reconstruir_malha() 
	
	var texto = "RESUMO DA SEMANA " + str(semana_atual) + "\n\n"
	texto += "Vias: - $" + str(custo_trilhos_real) + "\n"
	texto += "Trens: - $" + str(custo_trens_real) + "\n"
	texto += "Receita: + $" + str(receita_semanal) + "\n"
	texto += "--------------------------------------\n"
	if vias_quebradas_agora > 0:
		texto += "⚠️ " + str(vias_quebradas_agora) + " trilhos cederam!\n"
	texto += "\nSALDO: $" + str(dinheiro)
	
	popup_relatorio.dialog_text = texto
	popup_relatorio.popup_centered()

func consertar_trilho(x: int, y: int):
	var pos = Vector2i(x, y)
	if trilhos_quebrados.has(pos):
		if gastar_dinheiro_especifico(25, Vector2(x*100+25, y*100)): 
			trilhos_quebrados.erase(pos)
			_reconstruir_malha()
			var t = _get_tile_at(x, y)
			if t: t.queue_redraw()

func _iniciar_nova_semana():
	get_tree().paused = false
	receita_semanal = 0
	tempo_semana = 0.0
	semana_atual += 1

func _iniciar_fase(num):
	get_tree().paused = false
	fase_concluida = false; tempo_fase = 0.0; tempo_semana = 0.0; semana_atual = 1; receita_semanal = 0
	jogo_perdido = false
	dinheiro = 2000 + (num * 500)
	
	trilhos_quebrados.clear()
	fila_trens_pendentes.clear()
	tempo_prox_trem = 0.0
	ignorar_colisao_timer = 0.0
	
	for k in estoque.keys(): estoque[k] = 0; metas[k] = 0
	estacoes_oferta.clear(); astar.clear()
	for id in trens_ativos.keys(): if is_instance_valid(trens_ativos[id]): trens_ativos[id].queue_free()
	trens_ativos.clear()
	for x in range(tamanho_mapa):
		for y in range(tamanho_mapa): _aplicar_no_mapa(x, y, 2)
	if num == 1: _gerar_mapa_nivel_1()
	if num == 2: _gerar_mapa_nivel_2()
	if num == 3: _gerar_mapa_nivel_3()
	_atualizar_status_bar()

func _checar_vitoria():
	var ok = true
	for r in metas.keys(): if metas[r] > 0 and estoque[r] < metas[r]: ok = false
	if ok and not fase_concluida: 
		fase_concluida = true; popup_vitoria.dialog_text = "Fase concluída em %s" % _get_tempo_formatado(); popup_vitoria.popup_centered()

# ==========================================
# MAPA E AStar2D
# ==========================================
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
	if x >= 0 and x < tamanho_mapa and y >= 0 and y < tamanho_mapa: 
		matriz_mapa[x][y] = estado; _reconstruir_malha()

func _eh_trilho_ou_estacao(tipo) -> bool:
	return tipo in [3, 4, 18, 19, 20, 21, 5, 6, 7, 8, 17, 12, 13, 15, 16, 23, 24]

func _reconstruir_malha():
	astar.clear()
	for x in range(tamanho_mapa):
		for y in range(tamanho_mapa):
			var tipo = matriz_mapa[x][y]
			if not _eh_trilho_ou_estacao(tipo): continue
			
			if trilhos_quebrados.has(Vector2i(x,y)): continue 
			
			astar.add_point(x + y * tamanho_mapa, Vector2(x, y))
			if tipo == 6: astar.add_point(x + y * tamanho_mapa + 1000, Vector2(x, y))
	
	var dirs = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
	for x in range(tamanho_mapa):
		for y in range(tamanho_mapa):
			var ta = matriz_mapa[x][y]
			if not _eh_trilho_ou_estacao(ta) or trilhos_quebrados.has(Vector2i(x,y)): continue 
			for d in dirs:
				var nx = x+d.x; var ny = y+d.y
				if nx>=0 and nx<tamanho_mapa and ny>=0 and ny<tamanho_mapa:
					var tb = matriz_mapa[nx][ny]
					if _eh_trilho_ou_estacao(tb) and not trilhos_quebrados.has(Vector2i(nx,ny)): 
						_tentar_conectar(x,y,ta,nx,ny,tb,d)

func _tentar_conectar(ax, ay, ta, bx, by, tb, d):
	if not _tem_saida(ta, d) or not _tem_saida(tb, -d): return
	
	var t_a = _get_tile_at(ax, ay)
	var t_b = _get_tile_at(bx, by)
	if t_a and t_a.has_method("is_direction_closed") and t_a.is_direction_closed(d): return
	if t_b and t_b.has_method("is_direction_closed") and t_b.is_direction_closed(-d): return
	
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

# ==========================================
# FÍSICA DE TRENS, CARGAS E COLISÕES
# ==========================================
func _atualizar_visual_carga(vagao_node: ColorRect, carga: String, vazio: bool):
	for c in vagao_node.get_children():
		c.queue_free()
	if vazio:
		vagao_node.color = Color(0.3, 0.3, 0.3)
		return
		
	vagao_node.color = Color(0.2, 0.2, 0.2) 
	
	if carga == "LEITE": 
		for i in range(3):
			var c = ColorRect.new(); c.color = Color.WHITE; c.size = Vector2(10, 20)
			c.position = Vector2(4 + i*12, 5)
			vagao_node.add_child(c)
	elif carga == "MADEIRA": 
		for i in range(3):
			var c = ColorRect.new(); c.color = Color("#8b5a2b"); c.size = Vector2(32, 6)
			c.position = Vector2(4, 4 + i*8)
			vagao_node.add_child(c)
	elif carga == "TRIGO": 
		for i in range(2):
			for j in range(3):
				var c = ColorRect.new(); c.color = Color("#f5deb3"); c.size = Vector2(8, 10)
				c.position = Vector2(4 + j*12, 4 + i*12)
				vagao_node.add_child(c)
	elif carga == "ACO": 
		for i in range(2):
			var c = ColorRect.new(); c.color = Color("#a9a9a9"); c.size = Vector2(34, 10)
			c.position = Vector2(3, 4 + i*12)
			vagao_node.add_child(c)
	elif carga == "CARVAO": 
		var posicoes = [Vector2(4,4), Vector2(16,4), Vector2(28,4), Vector2(10,11), Vector2(22,11), Vector2(4,18), Vector2(16,18), Vector2(28,18)]
		for p in posicoes:
			var c = ColorRect.new(); c.color = Color("#111111"); c.size = Vector2(8, 8)
			c.position = p
			vagao_node.add_child(c)

func _processar_movimento_trens(delta):
	for id in trens_ativos.keys():
		var t = trens_ativos[id]
		if not is_instance_valid(t): continue

		var pts = t.get_meta("pontos")
		var idx = t.get_meta("indice_alvo")
		var indo = t.get_meta("indo")
		var carga = t.get_meta("carga")

		var grid_pos = Vector2i(int(t.position.x / 100), int(t.position.y / 100))
		var alvo = pts[idx]
		var alvo_grid = Vector2i(int(alvo.x / 100), int(alvo.y / 100))
		
		var parar_agora = false
		
		var tile_alvo = _get_tile_at(alvo_grid.x, alvo_grid.y)
		if tile_alvo and tile_alvo.estado_atual in [23, 24] and not tile_alvo.semaforo_aberto:
			parar_agora = true
		
		if grid_pos != alvo_grid and not parar_agora:
			var id_atual = grid_pos.x + grid_pos.y * tamanho_mapa
			var id_alvo = alvo_grid.x + alvo_grid.y * tamanho_mapa
			
			var tile_atual = _get_tile_at(grid_pos.x, grid_pos.y)
			if tile_atual and tile_atual.estado_atual == 6 and (alvo_grid.y - grid_pos.y) != 0: id_atual += 1000
			if tile_alvo and tile_alvo.estado_atual == 6 and (alvo_grid.y - grid_pos.y) != 0: id_alvo += 1000
			
			if not astar.are_points_connected(id_atual, id_alvo):
				parar_agora = true
				
		if not parar_agora and tile_alvo and tile_alvo.estado_atual in [5, 6, 7]:
			var next_idx = idx + 1 if indo else idx - 1
			if next_idx >= 0 and next_idx < pts.size():
				var prox_alvo = pts[next_idx]
				var prox_alvo_grid = Vector2i(int(prox_alvo.x / 100), int(prox_alvo.y / 100))
				
				var tile_prox = _get_tile_at(prox_alvo_grid.x, prox_alvo_grid.y)
				if tile_prox and tile_prox.estado_atual in [23, 24] and not tile_prox.semaforo_aberto:
					parar_agora = true
				else:
					var id_alvo_nav = alvo_grid.x + alvo_grid.y * tamanho_mapa
					var id_prox = prox_alvo_grid.x + prox_alvo_grid.y * tamanho_mapa
					
					if tile_alvo.estado_atual == 6 and (prox_alvo_grid.y - alvo_grid.y) != 0: id_alvo_nav += 1000
					if tile_prox and tile_prox.estado_atual == 6 and (prox_alvo_grid.y - alvo_grid.y) != 0: id_prox += 1000
					
					if not astar.are_points_connected(id_alvo_nav, id_prox):
						parar_agora = true
				
		if parar_agora:
			if t.position.distance_to(alvo) <= 80.0: 
				continue 

		var vel = 250.0 * (verba_trens / 100.0) * (verba_vias / 100.0)

		t.position = t.position.move_toward(alvo, vel * delta)

		var prev_pos = t.get_meta("prev_pos", t.position)
		if t.position.distance_squared_to(prev_pos) > 1.0:
			t.rotation = prev_pos.angle_to_point(t.position)
			t.set_meta("prev_pos", t.position)

		if t.position.distance_to(alvo) < 1.0:
			if indo:
				if idx < pts.size() - 1:
					t.set_meta("indice_alvo", idx + 1)
				else: 
					t.set_meta("indo", false)
					if pts.size() > 1: t.set_meta("indice_alvo", idx - 1)
					_atualizar_visual_carga(t.get_node("Vagao"), carga, false)
			else:
				if idx > 0:
					t.set_meta("indice_alvo", idx - 1)
				else: 
					t.set_meta("indo", true)
					if pts.size() > 1: t.set_meta("indice_alvo", 1)
					_atualizar_visual_carga(t.get_node("Vagao"), carga, true)
					
					estoque[carga] += 1
					dinheiro += recompensas[carga]
					receita_semanal += recompensas[carga]
					_spawn_floating_text(t.position, "+ $" + str(recompensas[carga]), Color.GREEN)
					_atualizar_status_bar()
					_checar_vitoria()

# --- VERIFICAÇÃO DE COLISÕES REAIS ---
func _verificar_colisoes():
	var trens_lista = trens_ativos.values()
	for i in range(trens_lista.size()):
		var t1 = trens_lista[i]
		if not is_instance_valid(t1): continue
		
		for j in range(i + 1, trens_lista.size()):
			var t2 = trens_lista[j]
			if not is_instance_valid(t2): continue

			# Trens medem 60x40. Se a distância entre o centro deles for menor que 50px, é acidente na certa.
			if t1.position.distance_to(t2.position) < 50.0:
				jogo_perdido = true
				get_tree().paused = true
				popup_game_over.popup_centered()
				return

func tentar_lancar_trem():
	if get_tree().paused == true: return 
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
			
			# ADICIONA NA FILA EM VEZ DE LANÇAR IMEDIATAMENTE
			fila_trens_pendentes.append({
				"pts": pts, "id": id, "carga": estacoes_oferta.get(d, "LEITE"), "o": principal, "d": d
			})
			# Dá um feedback visual na estação para o jogador saber que agendou a saída
			var px = principal.x * 100 + 50; var py = principal.y * 100 + 50
			_spawn_floating_text(Vector2(px, py), "AGENDADO!", Color.YELLOW)

func _spawnar_trem(pontos, id, carga, o, d):
	var t = Node2D.new(); t.name = id; t.z_index = 20; add_child(t); trens_ativos[id] = t
	
	var loc = ColorRect.new(); loc.size = Vector2(60, 40); loc.color = Color(0.1, 0.1, 0.1); 
	loc.position = Vector2(-30, -20)
	t.add_child(loc)
	
	var vag = ColorRect.new(); vag.name = "Vagao"; vag.size = Vector2(40, 30); vag.color = Color(0.3, 0.3, 0.3); 
	vag.position = Vector2(-75, -15) 
	t.add_child(vag)
	
	t.set_meta("origem", o)
	t.set_meta("destino", d)
	t.set_meta("carga", carga)
	t.set_meta("indo", true)
	t.set_meta("indice_alvo", 1)
	
	var pts = []; 
	for p in pontos: pts.append(Vector2(p.x*100 + 50, p.y*100 + 50))
	t.set_meta("pontos", pts)
	
	var pos_inicial = pts[0]
	t.set_meta("prev_pos", pos_inicial)
	t.position = pos_inicial

# ==========================================
# O PINCEL DEFINITIVO (AUTO-TILER)
# ==========================================
func _prever_pincel_magico(x, y) -> int:
	var t = _get_tile_at(x, y)
	var bioma = 2
	if t: bioma = t.base_bioma
	
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
		elif d1.y!=0 and d2.y!=0: tipo=4
		elif (d1==Vector2i(0,1) and d2==Vector2i(-1,0)) or (d2==Vector2i(0,1) and d1==Vector2i(-1,0)): tipo=18
		elif (d1==Vector2i(0,-1) and d2==Vector2i(-1,0)) or (d2==Vector2i(0,-1) and d1==Vector2i(-1,0)): tipo=19
		elif (d1==Vector2i(0,-1) and d2==Vector2i(1,0)) or (d2==Vector2i(0,-1) and d1==Vector2i(1,0)): tipo=20
		elif (d1==Vector2i(0,1) and d2==Vector2i(1,0)) or (d2==Vector2i(0,1) and d1==Vector2i(1,0)): tipo=21
	elif v.size() == 3: tipo=5
	elif v.size() == 4: tipo=6
	elif ultima_pos_pincel != Vector2i(-1, -1):
		var diff = Vector2i(x, y) - ultima_pos_pincel
		if diff.x != 0 and diff.y == 0: tipo = 3
		elif diff.y != 0 and diff.x == 0: tipo = 4
	elif v.size() == 1:
		if v[0].x != 0: tipo = 3
		else: tipo = 4
	
	if bioma == 11: 
		tipo = 12 if (tipo == 3 or tipo in [18,19,20,21,5,6]) else 13
	elif bioma == 14: 
		tipo = 15 if (tipo == 3 or tipo in [18,19,20,21,5,6]) else 16

	return tipo

func aplicar_pincel_magico(x, y):
	if x < 0 or x >= tamanho_mapa or y < 0 or y >= tamanho_mapa: return
	if matriz_mapa[x][y] in [17, 8, 10, 7, 23, 24]: return 
	
	var t = _get_tile_at(x, y)
	if t and t.estado_atual == 9 and not t.arvore_cortada: return 
	
	var tipo = _prever_pincel_magico(x, y)
	
	if matriz_mapa[x][y] != tipo:
		var tile_antigo = matriz_mapa[x][y]
		var pos_tela = Vector2(x*100+25, y*100)
		if gastar_dinheiro(tipo, pos_tela):
			if tile_antigo not in [2, 11, 14, 9, 10]: reembolsar_dinheiro(tile_antigo, pos_tela)
			matriz_mapa[x][y] = tipo
			if t: 
				t.estado_atual=tipo
				t.queue_redraw()
	
	var dirs = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
	for d in dirs:
		var nx = x + d.x
		var ny = y + d.y
		if nx >= 0 and nx < tamanho_mapa and ny >= 0 and ny < tamanho_mapa:
			var tipo_vizinho = matriz_mapa[nx][ny]
			if tipo_vizinho in [3, 4, 18, 19, 20, 21, 5, 6, 12, 13, 15, 16]:
				var novo_tipo = _prever_pincel_magico(nx, ny)
				if tipo_vizinho != novo_tipo:
					matriz_mapa[nx][ny] = novo_tipo
					var t_viz = _get_tile_at(nx, ny)
					if t_viz:
						t_viz.estado_atual = novo_tipo
						t_viz.queue_redraw()
	
	_reconstruir_malha()
	ultima_pos_pincel = Vector2i(x, y)

# ==========================================
# GERAÇÃO DE NÍVEIS E ESTAÇÕES
# ==========================================
func _get_tile_at(x, y):
	for t in mapa_node.get_children(): if t.has_method("get_grid_pos") and t.get_grid_pos() == Vector2i(x, y): return t
	return null

func _gerar_mapa_nivel_1():
	metas["LEITE"] = 3; metas["MADEIRA"] = 2
	for x in range(tamanho_mapa): _aplicar_no_mapa(x, 9, 11); _aplicar_no_mapa(x, 10, 11)
	_aplicar_no_mapa(2, 2, 17); _aplicar_estacao_oferta(17, 17, "LEITE"); _aplicar_estacao_oferta(4, 15, "MADEIRA")

func _gerar_mapa_nivel_2():
	metas["LEITE"] = 2; metas["MADEIRA"] = 4; metas["TRIGO"] = 2
	for y in range(tamanho_mapa): _aplicar_no_mapa(8, y, 11)
	_aplicar_no_mapa(17, 2, 17); _aplicar_estacao_oferta(2, 17, "LEITE"); _aplicar_estacao_oferta(2, 2, "MADEIRA"); _aplicar_estacao_oferta(17, 17, "TRIGO")

func _gerar_mapa_nivel_3():
	metas["TRIGO"] = 2; metas["ACO"] = 3; metas["CARVAO"] = 2
	for x in range(tamanho_mapa): _aplicar_no_mapa(x, 10, 11)
	for y in range(tamanho_mapa): _aplicar_no_mapa(10, y, 14)
	_aplicar_no_mapa(2, 2, 17); _aplicar_estacao_oferta(17, 2, "ACO"); _aplicar_estacao_oferta(2, 17, "CARVAO"); _aplicar_estacao_oferta(17, 17, "TRIGO")

func _aplicar_estacao_oferta(x, y, tipo): estacoes_oferta[Vector2i(x, y)] = tipo; _aplicar_no_mapa(x, y, 8)

func _aplicar_no_mapa(x, y, estado):
	matriz_mapa[x][y] = estado; var t = _get_tile_at(x, y)
	if t: t.estado_atual = estado; t.base_bioma = estado if estado in [2,11,14] else 2; t.queue_redraw()
	_reconstruir_malha()
