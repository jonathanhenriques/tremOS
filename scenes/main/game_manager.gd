# game_manager.gd
# VERSÃO FINAL COMPLETA - Sintaxe Corrigida
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

var custos_construcao = {3: 10, 4: 10, 18: 15, 19: 15, 20: 15, 21: 15, 5: 30, 6: 40, 7: 50, 12: 100, 13: 100, 15: 150, 16: 150, 23: 50, 24: 50, 25: 60}
var estacoes_oferta = {} 

var categorias = {"TRILHOS": [22, 7, 23], "BIOMAS": [2, 11, 14, 9, 10], "ESTRUTURAS": [17, 8, 25]}
var nomes_tiles = {0: "BORRACHA", 1: "SELEÇÃO", 2: "TERRA", 3: "TRILHO H", 4: "TRILHO V", 18: "┐ S-O", 19: "┘ N-O", 20: "└ N-L", 21: "┌ S-L", 5: "BIFURC. Y", 6: "CRUZAM. H", 7: "CHAVE", 17: "PRINCIPAL", 8: "ESTAÇÃO", 9: "ÁRVORE", 10: "PEDRA", 11: "ÁGUA", 14: "MONTANHA", 22: "PINCEL MÁGICO", 12: "PONTE H", 13: "PONTE V", 15: "TÚNEL H", 16: "TÚNEL V", 23: "SEMÁFORO", 24: "SEMÁFORO V", 25: "PLATAFORMA"}

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
					if event.button_index == MOUSE_BUTTON_WHEEL_UP: 
						idx = (idx - 1 + lista.size()) % lista.size()
					if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: 
						idx = (idx + 1) % lista.size()
					_selecionar_ferramenta(lista[idx])
					get_viewport().set_input_as_handled()

# ==========================================
# SISTEMA DE DIÁLOGOS E UI
# ==========================================
func _setup_dialogos():
	popup_confirmacao = ConfirmationDialog.new()
	add_child(popup_confirmacao)
	popup_confirmacao.title = "Aviso de Engenharia"
	popup_confirmacao.dialog_text = "Deseja remover esta estrutura?"
	popup_confirmacao.process_mode = Node.PROCESS_MODE_ALWAYS
	
	popup_vitoria = ConfirmationDialog.new()
	add_child(popup_vitoria)
	popup_vitoria.title = "VITÓRIA!"
	popup_vitoria.ok_button_text = "Próxima Fase"
	popup_vitoria.cancel_button_text = "Continuar"
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

	popup_relatorio = AcceptDialog.new()
	add_child(popup_relatorio)
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
	popup_orcamento = AcceptDialog.new()
	add_child(popup_orcamento)
	popup_orcamento.title = "Orçamento de Utilidades e Transportes"
	popup_orcamento.ok_button_text = "Aplicar Verbas"
	popup_orcamento.exclusive = true
	popup_orcamento.process_mode = Node.PROCESS_MODE_ALWAYS
	
	var vbox = VBoxContainer.new()
	popup_orcamento.add_child(vbox)
	
	var label_vias = Label.new()
	label_vias.text = "Despesas: Manutenção de Vias"
	vbox.add_child(label_vias)
	
	var slider_vias = HSlider.new()
	slider_vias.min_value = 0
	slider_vias.max_value = 100
	slider_vias.value = verba_vias
	vbox.add_child(slider_vias)
	
	var val_vias = Label.new()
	val_vias.text = "Verba: 100%"
	vbox.add_child(val_vias)
	
	slider_vias.value_changed.connect(func(v): 
		verba_vias = v
		val_vias.text = "Verba: " + str(v) + "%"
	)
	
	var separador = HSeparator.new()
	vbox.add_child(separador)
	
	var label_trens = Label.new()
	label_trens.text = "Despesas: Operação da Frota"
	vbox.add_child(label_trens)
	
	var slider_trens = HSlider.new()
	slider_trens.min_value = 0
	slider_trens.max_value = 100
	slider_trens.value = verba_trens
	vbox.add_child(slider_trens)
	
	var val_trens = Label.new()
	val_trens.text = "Verba: 100%"
	vbox.add_child(val_trens)
	
	slider_trens.value_changed.connect(func(v): 
		verba_trens = v
		val_trens.text = "Verba: " + str(v) + "%"
	)
	
	popup_orcamento.confirmed.connect(func(): 
		if not get_tree().paused: 
			Engine.time_scale = velocidade_jogo
	)

