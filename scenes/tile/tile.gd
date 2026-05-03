# tile.gd
extends ColorRect

# --- VARIÁVEIS DE ESTADO E REFERÊNCIAS ---
var estado_atual: int = 2
var base_bioma: int = 2
var mouse_em_cima: bool = false
var pos_x: int = 0
var pos_y: int = 0
var gm_ref = null

var index_chave: int = 0
var arvore_cortada: bool = false
var semaforo_aberto: bool = true 
var sentido_via: int = 0 # 0: Sem Seta (Mão Dupla), 1: Sentido A, 2: Sentido B, 3: Seta Dupla

var _icon_rect: TextureRect
var _icon_fantasma: TextureRect
var _tex_trilho = preload("res://assets/trilho.png")

# ==========================================
# CONFIGURAÇÃO E INTERAÇÃO
# ==========================================
func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func():
		mouse_em_cima = true
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and get_viewport().get_mouse_position().x > 130:
			if gm_ref.estado_selecionado == 22: _update_brush()
			elif gm_ref.estado_selecionado == 0: _apagar_tile()
			elif gm_ref.estado_selecionado != 1: _aplicar_estado()
		queue_redraw()
	)
	mouse_exited.connect(func(): 
		mouse_em_cima = false
		queue_redraw()
	)
	
	_icon_rect = TextureRect.new()
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon_rect.pivot_offset = Vector2(50, 50)
	_icon_rect.modulate = Color(1, 1, 1, 0)
	add_child(_icon_rect)
	
	_icon_fantasma = TextureRect.new()
	_icon_fantasma.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_fantasma.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon_fantasma.pivot_offset = Vector2(50, 50)
	_icon_fantasma.modulate = Color(1, 1, 1, 0)
	add_child(_icon_fantasma)

func configurar(x, y, gm): 
	pos_x = x;
	pos_y = y; gm_ref = gm
	custom_minimum_size = Vector2(100, 100)
	color = Color(0, 0, 0, 0)
	process_mode = Node.PROCESS_MODE_ALWAYS

func get_grid_pos() -> Vector2i: return Vector2i(pos_x, pos_y)

func _gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			
			# Se estivermos com a ferramenta de Lançar Trem (27), usamos a lógica de spawn
			if gm_ref.estado_selecionado == 27:
				gm_ref.lancar_trem_manual(pos_x, pos_y)
				return
			
			# Lógica de Seleção (ID 1) e Conserto de Trilhos [cite: 45, 46]
			if gm_ref.estado_selecionado == 1: 
				if gm_ref.trilhos_quebrados.has(Vector2i(pos_x, pos_y)): 
					gm_ref.consertar_trilho(pos_x, pos_y)
				elif estado_atual in [23, 24]:
					semaforo_aberto = not semaforo_aberto
				elif gm_ref._eh_trilho(estado_atual) and estado_atual != 6:
					if estado_atual in [5, 7]:
						var v_reais = _get_vizinhos_trilho()
						var max_estados = (v_reais.size() * 2) + 1
						if max_estados > 1:
							index_chave = (index_chave + 1) % max_estados
					else:
						sentido_via = (sentido_via + 1) % 6
					gm_ref._reconstruir_malha()
				queue_redraw()
				return 
				
			# Lógica de Apagar (ID 0) ou Pincel Mágico (ID 22) [cite: 47]
			if gm_ref.estado_selecionado == 0: _apagar_tile(); return
			if gm_ref.estado_selecionado == 22: _update_brush(); return
			
			# Bloqueio para não construir sobre Prédios Principais
			if estado_atual in [17, 8]: return
			
			# Aplica a ferramenta atual (Biomas, Estruturas ou Spawn de Trem)
			_aplicar_estado()
			
		if event.button_index == MOUSE_BUTTON_RIGHT: 
			if gm_ref.estado_selecionado != 1: _apagar_tile()

# ==========================================
# LÓGICA DE DIREÇÃO E PORTAS (CORRIGIDA)
# ==========================================

func _get_ports() -> Array:
	match estado_atual:
		3, 12, 15, 23: return [Vector2i(-1, 0), Vector2i(1, 0)] 
		4, 13, 16, 24: return [Vector2i(0, -1), Vector2i(0, 1)] 
		18: return [Vector2i(0, 1), Vector2i(-1, 0)] 
		19: return [Vector2i(-1, 0), Vector2i(0, -1)] 
		20: return [Vector2i(0, -1), Vector2i(1, 0)] 
		21: return [Vector2i(1, 0), Vector2i(0, 1)] 
	return []

