# game_manager.gd - Sistema Blindado com Conexão Direta nas Estações
extends Node2D

# --- CONFIGURAÇÕES GERAIS E EXPORTS ---
@export var tamanho_mapa: int = 20
@export var tile_size: int = 100
@export var velocidade_jogo: float = 1.0

@export var modo_dev: bool = true 

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
var estado_selecionado = 22 
var astar = AStar2D.new()
var trens_ativos = {}
var jogo_perdido: bool = false
var fase_concluida := false
var jogo_infinito := false 
var nivel_atual: int = 1
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

# --- GESTÃO AMBIENTAL ---
var custo_multa_arvore: int = 50
var madeira_construcao: int = 0

# --- TEMPO ---
var tempo_fase: float = 0.0
var tempo_semana: float = 0.0
var duracao_semana: float = 30.0 
var semana_atual: int = 1
var receita_semanal: int = 0 

# --- DICIONÁRIOS E RECURSOS ---
var estoque = {"LEITE": 0, "MADEIRA": 0, "TRIGO": 0, "ACO": 0, "CARVAO": 0}
var metas = {"LEITE": 0, "MADEIRA": 0, "TRIGO": 0, "ACO": 0, "CARVAO": 0}
var recompensas = {"LEITE": 200, "MADEIRA": 150, "TRIGO": 180, "ACO": 300, "CARVAO": 250}
var cores_carga = {"LEITE": Color.WHITE, "MADEIRA": Color("#8b5a2b"), "TRIGO": Color("#f5deb3"), "ACO": Color("#a9a9a9"), "CARVAO": Color("#2f4f4f")}

# REMOVIDO O TILO 25 DOS CUSTOS
var custos_construcao = {3: 10, 4: 10, 18: 15, 19: 15, 20: 15, 21: 15, 5: 30, 6: 40, 7: 50, 12: 100, 13: 100, 15: 150, 16: 150, 23: 50, 24: 50}
var estacoes_oferta = {} 