func _criar_ui_sistema_soko():
	var canvas = CanvasLayer.new()
	add_child(canvas)
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	
	var topo = Panel.new()
	topo.custom_minimum_size = Vector2(0, 90)
	topo.set_anchors_preset(Control.PRESET_TOP_WIDE)
	canvas.add_child(topo)
	
	info_label = Label.new()
	topo.add_child(info_label)
	info_label.position = Vector2(160, 5)
	
	var btn_orc = Button.new()
	btn_orc.text = "ORÇAMENTO"
	btn_orc.position = Vector2(20, 5)
	btn_orc.custom_minimum_size = Vector2(120, 30)
	btn_orc.add_theme_color_override("font_color", Color.YELLOW)
	btn_orc.pressed.connect(func(): popup_orcamento.popup_centered())
	topo.add_child(btn_orc)
	
	botao_pause = Button.new()
	botao_pause.text = "PAUSE"
	botao_pause.position = Vector2(20, 45)
	botao_pause.custom_minimum_size = Vector2(120, 35)
	botao_pause.pressed.connect(_alternar_pause)
	topo.add_child(botao_pause)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(850, 60)
	scroll.position = Vector2(160, 30)
	topo.add_child(scroll)
	
	sub_menu_container = HBoxContainer.new()
	scroll.add_child(sub_menu_container)
	
	var lateral = PanelContainer.new()
	lateral.custom_minimum_size = Vector2(130, 0)
	lateral.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	lateral.offset_top = 95
	canvas.add_child(lateral)
	
	var vbox = VBoxContainer.new()
	lateral.add_child(vbox)
	
	for n in ["BORRACHA", "SELEÇÃO"]:
		var b = Button.new()
		b.text = n
		b.custom_minimum_size = Vector2(110, 45)
		vbox.add_child(b)
		b.pressed.connect(_selecionar_ferramenta.bind(0 if n=="BORRACHA" else 1))
	
	for cat in categorias.keys():
		if not modo_dev and (cat == "BIOMAS" or cat == "ESTRUTURAS"): 
			continue
		var btn = Button.new()
		btn.text = cat
		btn.custom_minimum_size = Vector2(110, 45)
		btn.pressed.connect(_abrir_sub_menu.bind(cat))
		vbox.add_child(btn)
	
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
	for n in sub_menu_container.get_children(): 
		n.queue_free()
		
	for id in categorias.get(cat, []):
		if id == 24: 
			continue 
		var btn = Button.new()
		btn.text = nomes_tiles.get(id, "ITEM_" + str(id))
		btn.custom_minimum_size = Vector2(120, 35)
		btn.pressed.connect(_selecionar_ferramenta.bind(id))
		sub_menu_container.add_child(btn)

func _selecionar_ferramenta(id):
	estado_selecionado = id
	_atualizar_status_bar()

func _get_tempo_formatado() -> String:
	var minutos = int(tempo_fase / 60)
	var segundos = int(tempo_fase) % 60
	return "%02d:%02d" % [minutos, segundos]

func _atualizar_status_bar():
	if info_label: 
		var string_metas = ""
		for k in metas.keys():
			if metas[k] > 0: 
				string_metas += k.left(3) + ": " + str(estoque[k]) + "/" + str(metas[k]) + " | "
				
		var status_texto = "PLAY" if not get_tree().paused else "PLANEJAMENTO"
		
		var madeira_texto = ""
		if madeira_construcao > 0: 
			madeira_texto = " (Madeira: " + str(madeira_construcao) + ")"
		
		var nome_ferramenta = nomes_tiles.get(estado_selecionado, "PINCEL")
		info_label.text = "[%s] T: %s | $ %d%s | FASE %d | ATIVO: %s | %s" % [status_texto, _get_tempo_formatado(), dinheiro, madeira_texto, nivel_atual, nome_ferramenta, string_metas]

# ==========================================
# LÓGICA DE JOGO E ECONOMIA
# ==========================================
func cortar_arvore(pos_tela: Vector2) -> bool:
	if dinheiro < custo_multa_arvore:
		if pos_tela != Vector2.ZERO: 
			_spawn_floating_text(pos_tela, "SEM VERBA!", Color.RED)
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
	if custo == 0: 
		return true
		
	var custo_final = custo
	var usou_madeira = false
	
	if id_ferramenta in [3, 4, 18, 19, 20, 21, 5, 6, 7, 23, 24, 12, 13, 15, 16, 25] and madeira_construcao > 0:
		var desconto = 10
		if custo_final < 10: 
			desconto = custo_final
		custo_final -= desconto
		madeira_construcao -= 1
		usou_madeira = true
		
	if dinheiro < custo_final: 
		return false
		
	dinheiro -= custo_final
	_atualizar_status_bar()
	
	if pos_tela != Vector2.ZERO:
		if usou_madeira: 
			_spawn_floating_text(pos_tela + Vector2(0, 20), "-1 MADEIRA", Color("#8b5a2b"))
		if custo_final > 0: 
			_spawn_floating_text(pos_tela, "- $" + str(custo_final), Color.RED)
			
	return true