func permite_saida(d: Vector2i) -> bool:
	if sentido_via == 0 or sentido_via == 3: return gm_ref._tem_saida(estado_atual, d)
	var p = _get_ports()
	if p.size() < 2: return gm_ref._tem_saida(estado_atual, d)
	if sentido_via == 1 or sentido_via == 4: return d == p[1] 
	if sentido_via == 2 or sentido_via == 5: return d == p[0]
	return false

func permite_entrada(port: Vector2i) -> bool:
	if sentido_via == 0 or sentido_via == 3: return gm_ref._tem_saida(estado_atual, port)
	var p = _get_ports()
	if p.size() < 2: return gm_ref._tem_saida(estado_atual, port)
	if sentido_via == 1 or sentido_via == 4: return port == p[0] 
	if sentido_via == 2 or sentido_via == 5: return port == p[1]
	return false



# ==========================================
# VISUAL E DESENHO
# ==========================================
func _get_vizinhos_trilho() -> Array:
	var v = []
	for d in [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]:
		var nx = pos_x + d.x
		var ny = pos_y + d.y
		if gm_ref._grid_valido(nx, ny) and gm_ref._eh_trilho(gm_ref.matriz_mapa[nx][ny]):
			# === NOVA CLÁUSULA VISUAL ===
			# O desenho só conecta se o vizinho tiver uma saída apontando para cá
			var tipo_viz = gm_ref.matriz_mapa[nx][ny]
			if gm_ref._tem_saida(tipo_viz, -d):
				v.append(d)
			# ============================
	return v


func _desenhar_simbolo(estado, alpha, tex_node):
	var c = Color(0, 0, 0, alpha)
	var font = get_theme_default_font()
	tex_node.texture = null
	
	if estado in [3, 12, 15, 23]: 
		tex_node.texture = _tex_trilho; tex_node.rotation = 0; tex_node.modulate = Color(0.1, 0.1, 0.1, alpha)
	if estado in [4, 13, 16, 24]: 
		tex_node.texture = _tex_trilho; tex_node.rotation = PI/2; tex_node.modulate = Color(0.1, 0.1, 0.1, alpha)
	
	if estado in [18, 19, 20, 21]:
		var p1 = Vector2(50, 50); var p2 = Vector2(50, 50)
		if estado == 18: p1 = Vector2(50, 100); p2 = Vector2(0, 50)
		elif estado == 19: p1 = Vector2(50, 0); p2 = Vector2(0, 50)
		elif estado == 20: p1 = Vector2(50, 0); p2 = Vector2(100, 50)
		elif estado == 21: p1 = Vector2(50, 100); p2 = Vector2(100, 50)
		draw_polyline_colors(PackedVector2Array([p1, Vector2(50, 50), p2]), [c, c, c], 8.0, true)
	
	if estado in [5, 6, 7]:
		var v_reais = _get_vizinhos_trilho()
		for d in v_reais:
			draw_line(Vector2(50.0, 50.0), Vector2(50.0, 50.0) + Vector2(float(d.x), float(d.y)) * 50.0, c, 8.0)
		
		if estado in [5, 7]:
			draw_circle(Vector2(50, 50), 16.0, c)
			if v_reais.size() > 0:
				var qtd_saidas = v_reais.size()
				if index_chave < qtd_saidas:
					var dir_viz = v_reais[index_chave]
					_draw_arrow(Vector2(50, 50), Vector2(50, 50) + Vector2(float(dir_viz.x), float(dir_viz.y)) * 35.0, Color.YELLOW)
				elif index_chave == qtd_saidas:
					pass
				else:
					var idx_azul = index_chave - qtd_saidas - 1
					var dir_viz = v_reais[idx_azul]
					_draw_arrow(Vector2(50, 50), Vector2(50, 50) + Vector2(float(dir_viz.x), float(dir_viz.y)) * 35.0, Color.CYAN)

	if estado not in [17, 8, 5, 6, 7] and gm_ref._eh_trilho(estado):
		var v_reais = _get_vizinhos_trilho()
		if v_reais.size() == 2:
			var p1 = Vector2(50.0, 50.0) + Vector2(float(v_reais[0].x), float(v_reais[0].y)) * 30.0
			var p2 = Vector2(50.0, 50.0) + Vector2(float(v_reais[1].x), float(v_reais[1].y)) * 30.0
			if sentido_via == 1: _draw_arrow(p1, p2, Color.YELLOW)
			elif sentido_via == 2: _draw_arrow(p2, p1, Color.YELLOW)
			elif sentido_via == 3: 
				_draw_arrow(Vector2(50,50), p1, Color.YELLOW); _draw_arrow(Vector2(50,50), p2, Color.YELLOW)
			elif sentido_via == 4: _draw_arrow(p1, p2, Color.CYAN)
			elif sentido_via == 5: _draw_arrow(p2, p1, Color.CYAN)

	if estado in [23, 24]: 
		draw_circle(Vector2(50, 22) if estado==23 else Vector2(22, 50), 6, Color.GREEN if semaforo_aberto else Color.RED)
	
	# --- VISUAL COLORIDO DAS ESTAÇÕES ---
	if estado in [17, 8]: 
		var cor_base = Color.MAGENTA if estado == 17 else Color.GOLD
		
		# Se for uma Estação (8), tentamos pegar a cor da carga que ela oferece
		if estado == 8:
			var tipo_carga = gm_ref.estacoes_oferta.get(Vector2i(pos_x, pos_y), "")
			if tipo_carga != "":
				cor_base = gm_ref.cores_carga.get(tipo_carga, Color.GOLD)
		
		draw_rect(Rect2(5, 5, 90, 90), cor_base)
		var texto = "BASE" if estado == 17 else gm_ref.estacoes_oferta.get(Vector2i(pos_x, pos_y), "LOG")
		draw_string(font, Vector2(10, 55), texto, HORIZONTAL_ALIGNMENT_CENTER, 80, 14, Color.WHITE)


