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
			if estado_atual == 17 or estado_atual == 8:
				if gm_ref.estado_selecionado != 0: 
					gm_ref.tentar_lancar_trem()
					return
			
			if gm_ref.estado_selecionado == 1: 
				if gm_ref.trilhos_quebrados.has(Vector2i(pos_x, pos_y)): 
					gm_ref.consertar_trilho(pos_x, pos_y)
				elif estado_atual == 7: 
					index_chave += 1
					gm_ref._reconstruir_malha()
				elif estado_atual in [23, 24]:
					semaforo_aberto = not semaforo_aberto
				elif gm_ref._eh_trilho(estado_atual) and estado_atual != 6:
					# CICLA: 0 (Limpo Duplo) -> 1 (A) -> 2 (B) -> 3 (Seta Dupla)
					sentido_via = (sentido_via + 1) % 4
					gm_ref._reconstruir_malha()
				queue_redraw()
				return 
				
			if gm_ref.estado_selecionado == 0: _apagar_tile(); return
			if gm_ref.estado_selecionado == 22: _update_brush(); return
			_aplicar_estado()
			
		if event.button_index == MOUSE_BUTTON_RIGHT: 
			if gm_ref.estado_selecionado != 1: _apagar_tile()

# ==========================================
# LÓGICA DE DIREÇÃO E PORTAS
# ==========================================
func _get_ports() -> Array:
	match estado_atual:
		3, 12, 15, 23, 25: return [Vector2i(-1, 0), Vector2i(1, 0)] 
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
	return d == p[1] if sentido_via == 1 else d == p[0]

func permite_entrada(port: Vector2i) -> bool:
	if sentido_via == 0 or sentido_via == 3: return gm_ref._tem_saida(estado_atual, port)
	var p = _get_ports()
	if p.size() < 2: return gm_ref._tem_saida(estado_atual, port)
	return port == p[0] if sentido_via == 1 else port == p[1]

# ==========================================
# VISUAL E DESENHO
# ==========================================
func _desenhar_simbolo(estado, alpha, tex_node):
	var c = Color(0, 0, 0, alpha)
	var font = get_theme_default_font()
	tex_node.texture = null
	
	if estado == 25:
		draw_rect(Rect2(0, 0, 100, 100), Color(0.4, 0.4, 0.4, alpha)) 
		for i in range(5):
			draw_line(Vector2(i*20, 0), Vector2(i*20+10, 10), Color(1, 0.8, 0, alpha), 4.0)
			draw_line(Vector2(i*20, 90), Vector2(i*20+10, 100), Color(1, 0.8, 0, alpha), 4.0)

	if estado in [3, 12, 15, 23, 25]: 
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
	
	# --- RENDERIZAÇÃO DE CRUZAMENTOS (5, 6) E CHAVES (7) ---
	if estado in [5, 6, 7]:
		var viz = []
		for d in [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]:
			var nx = pos_x + d.x; var ny = pos_y + d.y
			if gm_ref._grid_valido(nx, ny) and gm_ref._eh_trilho(gm_ref.matriz_mapa[nx][ny]): 
				viz.append(d)
		
		# Desenha os braços do cruzamento
		for d in viz:
			draw_line(Vector2(50.0, 50.0), Vector2(50.0, 50.0) + Vector2(float(d.x), float(d.y)) * 50.0, c, 8.0)
			
		if estado == 7: # CHAVE
			draw_circle(Vector2(50, 50), 16.0, c)
			if viz.size() > 0:
				var dir_viz = viz[index_chave % viz.size()] as Vector2i
				var p_arrow = Vector2(50, 50) + Vector2(float(dir_viz.x), float(dir_viz.y)) * 35.0
				_draw_arrow(Vector2(50, 50), p_arrow, Color.YELLOW)

	# --- DESENHO DE SETAS INTELIGENTES (Retas e Curvas) ---
	if gm_ref._eh_trilho(estado) and estado not in [17, 8, 6, 7, 5]:
		var ports = _get_ports()
		if ports.size() == 2:
			var port0 = ports[0] as Vector2i
			var port1 = ports[1] as Vector2i
			var p1 = Vector2(50.0, 50.0) + Vector2(float(port0.x), float(port0.y)) * 30.0
			var p2 = Vector2(50.0, 50.0) + Vector2(float(port1.x), float(port1.y)) * 30.0
			
			if sentido_via == 1: 
				_draw_arrow(p1, p2, Color.YELLOW)
			elif sentido_via == 2: 
				_draw_arrow(p2, p1, Color.YELLOW)
			elif sentido_via == 3: # SETA DUPLA EXPLÍCITA
				_draw_arrow(Vector2(50.0, 50.0), p1, Color.YELLOW)
				_draw_arrow(Vector2(50.0, 50.0), p2, Color.YELLOW)

	if estado in [23, 24]: 
		draw_circle(Vector2(50, 22) if estado==23 else Vector2(22, 50), 6, Color.GREEN if semaforo_aberto else Color.RED)
	
	if estado in [17, 8]: 
		var cor_base = Color.MAGENTA if estado == 17 else Color.GOLD
		draw_rect(Rect2(5, 5, 90, 90), cor_base)
		var texto = "BASE" if estado == 17 else gm_ref.estacoes_oferta.get(Vector2i(pos_x, pos_y), "LOG")
		draw_string(font, Vector2(10, 55), texto, HORIZONTAL_ALIGNMENT_CENTER, 80, 14, Color.WHITE)