func gastar_dinheiro_especifico(valor: int, pos_tela: Vector2) -> bool:
	if dinheiro < valor: 
		return false
	dinheiro -= valor
	_atualizar_status_bar()
	if pos_tela != Vector2.ZERO: 
		_spawn_floating_text(pos_tela, "- $" + str(valor), Color.RED)
	return true

func reembolsar_dinheiro(id_ferramenta, pos_tela: Vector2):
	var valor = custos_construcao.get(id_ferramenta, 0)
	if valor > 0:
		dinheiro += valor
		_atualizar_status_bar()
		if pos_tela != Vector2.ZERO: 
			_spawn_floating_text(pos_tela, "+ $" + str(valor), Color.GREEN)

func _spawn_floating_text(pos: Vector2, txt: String, col: Color):
	var l = Label.new()
	l.text = txt
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", 22)
	l.position = pos + Vector2(randf_range(-15, 15), randf_range(-15, 15))
	l.z_index = 50
	add_child(l)
	l.process_mode = Node.PROCESS_MODE_ALWAYS
	var tw = create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS) 
	tw.tween_property(l, "position", l.position + Vector2(0,-60), 1.0)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)

func _avancar_fase():
	nivel_atual += 1
	if nivel_atual > 3: 
		nivel_atual = 1 
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
		if gastar_dinheiro_especifico(25, Vector2(float(x*100+25), float(y*100))): 
			trilhos_quebrados.erase(pos)
			_reconstruir_malha()
			var t = _get_tile_at(x, y)
			if t: 
				t.queue_redraw()

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
	tempo_fase = 0.0
	tempo_semana = 0.0
	semana_atual = 1
	receita_semanal = 0
	dinheiro = 2000 + (num * 500)
	custo_multa_arvore = 50
	madeira_construcao = 0
	trilhos_quebrados.clear()
	fila_trens_pendentes.clear()
	tempo_prox_trem = 0.0
	ignorar_colisao_timer = 0.0
	
	for k in estoque.keys(): 
		estoque[k] = 0
	for k in metas.keys(): 
		metas[k] = 0
		
	estacoes_oferta.clear()
	astar.clear()
	
	for id in trens_ativos.keys(): 
		if is_instance_valid(trens_ativos[id]): 
			trens_ativos[id].queue_free()
	trens_ativos.clear()
	
	for x in range(tamanho_mapa):
		for y in range(tamanho_mapa): 
			_aplicar_no_mapa(x, y, 2, false)
			
	if num == 1: 
		_gerar_mapa_nivel_1()
	elif num == 2: 
		_gerar_mapa_nivel_2()
	else: 
		_gerar_mapa_nivel_3()
		
	_reconstruir_malha()
	_atualizar_status_bar()

func _checar_vitoria():
	if jogo_infinito: 
		return
		
	var tem_metas = false
	var ok = true
	
	for r in metas.keys(): 
		if metas[r] > 0:
			tem_metas = true
			if estoque[r] < metas[r]: 
				ok = false
				
	if tem_metas and ok and not fase_concluida: 
		fase_concluida = true
		get_tree().paused = true 
		popup_vitoria.dialog_text = "Fase concluída em %s!" % _get_tempo_formatado()
		popup_vitoria.popup_centered()

# ==========================================
# MAPA E ASTAR
# ==========================================
func _criar_matriz_vazia():
	matriz_mapa.clear()
	for x in range(tamanho_mapa):
		matriz_mapa.append([])
		for y in range(tamanho_mapa): 
			matriz_mapa[x].append(2) 

func _criar_mapa():
	for n in mapa_node.get_children(): 
		if n.name != "LinhasDoGrid": 
			n.queue_free()
			
	for x in range(tamanho_mapa):
		for y in range(tamanho_mapa):
			var t = tile_scene.instantiate()
			t.position = Vector2(float(x*100), float(y*100))
			t.configurar(x, y, self)
			mapa_node.add_child(t)

func _configurar_grid_visual():
	var l = mapa_node.get_node_or_null("LinhasDoGrid")
	if l: 
		l.configurar(tamanho_mapa, tile_size)

func atualizar_matriz(x, y, estado):
	if x >= 0 and x < tamanho_mapa and y >= 0 and y < tamanho_mapa: 
		matriz_mapa[x][y] = estado
		_reconstruir_malha()

func _eh_trilho(tipo) -> bool:
	return tipo in [3, 4, 18, 19, 20, 21, 5, 6, 7, 12, 13, 15, 16, 23, 24, 8, 17, 25]