func _draw_arrow(from: Vector2, to: Vector2, color: Color):
	draw_line(from, to, color, 4.0)
	var dir = (to - from).normalized()
	var perp = Vector2(-dir.y, dir.x) * 8.0
	draw_colored_polygon(PackedVector2Array([to, to - dir * 12.0 + perp, to - dir * 12.0 - perp]), color)

func _draw():
	var cor_chao = Color("#804d1a", 0.4)
	if base_bioma == 11: cor_chao = Color.DEEP_SKY_BLUE
	elif base_bioma == 14: cor_chao = Color.DARK_GRAY
	draw_rect(Rect2(Vector2.ZERO, size), cor_chao)
	_desenhar_simbolo(estado_atual, 1.0, _icon_rect)
	if mouse_em_cima: draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.1))

func _update_brush(): gm_ref.aplicar_pincel_magico(pos_x, pos_y)



func _apagar_tile():
	if estado_atual in [17, 8]: return 
	gm_ref.reembolsar_dinheiro(estado_atual, Vector2(float(pos_x*100), float(pos_y*100)))
	estado_atual = base_bioma
	gm_ref.atualizar_matriz(pos_x, pos_y, estado_atual)
	gm_ref._atualizar_vizinhos_pincel(pos_x, pos_y)
	queue_redraw()
	gm_ref._reconstruir_malha()




func _aplicar_estado():
	var tool = gm_ref.estado_selecionado
	
	if tool == 27:
		gm_ref.lancar_trem_manual(pos_x, pos_y)
		return
	
	if gm_ref.gastar_dinheiro(tool, Vector2(float(pos_x*100), float(pos_y*100))):
		estado_atual = tool
		gm_ref.atualizar_matriz(pos_x, pos_y, estado_atual)
		
		# NOVA LÓGICA: Se for estação (ID 8), aplica a carga selecionada no menu Dev
		if tool == 8:
			var carga_meta = gm_ref.get_meta("carga_pincel_atual", "LEITE")
			gm_ref.estacoes_oferta[Vector2i(pos_x, pos_y)] = carga_meta
		
		queue_redraw()



func disparar_gatilho_inteligente():
	# --- NOVA LÓGICA PARA CHAVES E BIFURCAÇÕES (INVERSÃO DE EIXO) ---
	if estado_atual in [5, 7]:
		var v_reais = _get_vizinhos_trilho()
		var qtd_saidas = v_reais.size()
		
		# Verifica se estamos no estado de Seta Azul (index_chave > qtd_saidas)
		if qtd_saidas > 0 and index_chave > qtd_saidas:
			var idx_azul_atual = index_chave - qtd_saidas - 1
			var dir_atual = v_reais[idx_azul_atual]
			
			# Calculamos a direção exatamente oposta (Inversão de Eixo)
			var dir_oposta = -dir_atual # Ex: (0, -1) vira (0, 1)
			
			# Procuramos se essa direção oposta existe fisicamente nesta chave
			var novo_idx_azul = v_reais.find(dir_oposta)
			
			# Se a saída oposta existir, invertemos! 
			# Se não existir (ex: uma chave em 'T' sem o outro lado do eixo), ela permanece onde está.
			if novo_idx_azul != -1:
				index_chave = qtd_saidas + 1 + novo_idx_azul
				queue_redraw()
			
	# --- LÓGICA PARA TRILHOS RETOS/CURVAS (MANTIDA) ---
	elif gm_ref._eh_trilho(estado_atual) and estado_atual not in [6, 25]:
		# Inverte entre os estados 4 (Azul A) e 5 (Azul B)
		if sentido_via == 4:
			sentido_via = 5
			queue_redraw()
		elif sentido_via == 5:
			sentido_via = 4
			queue_redraw()
			
			
			
			