func _draw_arrow(from: Vector2, to: Vector2, color: Color):
	draw_line(from, to, color, 4.0)
	var dir = (to - from).normalized()
	var perp = Vector2(-dir.y, dir.x) * 8.0
	var tip = to
	var p1 = to - dir * 12.0 + perp
	var p2 = to - dir * 12.0 - perp
	draw_colored_polygon(PackedVector2Array([tip, p1, p2]), color)

func _draw():
	var cor_chao = Color("#804d1a", 0.4)
	if base_bioma == 11: cor_chao = Color.DEEP_SKY_BLUE
	elif base_bioma == 14: cor_chao = Color.DARK_GRAY
	draw_rect(Rect2(Vector2.ZERO, size), cor_chao)
	_desenhar_simbolo(estado_atual, 1.0, _icon_rect)
	if mouse_em_cima: draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.1))

# --- MÉTODOS AUXILIARES E BORRACHA ---
func _update_brush(): gm_ref.aplicar_pincel_magico(pos_x, pos_y)

func _apagar_tile():
	if estado_atual in [17, 8, 25]: return 
	
	var pos_tela = Vector2(float(pos_x * 100 + 25), float(pos_y * 100))
	if estado_atual == 9 and not arvore_cortada:
		if gm_ref.has_method("cortar_arvore"):
			if gm_ref.cortar_arvore(pos_tela):
				arvore_cortada = true
				queue_redraw()
		return

	if estado_atual != base_bioma:
		gm_ref.reembolsar_dinheiro(estado_atual, pos_tela)
		estado_atual = base_bioma
		sentido_via = 0
		gm_ref.atualizar_matriz(pos_x, pos_y, estado_atual)
		
		# INFORMA OS VIZINHOS QUE O TRILHO SUMIU! (Conserta o cruzamento)
		gm_ref._atualizar_vizinhos_pincel(pos_x, pos_y)
		
		queue_redraw()
		gm_ref._reconstruir_malha()

func _aplicar_estado():
	var tool = gm_ref.estado_selecionado
	if gm_ref.gastar_dinheiro(tool, Vector2(float(pos_x*100), float(pos_y*100))):
		estado_atual = tool;
		sentido_via = 0
		gm_ref.atualizar_matriz(pos_x, pos_y, estado_atual)
		queue_redraw()