func _reconstruir_malha():
	astar.clear()
	for x in range(tamanho_mapa):
		for y in range(tamanho_mapa):
			var tipo = matriz_mapa[x][y]
			if not _eh_trilho(tipo): 
				continue
			if trilhos_quebrados.has(Vector2i(x,y)): 
				continue 
			astar.add_point(x + y * tamanho_mapa, Vector2(float(x), float(y)))
			if tipo == 6: 
				astar.add_point(x + y * tamanho_mapa + 1000, Vector2(float(x), float(y)))
				
	var dirs = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
	for x in range(tamanho_mapa):
		for y in range(tamanho_mapa):
			var ta = matriz_mapa[x][y]
			if not _eh_trilho(ta) or trilhos_quebrados.has(Vector2i(x,y)): 
				continue 
			for d in dirs:
				var nx = x+d.x
				var ny = y+d.y
				if nx>=0 and nx<tamanho_mapa and ny>=0 and ny<tamanho_mapa:
					var tb = matriz_mapa[nx][ny]
					if _eh_trilho(tb) and not trilhos_quebrados.has(Vector2i(nx,ny)): 
						_tentar_conectar(x,y,ta,nx,ny,tb,d)

func _tentar_conectar(ax, ay, ta, bx, by, tb, d):
	if not _tem_saida(ta, d) or not _tem_saida(tb, -d): 
		return
		
	var t_a = _get_tile_at(ax, ay)
	var t_b = _get_tile_at(bx, by)
	var pode_ir = true
	
	if t_a and t_a.has_method("permite_saida") and not t_a.permite_saida(d): 
		pode_ir = false
	if t_b and t_b.has_method("permite_entrada") and not t_b.permite_entrada(-d): 
		pode_ir = false
		
	if pode_ir:
		var ida = ax + ay * tamanho_mapa
		var idb = bx + by * tamanho_mapa
		if ta == 6 and d.y != 0: 
			ida += 1000
		if tb == 6 and d.y != 0: 
			idb += 1000
		if astar.has_point(ida) and astar.has_point(idb): 
			astar.connect_points(ida, idb, false) 

func _tem_saida(tipo, dir) -> bool:
	if tipo in [3, 12, 15, 23]: 
		return dir.x != 0
	if tipo in [4, 13, 16, 24]: 
		return dir.y != 0
	if tipo == 18: 
		return dir in [Vector2i(0, 1), Vector2i(-1, 0)]
	if tipo == 19: 
		return dir in [Vector2i(0, -1), Vector2i(-1, 0)]
	if tipo == 20: 
		return dir in [Vector2i(0, -1), Vector2i(1, 0)]
	if tipo == 21: 
		return dir in [Vector2i(0, 1), Vector2i(1, 0)]
	if tipo in [5, 6, 7, 8, 17, 25]: 
		return true 
	return false

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
			conn1 = astar.are_points_connected(id_from, avoid_id1, false)
			if conn1: 
				astar.disconnect_points(id_from, avoid_id1, false)
		if astar.has_point(id_from) and astar.has_point(avoid_id2):
			conn2 = astar.are_points_connected(id_from, avoid_id2, false)
			if conn2: 
				astar.disconnect_points(id_from, avoid_id2, false)
				
	var path_ids = astar.get_id_path(id_from, id_to)
	
	if avoid_grid != Vector2i(-1, -1):
		if conn1: 
			astar.connect_points(id_from, avoid_id1, false)
		if conn2: 
			astar.connect_points(id_from, avoid_id2, false)
			
	var pts: Array[Vector2] = []
	for pid in path_ids: 
		pts.append(astar.get_point_position(pid) * 100.0 + Vector2(50.0, 50.0))
	return pts