# REMOVIDO O TILO 25 DAS CATEGORIAS E NOMES
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
			
			if fila_trens_pendentes.size() > 0:
				tempo_prox_trem -= delta
				if tempo_prox_trem <= 0.0:
					var trem_data = fila_trens_pendentes.pop_front()
					_spawnar_trem(trem_data.pts, trem_data.id, trem_data.carga, trem_data.o, trem_data.d)
					tempo_prox_trem = 2.0
			
			_processar_movimento_trens(delta)
			
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
	popup_vitoria.process_mode = Node.PROCESS_MODE_ALWAYS
	
	popup_vitoria.confirmed.connect(func():
		get_tree().paused = false
		_avancar_fase()
	)
	popup_vitoria.canceled.connect(func():
		fase_concluida = false
		jogo_infinito = true
		get_tree().paused = false
	)

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
	
	if modo_dev:
		var btn_dev = popup_game_over.add_button("Modo Dev: Ignorar", false, "continuar_dev")
		btn_dev.pressed.connect(func():
			jogo_perdido = false
			get_tree().paused = false
			ignorar_colisao_timer = 3.0
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
		
		var madeira_texto = ""
		if madeira_construcao > 0: madeira_texto = " (Madeira: " + str(madeira_construcao) + ")"
		
		info_label.text = "[%s] T: %s | $ %d%s | FASE %d | ATIVO: %s | %s" % [status_texto, _get_tempo_formatado(), dinheiro, madeira_texto, nivel_atual, nomes_tiles[estado_selecionado], string_metas]

# ==========================================
# LÓGICA DE JOGO, PROGRESSÃO E ECONOMIA
# ==========================================
func cortar_arvore(pos_tela: Vector2) -> bool:
	if dinheiro < custo_multa_arvore:
		if pos_tela != Vector2.ZERO: _spawn_floating_text(pos_tela, "SEM VERBA!", Color.RED)
		return false

	dinheiro -= custo_multa_arvore
	madeira_construcao += 1

	if pos_tela != Vector2.ZERO:
		_spawn_floating_text(pos_tela, "MULTA: -$" + str(custo_multa_arvore), Color.RED)
		_spawn_floating_text(pos_tela + Vector2(0, 25), "+1 MADEIRA", Color("#8b5a2b"))

	custo_multa_arvore += 50 
	_atualizar_status_bar()
	return true

func gastar_dinheiro(id_ferramenta, pos_tela: Vector2 = Vector2.ZERO) -> bool:
	var custo = custos_construcao.get(id_ferramenta, 0)
	if custo == 0: return true
	
	var custo_final = custo
	var usou_madeira = false

	# Removido ID 25 daqui também
	if id_ferramenta in [3, 4, 18, 19, 20, 21, 5, 6, 7, 23, 24, 12, 13, 15, 16] and madeira_construcao > 0:
		var desconto = 10
		if custo_final < 10: desconto = custo_final
		custo_final -= desconto
		madeira_construcao -= 1
		usou_madeira = true

	if dinheiro < custo_final: return false

	dinheiro -= custo_final
	_atualizar_status_bar()

	if pos_tela != Vector2.ZERO:
		if usou_madeira:
			_spawn_floating_text(pos_tela + Vector2(0, 20), "-1 MADEIRA", Color("#8b5a2b"))
		if custo_final > 0:
			_spawn_floating_text(pos_tela, "- $" + str(custo_final), Color.RED)

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
	var custo_trilhos_ideal = 10.0
	var custo_trilhos_real = int(custo_trilhos_ideal * (verba_vias / 100.0))
	
	var qtd_trens = trens_ativos.size()
	var custo_trens_ideal = qtd_trens * 10.0 
	var custo_trens_real = int(custo_trens_ideal * (verba_trens / 100.0))
	
	var custo_total = custo_trilhos_real + custo_trens_real
	dinheiro -= custo_total 
	
	var texto = "RESUMO DA SEMANA " + str(semana_atual) + "\n\n"
	texto += "Vias: - $" + str(custo_trilhos_real) + "\n"
	texto += "Trens: - $" + str(custo_trens_real) + "\n"
	texto += "Receita: + $" + str(receita_semanal) + "\n"
	texto += "--------------------------------------\n"
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
	fase_concluida = false
	jogo_perdido = false
	jogo_infinito = false
	tempo_fase = 0.0; tempo_semana = 0.0; semana_atual = 1; receita_semanal = 0
	dinheiro = 2000 + (num * 500)
	
	custo_multa_arvore = 50
	madeira_construcao = 0
	
	trilhos_quebrados.clear()
	fila_trens_pendentes.clear()
	tempo_prox_trem = 0.0
	ignorar_colisao_timer = 0.0
	
	for k in estoque.keys(): estoque[k] = 0; metas[k] = 0
	estacoes_oferta.clear(); astar.clear()
	for id in trens_ativos.keys(): if is_instance_valid(trens_ativos[id]): trens_ativos[id].queue_free()
	trens_ativos.clear()
	
	for x in range(tamanho_mapa):
		for y in range(tamanho_mapa): _aplicar_no_mapa(x, y, 2, false)
		
	if num == 1: _gerar_mapa_nivel_1()
	if num == 2: _gerar_mapa_nivel_2()
	if num == 3: _gerar_mapa_nivel_3()
	
	_reconstruir_malha()
	_atualizar_status_bar()

func _checar_vitoria():
	if jogo_infinito: return
	
	var tem_metas = false
	var ok = true
	for r in metas.keys(): 
		if metas[r] > 0:
			tem_metas = true
			if estoque[r] < metas[r]: ok = false
				
	if tem_metas and ok and not fase_concluida: 
		fase_concluida = true
		get_tree().paused = true 
		popup_vitoria.dialog_text = "Fase concluída em %s!" % _get_tempo_formatado()
		popup_vitoria.popup_centered()

# ==========================================
# MAPA E AStar2D (CONEXÃO DIRETA)
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

# ATUALIZADO: Agora 17 (Central) e 8 (Estação) SÃO considerados pontos válidos na rota!
func _eh_trilho(tipo) -> bool:
	return tipo in [3, 4, 18, 19, 20, 21, 5, 6, 7, 12, 13, 15, 16, 23, 24, 8, 17]

func _reconstruir_malha():
	astar.clear()
	for x in range(tamanho_mapa):
		for y in range(tamanho_mapa):
			var tipo = matriz_mapa[x][y]
			if not _eh_trilho(tipo): continue
			
			if trilhos_quebrados.has(Vector2i(x,y)): continue 
			
			astar.add_point(x + y * tamanho_mapa, Vector2(x, y))
			if tipo == 6: astar.add_point(x + y * tamanho_mapa + 1000, Vector2(x, y))
	
	var dirs = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
	for x in range(tamanho_mapa):
		for y in range(tamanho_mapa):
			var ta = matriz_mapa[x][y]
			if not _eh_trilho(ta) or trilhos_quebrados.has(Vector2i(x,y)): continue 
			for d in dirs:
				var nx = x+d.x; var ny = y+d.y
				if nx>=0 and nx<tamanho_mapa and ny>=0 and ny<tamanho_mapa:
					var tb = matriz_mapa[nx][ny]
					if _eh_trilho(tb) and not trilhos_quebrados.has(Vector2i(nx,ny)): 
						_tentar_conectar(x,y,ta,nx,ny,tb,d)

func _tentar_conectar(ax, ay, ta, bx, by, tb, d):
	if not _tem_saida(ta, d) or not _tem_saida(tb, -d): return
	
	var t_a = _get_tile_at(ax, ay)
	var t_b = _get_tile_at(bx, by)
	
	var pode_ir = true
	if t_a and t_a.has_method("permite_saida"):
		if not t_a.permite_saida(d): pode_ir = false
	if t_b and t_b.has_method("permite_entrada"):
		if not t_b.permite_entrada(-d): pode_ir = false
	if t_a and t_a.has_method("is_direction_closed") and t_a.is_direction_closed(d): pode_ir = false
	if t_b and t_b.has_method("is_direction_closed") and t_b.is_direction_closed(-d): pode_ir = false
	
	if pode_ir:
		var ida = ax + ay * tamanho_mapa; var idb = bx + by * tamanho_mapa
		if ta == 6 and d.y != 0: ida += 1000
		if tb == 6 and d.y != 0: idb += 1000
		if astar.has_point(ida) and astar.has_point(idb): 
			astar.connect_points(ida, idb, false) 

# ATUALIZADO: 17 e 8 agora aceitam saídas (e entradas) por todos os lados!
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
# CÁLCULO DE ROTAS (TIPAGEM FORTE)
# ==========================================
func _calcular_rota_trem(origem_grid: Vector2i, destino_grid: Vector2i, avoid_grid: Vector2i) -> Array[Vector2]:
	var id_from = origem_grid.x + origem_grid.y * tamanho_mapa
	var id_to = destino_grid.x + destino_grid.y * tamanho_mapa
	var avoid_id1 = -1
	var avoid_id2 = -1
	var conn1 = false
	var conn2 = false

	if avoid_grid != Vector2i(-1, -1):
		avoid_id1 = avoid_grid.x + avoid_grid.y * tamanho_mapa
		avoid_id2 = avoid_id1 + 1000
		if astar.has_point(id_from) and astar.has_point(avoid_id1):
			conn1 = astar.are_points_connected(id_from, avoid_id1)
			if conn1: astar.disconnect_points(id_from, avoid_id1)
		if astar.has_point(id_from) and astar.has_point(avoid_id2):
			conn2 = astar.are_points_connected(id_from, avoid_id2)
			if conn2: astar.disconnect_points(id_from, avoid_id2)

	var path_ids = astar.get_id_path(id_from, id_to)

	if avoid_grid != Vector2i(-1, -1):
		if conn1: astar.connect_points(id_from, avoid_id1, false)
		if conn2: astar.connect_points(id_from, avoid_id2, false)

	var pts: Array[Vector2] = []
	for pid in path_ids:
		pts.append(astar.get_point_position(pid) * 100.0 + Vector2(50.0, 50.0))
	return pts

# ==========================================
# FÍSICA DE TRENS E COLISÕES
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

		var pts: Array[Vector2] = t.get_meta("pontos")
		var idx: int = t.get_meta("indice_alvo")
		var estado_viagem = t.get_meta("estado")
		var carga = t.get_meta("carga")
		var tempo_espera = t.get_meta("tempo_espera", 0.0)

		if tempo_espera > 0.0:
			tempo_espera -= delta
			if tempo_espera <= 0.0:
				var from = Vector2i(int(t.position.x/100.0), int(t.position.y/100.0))
				var to = t.get_meta("origem") if estado_viagem == "VOLTANDO" else t.get_meta("destino")
				
				var avoid = Vector2i(-1, -1)
				if t.has_meta("last_grid_pos"):
					avoid = t.get_meta("last_grid_pos")

				var new_path = _calcular_rota_trem(from, to, avoid)
				if new_path.size() >= 2:
					t.set_meta("pontos", new_path)
					t.set_meta("indice_alvo", 1)
					t.set_meta("tempo_espera", 0.0)
					pts = new_path
					idx = 1
				else:
					t.set_meta("tempo_espera", 2.0) 
					_spawn_floating_text(t.position, "FALTA SAÍDA (BOLSÃO)!", Color.RED)
					continue 
			else:
				t.set_meta("tempo_espera", tempo_espera)
				continue 

		var grid_pos = Vector2i(int(t.position.x / 100.0), int(t.position.y / 100.0))
		var alvo: Vector2 = pts[idx]
		var alvo_grid = Vector2i(int(alvo.x / 100.0), int(alvo.y / 100.0))
		
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
			
			if not astar.are_points_connected(id_atual, id_alvo, false):
				parar_agora = true
				
		if not parar_agora and tile_alvo and tile_alvo.estado_atual in [5, 6, 7]:
			var next_idx = idx + 1
			if next_idx < pts.size():
				var prox_alvo: Vector2 = pts[next_idx]
				var prox_alvo_grid = Vector2i(int(prox_alvo.x / 100.0), int(prox_alvo.y / 100.0))
				var tile_prox = _get_tile_at(prox_alvo_grid.x, prox_alvo_grid.y)
				if tile_prox and tile_prox.estado_atual in [23, 24] and not tile_prox.semaforo_aberto:
					parar_agora = true
				else:
					var id_alvo_nav = alvo_grid.x + alvo_grid.y * tamanho_mapa
					var id_prox = prox_alvo_grid.x + prox_alvo_grid.y * tamanho_mapa
					if tile_alvo.estado_atual == 6 and (prox_alvo_grid.y - alvo_grid.y) != 0: id_alvo_nav += 1000
					if tile_prox and tile_prox.estado_atual == 6 and (prox_alvo_grid.y - alvo_grid.y) != 0: id_prox += 1000
					
					if not astar.are_points_connected(id_alvo_nav, id_prox, false):
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
			if idx < pts.size() - 1:
				t.set_meta("indice_alvo", idx + 1)
			else:
				t.set_meta("tempo_espera", 2.0)
				
				var idx_pts = pts.size() - 2
				if idx_pts >= 0:
					var p_pts: Vector2 = pts[idx_pts]
					t.set_meta("last_grid_pos", Vector2i(int(p_pts.x / 100.0), int(p_pts.y / 100.0)))
				else:
					t.set_meta("last_grid_pos", Vector2i(-1, -1))

				if estado_viagem == "INDO":
					t.set_meta("estado", "VOLTANDO")
					_atualizar_visual_carga(t.get_node("Vagao"), carga, false)
				else:
					t.set_meta("estado", "INDO")
					_atualizar_visual_carga(t.get_node("Vagao"), carga, true)
					
					estoque[carga] += 1
					dinheiro += recompensas[carga]
					receita_semanal += recompensas[carga]
					_spawn_floating_text(t.position, "+ $" + str(recompensas[carga]), Color.GREEN)
					_atualizar_status_bar()
					_checar_vitoria()

func _verificar_colisoes():
	var trens_lista = trens_ativos.values()
	for i in range(trens_lista.size()):
		var t1 = trens_lista[i]
		if not is_instance_valid(t1): continue
		
		for j in range(i + 1, trens_lista.size()):
			var t2 = trens_lista[j]
			if not is_instance_valid(t2): continue

			if t1.position.distance_to(t2.position) < 50.0:
				jogo_perdido = true
				get_tree().paused = true
				popup_game_over.popup_centered()
				return

# --- VALIDAÇÃO EXTREMA COM CONEXÃO DIRETA NAS ESTAÇÕES ---
func tentar_lancar_trem():
	if get_tree().paused: return 
	
	var centrais: Array[Vector2i] = []
	var estacoes: Array[Vector2i] = []
	for x in range(tamanho_mapa):
		for y in range(tamanho_mapa):
			if matriz_mapa[x][y] == 17: centrais.append(Vector2i(x, y))
			if matriz_mapa[x][y] == 8: estacoes.append(Vector2i(x, y))
			
	if centrais.size() == 0: return
	var principal: Vector2i = centrais[0]
	
	for est in estacoes:
		# Agora a origem e destino SÃO a própria central e a própria estação!
		var path_ida: Array[Vector2] = _calcular_rota_trem(principal, est, Vector2i(-1, -1))
		if path_ida.size() >= 2:
			var p_ida: Vector2 = path_ida[path_ida.size() - 2]
			var avoid_volta = Vector2i(int(p_ida.x / 100.0), int(p_ida.y / 100.0))
			
			var path_volta: Array[Vector2] = _calcular_rota_trem(est, principal, avoid_volta)

			if path_volta.size() >= 2:
				var p_volta: Vector2 = path_volta[path_volta.size() - 2]
				var avoid_ida2 = Vector2i(int(p_volta.x / 100.0), int(p_volta.y / 100.0))
				
				var path_ida2: Array[Vector2] = _calcular_rota_trem(principal, est, avoid_ida2)

				if path_ida2.size() >= 2:
					var id = "T_%d_%d_%d" % [est.x, est.y, Time.get_ticks_msec()]
					fila_trens_pendentes.append({
						"pts": path_ida, "id": id, "carga": estacoes_oferta.get(est, "LEITE"), "o": principal, "d": est
					})
					_spawn_floating_text(Vector2(principal.x * 100.0 + 50.0, principal.y * 100.0 + 50.0), "AGENDADO!", Color.YELLOW)
				else:
					_spawn_floating_text(Vector2(principal.x * 100.0 + 50.0, principal.y * 100.0 + 50.0), "FALTA BOLSÃO NA CENTRAL!", Color.RED)
			else:
				_spawn_floating_text(Vector2(est.x * 100.0 + 50.0, est.y * 100.0 + 50.0), "FALTA BOLSÃO NA ESTAÇÃO!", Color.RED)
		else:
			_spawn_floating_text(Vector2(principal.x * 100.0 + 50.0, principal.y * 100.0 + 50.0), "SEM ROTA LIGADA!", Color.RED)

func _spawnar_trem(pontos: Array[Vector2], id, carga, o, d):
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
	t.set_meta("estado", "INDO")
	t.set_meta("tempo_espera", 0.0)
	t.set_meta("last_grid_pos", o)
	t.set_meta("indice_alvo", 1)
	
	var pts: Array[Vector2] = pontos.duplicate()
	t.set_meta("pontos", pts)
	
	var pos_inicial: Vector2 = pts[0]
	t.set_meta("prev_pos", pos_inicial)
	t.position = pos_inicial

# ==========================================
# O PINCEL DEFINITIVO E O RESTANTE DO CÓDIGO
# ==========================================
func _aplicar_no_mapa(x, y, estado, reconstruir = true):
	matriz_mapa[x][y] = estado; var t = _get_tile_at(x, y)
	if t: t.estado_atual = estado; t.base_bioma = estado if estado in [2,11,14] else 2; t.queue_redraw()
	if reconstruir: _reconstruir_malha()

func _aplicar_estacao_oferta(x, y, tipo, reconstruir = true): 
	estacoes_oferta[Vector2i(x, y)] = tipo; 
	_aplicar_no_mapa(x, y, 8, reconstruir)

func _prever_pincel_magico(x, y) -> int:
	var t = _get_tile_at(x, y)
	var bioma = 2
	if t: bioma = t.base_bioma
	
	var dirs = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
	var v = []
	for d in dirs:
		var n = Vector2i(x,y)+d
		if n.x>=0 and n.x<tamanho_mapa and n.y>=0 and n.y<tamanho_mapa:
			if _eh_trilho(matriz_mapa[n.x][n.y]): v.append(d)
			
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
# GERAÇÃO DE NÍVEIS (REMOVIDO TILO 25)
# ==========================================
func _get_tile_at(x, y):
	for t in mapa_node.get_children(): if t.has_method("get_grid_pos") and t.get_grid_pos() == Vector2i(x, y): return t
	return null

func _gerar_mapa_nivel_1():
	metas["LEITE"] = 3; metas["MADEIRA"] = 2
	for x in range(tamanho_mapa): _aplicar_no_mapa(x, 9, 11, false); _aplicar_no_mapa(x, 10, 11, false)
	_aplicar_no_mapa(2, 2, 17, false)
	_aplicar_estacao_oferta(17, 17, "LEITE", false)
	_aplicar_estacao_oferta(4, 15, "MADEIRA", false)

func _gerar_mapa_nivel_2():
	metas["LEITE"] = 2; metas["MADEIRA"] = 4; metas["TRIGO"] = 2
	for y in range(tamanho_mapa): _aplicar_no_mapa(8, y, 11, false)
	_aplicar_no_mapa(17, 2, 17, false)
	_aplicar_estacao_oferta(2, 17, "LEITE", false)
	_aplicar_estacao_oferta(2, 2, "MADEIRA", false)
	_aplicar_estacao_oferta(17, 17, "TRIGO", false)

func _gerar_mapa_nivel_3():
	metas["TRIGO"] = 2; metas["ACO"] = 3; metas["CARVAO"] = 2
	for x in range(tamanho_mapa): _aplicar_no_mapa(x, 10, 11, false)
	for y in range(tamanho_mapa): _aplicar_no_mapa(10, y, 14, false)
	_aplicar_no_mapa(2, 2, 17, false)
	_aplicar_estacao_oferta(17, 2, "ACO", false)
	_aplicar_estacao_oferta(2, 17, "CARVAO", false)
	_aplicar_estacao_oferta(17, 17, "TRIGO", false)