# ==========================================
# CÁLCULO FÍSICO DE TRENS E COLISÕES
# ==========================================
func _processar_movimento_trens(delta):
	for id in trens_ativos.keys():
		var t = trens_ativos[id]
		if not is_instance_valid(t): 
			continue

		var tempo_espera = t.get_meta("tempo_espera", 0.0)
		if tempo_espera > 0.0:
			t.set_meta("tempo_espera", tempo_espera - delta)
			continue

		var dir_atual = t.get_meta("direcao_atual")

		if dir_atual == Vector2i.ZERO:
			var grid_atual = t.get_meta("grid_atual", Vector2i(-1,-1))
			var tipo_chao = -1
			if _grid_valido(grid_atual.x, grid_atual.y):
				tipo_chao = matriz_mapa[grid_atual.x][grid_atual.y]
				
			if tipo_chao in [8, 17, 25]:
				if t.has_node("StuckAlert"):
					t.get_node("StuckAlert").queue_free()
			else:
				if not t.has_node("StuckAlert"):
					var alert = Label.new()
					alert.name = "StuckAlert"
					alert.text = "?"
					alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					alert.add_theme_font_size_override("font_size", 45)
					alert.add_theme_color_override("font_color", Color.YELLOW)
					alert.add_theme_constant_override("outline_size", 4)
					alert.add_theme_color_override("font_outline_color", Color.BLACK)
					alert.position = Vector2(-20, -80)
					alert.z_index = 51
					t.add_child(alert)
			
			_decidir_proximo_passo(t, t.get_meta("grid_atual"), t.get_meta("ultima_direcao_valida"))
			continue
		else:
			if t.has_node("StuckAlert"):
				t.get_node("StuckAlert").queue_free()

		var alvo_grid = t.get_meta("alvo_grid")
		var pos_alvo_pixel = Vector2(float(alvo_grid.x), float(alvo_grid.y)) * 100.0 + Vector2(50.0, 50.0)
		
		var vel = 250.0 * (verba_trens / 100.0) * (verba_vias / 100.0)
		t.position = t.position.move_toward(pos_alvo_pixel, vel * delta)
		
		var angulo_alvo = Vector2(float(dir_atual.x), float(dir_atual.y)).angle()
		t.rotation = lerp_angle(t.rotation, angulo_alvo, 10.0 * delta)

		if t.position.distance_to(pos_alvo_pixel) < 1.0:
			t.set_meta("grid_atual", alvo_grid)
			_decidir_proximo_passo(t, alvo_grid, dir_atual)

func _is_valid_exit(pos_grid: Vector2i, d: Vector2i, entrada: Vector2i, tile) -> bool:
	if d == -entrada: 
		return false 
	if not tile.permite_saida(d): 
		return false 
		
	var nx = pos_grid.x + d.x
	var ny = pos_grid.y + d.y
	
	if not _grid_valido(nx, ny): 
		return false
		
	var n_tipo = matriz_mapa[nx][ny]
	if not _eh_trilho(n_tipo): 
		return false
		
	var n_tile = _get_tile_at(nx, ny)
	if n_tile and n_tile.has_method("permite_entrada"):
		if not n_tile.permite_entrada(-d): 
			return false 
			
	return true

func _decidir_proximo_passo(t, grid_atual: Vector2i, dir_vinda: Vector2i):
	if not _grid_valido(grid_atual.x, grid_atual.y):
		t.set_meta("direcao_atual", Vector2i.ZERO)
		t.set_meta("ultima_direcao_valida", dir_vinda)
		return

	var tipo = matriz_mapa[grid_atual.x][grid_atual.y]
	var tile = _get_tile_at(grid_atual.x, grid_atual.y)
	
	if tipo == 25 and not t.get_meta("parada_concluida", false):
		_processar_logistica_plataforma(t)
		return

	if tipo != 25:
		t.set_meta("parada_concluida", false)

	if (tipo == 23 or tipo == 24) and tile and not tile.semaforo_aberto:
		return 

	var nova_dir = _obter_saida_fisica(tipo, dir_vinda, tile)
	
	if nova_dir == Vector2i.ZERO:
		t.set_meta("direcao_atual", Vector2i.ZERO)
		t.set_meta("ultima_direcao_valida", dir_vinda)
	else:
		t.set_meta("direcao_atual", nova_dir)
		t.set_meta("alvo_grid", grid_atual + nova_dir)
		t.set_meta("ultima_direcao_valida", nova_dir)

func _obter_saida_fisica(tipo, entrada: Vector2i, tile) -> Vector2i:
	if not tile or not tile.has_method("permite_saida"): 
		return Vector2i.ZERO

	var pos_grid = Vector2i(tile.pos_x, tile.pos_y)
	var saida_geo = Vector2i.ZERO

	if tipo == 25: 
		if _is_valid_exit(pos_grid, entrada, entrada, tile): 
			return entrada
		for d in [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]:
			if _is_valid_exit(pos_grid, d, entrada, tile): 
				return d
		return Vector2i.ZERO

	match tipo:
		3, 23: 
			saida_geo = entrada if entrada.x != 0 else Vector2i.ZERO
		4, 24: 
			saida_geo = entrada if entrada.y != 0 else Vector2i.ZERO
		18: 
			if entrada == Vector2i(0,-1): 
				saida_geo = Vector2i(-1, 0)
			elif entrada == Vector2i(1,0): 
				saida_geo = Vector2i(0, 1)
		19: 
			if entrada == Vector2i(0,1): 
				saida_geo = Vector2i(-1, 0)
			elif entrada == Vector2i(1,0): 
				saida_geo = Vector2i(0, -1)
		20: 
			if entrada == Vector2i(0,1): 
				saida_geo = Vector2i(1, 0)
			elif entrada == Vector2i(-1,0): 
				saida_geo = Vector2i(0, -1)
		21: 
			if entrada == Vector2i(0,-1): 
				saida_geo = Vector2i(1, 0)
			elif entrada == Vector2i(-1,0): 
				saida_geo = Vector2i(0, 1)
		6: 
			saida_geo = entrada 
		5, 7:
			var viz_validos = []
			for d in [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]:
				if _is_valid_exit(pos_grid, d, entrada, tile): 
					viz_validos.append(d)

			if viz_validos.size() == 0: 
				return Vector2i.ZERO
			if viz_validos.size() == 1: 
				return viz_validos[0]

			var viz_fisicos = []
			for d in [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]:
				var nx = pos_grid.x + d.x
				var ny = pos_grid.y + d.y
				if _grid_valido(nx, ny) and _eh_trilho(matriz_mapa[nx][ny]): 
					viz_fisicos.append(d)

			# === MODIFICAÇÃO INICIA AQUI ===
			# Validamos se a chave está no estado com Seta ou no novo estado "Sem Seta"
			if viz_fisicos.size() > 0:
				var idx_real = tile.index_chave % (viz_fisicos.size() + 1)
				
				# Se for menor, a seta aponta para uma direção forçada
				if idx_real < viz_fisicos.size():
					var dir_preferida = viz_fisicos[idx_real] as Vector2i
					if dir_preferida in viz_validos: 
						return dir_preferida

			# Se chegou até aqui, significa que estava no estado "Sem Seta" (idx_real == viz_fisicos.size()).
			# Nesse caso, o trem segue seu fluxo natural (em frente se puder).
			if entrada in viz_validos: 
				return entrada
			return viz_validos[0]
			# === MODIFICAÇÃO TERMINA AQUI ===

	if saida_geo != Vector2i.ZERO and _is_valid_exit(pos_grid, saida_geo, entrada, tile):
		return saida_geo
		
	return Vector2i.ZERO


func _processar_logistica_plataforma(t):
	var carga = t.get_meta("carga")
	var estado = t.get_meta("estado")
	t.set_meta("tempo_espera", 3.0)
	t.set_meta("parada_concluida", true)
	
	var grid_atual = t.get_meta("grid_atual")
	var vizinhos = _get_vizinhos_edificio(grid_atual)
	
	if vizinhos.has(8): # Estação
		if estado == "INDO": 
			t.set_meta("estado", "VOLTANDO")
			_atualizar_visual_carga(t.get_node("Vagao"), carga, false) 
			_spawn_floating_text(t.position, "CARREGADO!", Color.YELLOW)
	elif vizinhos.has(17): # Central
		if estado == "VOLTANDO": 
			t.set_meta("estado", "INDO")
			estoque[carga] += 1
			dinheiro += recompensas.get(carga, 0)
			receita_semanal += recompensas.get(carga, 0)
			_atualizar_visual_carga(t.get_node("Vagao"), carga, true) 
			_spawn_floating_text(t.position, "ENTREGUE! +$" + str(recompensas.get(carga, 0)), Color.GREEN)
			_atualizar_status_bar()
			_checar_vitoria()

func _verificar_colisoes():
	var trens_lista = trens_ativos.values()
	for i in range(trens_lista.size()):
		var t1 = trens_lista[i]
		if not is_instance_valid(t1): 
			continue
		for j in range(i + 1, trens_lista.size()):
			var t2 = trens_lista[j]
			if not is_instance_valid(t2): 
				continue
			if t1.position.distance_to(t2.position) < 50.0:
				jogo_perdido = true
				get_tree().paused = true
				popup_game_over.popup_centered()
				return

# ==========================================
# LANÇAMENTO DE TRENS
# ==========================================
func tentar_lancar_trem():
	if get_tree().paused: 
		return 
		
	var centrais: Array[Vector2i] = []
	var estacoes: Array[Vector2i] = []
	for x in range(tamanho_mapa):
		for y in range(tamanho_mapa):
			if matriz_mapa[x][y] == 17: 
				centrais.append(Vector2i(x, y))
			if matriz_mapa[x][y] == 8: 
				estacoes.append(Vector2i(x, y))
				
	if centrais.size() == 0: 
		return
	
	var p_central = _buscar_plataforma_vizinha(centrais[0])
	if p_central == Vector2i(-1, -1): 
		_spawn_floating_text(Vector2(float(centrais[0].x*100+50), float(centrais[0].y*100+50)), "FALTA PLATAFORMA!", Color.RED)
		return
		
	for est in estacoes:
		var p_est = _buscar_plataforma_vizinha(est)
		if p_est == Vector2i(-1, -1): 
			continue
		
		var path_ida = _calcular_rota_trem(p_central, p_est, Vector2i(-1, -1))
		if path_ida.size() >= 2:
			var id = "T_%d_%d_%d" % [p_est.x, p_est.y, Time.get_ticks_msec()]
			fila_trens_pendentes.append({"pts": path_ida, "id": id, "carga": estacoes_oferta.get(est, "LEITE"), "o": p_central, "d": p_est})
			_spawn_floating_text(Vector2(float(p_central.x*100+50), float(p_central.y*100+50)), "AGENDADO!", Color.YELLOW)

func _buscar_plataforma_vizinha(pos: Vector2i) -> Vector2i:
	for d in [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]:
		var n = pos + d
		if _grid_valido(n.x, n.y) and matriz_mapa[n.x][n.y] == 25: 
			return n
	return Vector2i(-1, -1)

func _spawnar_trem(pontos, id, carga, o, d):
	var t = Node2D.new()
	t.name = id
	t.z_index = 20
	add_child(t)
	trens_ativos[id] = t
	
	var loc = ColorRect.new()
	loc.size = Vector2(60, 40)
	loc.color = Color(0.1, 0.1, 0.1)
	loc.position = Vector2(-30, -20)
	t.add_child(loc)
	
	var vag = ColorRect.new()
	vag.name = "Vagao"
	vag.size = Vector2(40, 30)
	vag.color = Color(0.3, 0.3, 0.3)
	vag.position = Vector2(-75, -15)
	t.add_child(vag)
	
	t.set_meta("origem", o)
	t.set_meta("destino", d)
	t.set_meta("carga", carga)
	t.set_meta("estado", "INDO")
	t.set_meta("tempo_espera", 0.0)
	
	var p_ini = Vector2i(int(pontos[0].x/100.0), int(pontos[0].y/100.0))
	var p_next = Vector2i(int(pontos[1].x/100.0), int(pontos[1].y/100.0)) if pontos.size() > 1 else p_ini + Vector2i(1,0)
	var d_ini = p_next - p_ini
	if d_ini == Vector2i.ZERO: 
		d_ini = Vector2i(1,0)
	
	t.set_meta("grid_atual", p_ini)
	t.set_meta("alvo_grid", p_next)
	t.set_meta("direcao_atual", d_ini)
	t.set_meta("ultima_direcao_valida", d_ini)
	t.set_meta("parada_concluida", false)
	t.position = pontos[0]
	
	_atualizar_visual_carga(vag, carga, true)

func _atualizar_visual_carga(vagao, carga, vazio):
	for c in vagao.get_children(): 
		c.queue_free()
		
	vagao.color = Color(0.3, 0.3, 0.3) if vazio else Color(0.2, 0.2, 0.2)
	if not vazio:
		var c = ColorRect.new()
		c.color = cores_carga.get(carga, Color.WHITE)
		c.size = Vector2(30, 20)
		c.position = Vector2(5, 5)
		vagao.add_child(c)

func _grid_valido(x, y):
	return x >= 0 and x < tamanho_mapa and y >= 0 and y < tamanho_mapa

func _get_vizinhos_edificio(pos):
	var res = []
	for d in [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]:
		var nx = pos.x + d.x
		var ny = pos.y + d.y
		if _grid_valido(nx, ny):
			res.append(matriz_mapa[nx][ny])
	return res

# ==========================================
# PINCEL MÁGICO E AUXILIARES
# ==========================================
func _aplicar_no_mapa(x, y, estado, reconstruir = true):
	matriz_mapa[x][y] = estado
	var t = _get_tile_at(x, y)
	if t: 
		t.estado_atual = estado
	if reconstruir: 
		_reconstruir_malha()

func _aplicar_estacao_oferta(x, y, tipo, reconstruir = true): 
	estacoes_oferta[Vector2i(x, y)] = tipo
	_aplicar_no_mapa(x, y, 8, reconstruir)

func _get_tile_at(x, y):
	for t in mapa_node.get_children(): 
		if t.has_method("get_grid_pos") and t.get_grid_pos() == Vector2i(x, y): 
			return t
	return null

func _prever_pincel_magico(x, y):
	var t = _get_tile_at(x,y)
	var bioma = t.base_bioma if t else 2
	var v = []
	for d in [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]:
		var nx = x+d.x
		var ny = y+d.y
		if _grid_valido(nx, ny) and _eh_trilho(matriz_mapa[nx][ny]): 
			v.append(d)
			
	var tipo = 3 
	if v.size() == 2:
		var d1=v[0]
		var d2=v[1]
		if d1.x!=0 and d2.x!=0: 
			tipo=3
		elif d1.y!=0 and d2.y!=0: 
			tipo=4
		elif (d1==Vector2i(0,1) and d2==Vector2i(-1,0)) or (d2==Vector2i(0,1) and d1==Vector2i(-1,0)): 
			tipo=18
		elif (d1==Vector2i(0,-1) and d2==Vector2i(-1,0)) or (d2==Vector2i(0,-1) and d1==Vector2i(-1,0)): 
			tipo=19
		elif (d1==Vector2i(0,-1) and d2==Vector2i(1,0)) or (d2==Vector2i(0,-1) and d1==Vector2i(1,0)): 
			tipo=20
		elif (d1==Vector2i(0,1) and d2==Vector2i(1,0)) or (d2==Vector2i(0,1) and d1==Vector2i(1,0)): 
			tipo=21
	elif v.size() == 3: 
		tipo=5
	elif v.size() == 4: 
		tipo=6
	elif v.size() == 1: 
		tipo = 3 if v[0].x != 0 else 4
	elif v.size() == 0 and ultima_pos_pincel != Vector2i(-1, -1):
		var diff = Vector2i(x, y) - ultima_pos_pincel
		if diff.x != 0: 
			tipo = 3 
		elif diff.y != 0: 
			tipo = 4
			
	if bioma == 11: 
		tipo = 12 if tipo == 3 else 13
	elif bioma == 14: 
		tipo = 15 if tipo == 3 else 16
		
	return tipo

func _atualizar_vizinhos_pincel(x, y):
	var dirs = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
	for d in dirs:
		var nx = x + d.x
		var ny = y + d.y
		if _grid_valido(nx, ny):
			var t_viz = matriz_mapa[nx][ny]
			if _eh_trilho(t_viz) and t_viz not in [17, 8, 7, 23, 24, 25]:
				var novo_tipo = _prever_pincel_magico(nx, ny)
				if t_viz != novo_tipo:
					matriz_mapa[nx][ny] = novo_tipo
					var t_node = _get_tile_at(nx, ny)
					if t_node:
						t_node.estado_atual = novo_tipo
						t_node.queue_redraw()

func aplicar_pincel_magico(x, y):
	if not _grid_valido(x, y): 
		return
	var t_node = _get_tile_at(x, y)
	
	if t_node and t_node.estado_atual == 9 and not t_node.arvore_cortada: 
		return
	if matriz_mapa[x][y] in [17, 8, 10, 7, 23, 24, 25]: 
		return 
		
	var tipo = _prever_pincel_magico(x, y)
	
	if matriz_mapa[x][y] != tipo:
		if gastar_dinheiro(tipo, Vector2(float(x*100+25), float(y*100))):
			matriz_mapa[x][y] = tipo
			if t_node: 
				t_node.estado_atual = tipo
				t_node.queue_redraw()
			_atualizar_vizinhos_pincel(x, y)
	else:
		_atualizar_vizinhos_pincel(x, y)
		
	ultima_pos_pincel = Vector2i(x, y)
	_reconstruir_malha()

func _gerar_mapa_nivel_1():
	metas["LEITE"] = 3
	metas["MADEIRA"] = 2
	for x in range(tamanho_mapa): 
		_aplicar_no_mapa(x, 9, 11, false)
		_aplicar_no_mapa(x, 10, 11, false)
	_aplicar_no_mapa(2, 2, 17, false)
	_aplicar_no_mapa(3, 2, 25, false)
	_aplicar_estacao_oferta(17, 17, "LEITE", false)
	_aplicar_no_mapa(16, 17, 25, false)
	_aplicar_estacao_oferta(4, 15, "MADEIRA", false)
	_aplicar_no_mapa(4, 14, 25, false)

func _gerar_mapa_nivel_2():
	metas["LEITE"]=2
	metas["MADEIRA"]=4
	metas["TRIGO"]=2
	_aplicar_no_mapa(17, 2, 17, false)
	_aplicar_no_mapa(16, 2, 25, false)
	_aplicar_estacao_oferta(2, 17, "LEITE", false)
	_aplicar_no_mapa(3, 17, 25, false)
	_aplicar_estacao_oferta(2, 2, "MADEIRA", false)
	_aplicar_no_mapa(2, 3, 25, false)
	_aplicar_estacao_oferta(17, 17, "TRIGO", false)
	_aplicar_no_mapa(17, 16, 25, false)

func _gerar_mapa_nivel_3():
	metas["TRIGO"]=2
	metas["ACO"]=3
	metas["CARVAO"]=2
	_aplicar_no_mapa(2, 2, 17, false)
	_aplicar_no_mapa(2, 3, 25, false)
	_aplicar_estacao_oferta(17, 2, "ACO", false)
	_aplicar_no_mapa(17, 3, 25, false)
	_aplicar_estacao_oferta(2, 17, "CARVAO", false)
	_aplicar_no_mapa(3, 17, 25, false)
	_aplicar_estacao_oferta(17, 17, "TRIGO", false)
	_aplicar_no_mapa(16, 17, 25, false)
