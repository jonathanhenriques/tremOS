# tile.gd - Versão com Visual de Plataforma (ID 25)
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
var sentido_via: int = 0 

var _icon_rect: TextureRect
var _icon_fantasma: TextureRect
var _tex_trilho = preload("res://assets/trilho.png")

# ==========================================
# CONFIGURAÇÃO INICIAL E SINAIS
# ==========================================
func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func():
		mouse_em_cima = true
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and get_viewport().get_mouse_position().x > 130:
			if gm_ref.estado_selecionado == 22: 
				_update_brush()
			elif gm_ref.estado_selecionado == 0: 
				_apagar_tile()
			elif gm_ref.estado_selecionado != 1: 
				_aplicar_estado()
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
	pos_x = x
	pos_y = y
	gm_ref = gm
	custom_minimum_size = Vector2(100, 100)
	color = Color(0, 0, 0, 0)
	process_mode = Node.PROCESS_MODE_ALWAYS

func get_grid_pos() -> Vector2i: 
	return Vector2i(pos_x, pos_y)

# ==========================================
# LÓGICA DE INTERAÇÃO
# ==========================================
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
					queue_redraw()
				elif estado_atual in [23, 24]:
					semaforo_aberto = not semaforo_aberto
					queue_redraw() 
				elif estado_atual in [3, 4, 18, 19, 20, 21, 12, 13, 15, 16, 25]:
					sentido_via = (sentido_via + 1) % 3
					gm_ref._reconstruir_malha()
					queue_redraw()
				return 
				
			if gm_ref.estado_selecionado == 0: 
				_apagar_tile()
				return
			if gm_ref.estado_selecionado == 22: 
				_update_brush()
				return
				
			_aplicar_estado()
			
		if event.button_index == MOUSE_BUTTON_RIGHT: 
			if gm_ref.estado_selecionado != 1: 
				_apagar_tile()

func is_direction_closed(d: Vector2i) -> bool:
	if estado_atual != 7: return false
	var d_list = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
	var viz = []
	for dir in d_list:
		var n = gm_ref._get_tile_at(pos_x + dir.x, pos_y + dir.y)
		if n and gm_ref._eh_trilho(n.estado_atual): viz.append(dir)
	
	if viz.size() > 2:
		var fechado_idx = index_chave % viz.size()
		if viz[fechado_idx] == d:
			return true
	return false

func _get_ports() -> Array:
	if estado_atual in [3, 12, 15, 23]: return [Vector2i(-1, 0), Vector2i(1, 0)]
	if estado_atual in [4, 13, 16, 24]: return [Vector2i(0, -1), Vector2i(0, 1)]
	if estado_atual == 18: return [Vector2i(0, 1), Vector2i(-1, 0)]
	if estado_atual == 19: return [Vector2i(-1, 0), Vector2i(0, -1)]
	if estado_atual == 20: return [Vector2i(0, -1), Vector2i(1, 0)]
	if estado_atual == 21: return [Vector2i(1, 0), Vector2i(0, 1)]
	if estado_atual == 25: return [Vector2i(-1,0), Vector2i(1,0), Vector2i(0,-1), Vector2i(0,1)]
	return []

func permite_saida(d: Vector2i) -> bool:
	if sentido_via == 0: return gm_ref._tem_saida(estado_atual, d)
	var p = _get_ports()
	if p.size() < 2: return gm_ref._tem_saida(estado_atual, d)
	
	if sentido_via == 1: return d == p[1] 
	if sentido_via == 2: return d == p[0] 
	return false

func permite_entrada(port: Vector2i) -> bool:
	if sentido_via == 0: return gm_ref._tem_saida(estado_atual, port)
	var p = _get_ports()
	if p.size() < 2: return gm_ref._tem_saida(estado_atual, port)
	
	if sentido_via == 1: return port == p[0] 
	if sentido_via == 2: return port == p[1] 
	return false

# ==========================================
# MÉTODOS DE AÇÃO
# ==========================================
func _update_brush():
	gm_ref.aplicar_pincel_magico(pos_x, pos_y)
	queue_redraw()
	var ds = [Vector2i(0,1), Vector2i(0,-1), Vector2i(1,0), Vector2i(-1,0)]
	for d in ds:
		var n = gm_ref._get_tile_at(pos_x + d.x, pos_y + d.y)
		if n: n.queue_redraw()

func _apagar_tile():
	if estado_atual in [17, 8, 7, 23, 24, 25]:
		if not gm_ref.popup_confirmacao.visible:
			var nome_item = "esta estrutura"
			if estado_atual in [17, 8]: nome_item = "este edifício"
			elif estado_atual == 25: nome_item = "esta plataforma"
			gm_ref.popup_confirmacao.dialog_text = "Deseja remover " + nome_item + "?"
			gm_ref.popup_confirmacao.popup_centered()
			if gm_ref.popup_confirmacao.confirmed.is_connected(_confirmar_remocao):
				gm_ref.popup_confirmacao.confirmed.disconnect(_confirmar_remocao)
			gm_ref.popup_confirmacao.confirmed.connect(_confirmar_remocao)
		return
		
	var pos_tela = Vector2(pos_x * 100 + 25, pos_y * 100)
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
		queue_redraw()
		gm_ref._reconstruir_malha()

func _confirmar_remocao(): 
	estado_atual = base_bioma
	sentido_via = 0
	gm_ref.atualizar_matriz(pos_x, pos_y, estado_atual)
	gm_ref._reconstruir_malha()
	queue_redraw()

func _obter_semaforo_inteligente() -> int:
	if estado_atual in [4, 13, 16]: return 24
	return 23

func _aplicar_estado():
	var tool = gm_ref.estado_selecionado
	if tool == 23: tool = _obter_semaforo_inteligente()
	if estado_atual in [17, 8, 10] or tool == estado_atual: return 
	
	var pos_tela = Vector2(pos_x * 100 + 25, pos_y * 100)
	if gm_ref.gastar_dinheiro(tool, pos_tela):
		if estado_atual != base_bioma and estado_atual != 9: 
			gm_ref.reembolsar_dinheiro(estado_atual, pos_tela + Vector2(0, 20))
		sentido_via = 0 
		estado_atual = tool
	
	gm_ref.atualizar_matriz(pos_x, pos_y, estado_atual)
	queue_redraw()

# ==========================================
# VISUAL E DESENHO
# ==========================================
func _desenhar_simbolo(estado, alpha, tex_node):
	var c = Color(0, 0, 0, alpha);
	var font = get_theme_default_font();
	
	# --- VISUAL DA PLATAFORMA (ID 25) ---
	if estado == 25:
		draw_rect(Rect2(0, 0, 100, 100), Color(0.4, 0.4, 0.4, alpha)) # Base cinza
		# Listras de alerta amarelas (Soko Style)
		for i in range(5):
			draw_line(Vector2(i*20, 0), Vector2(i*20+10, 10), Color(1, 0.8, 0, alpha), 4.0)
			draw_line(Vector2(i*20, 90), Vector2(i*20+10, 100), Color(1, 0.8, 0, alpha), 4.0)
		# Desenha um trilho horizontal simples por cima
		draw_line(Vector2(0, 45), Vector2(100, 45), c, 4.0)
		draw_line(Vector2(0, 55), Vector2(100, 55), c, 4.0)

	if estado in [3, 12, 15, 23]: tex_node.texture = _tex_trilho; tex_node.rotation = 0; tex_node.modulate = Color(0.1, 0.1, 0.1, alpha)
	if estado in [4, 13, 16, 24]: tex_node.texture = _tex_trilho; tex_node.rotation = PI/2; tex_node.modulate = Color(0.1, 0.1, 0.1, alpha)
	
	if estado in [18, 19, 20, 21]:
		var p1 = Vector2(50, 50); var p2 = Vector2(50, 50)
		if estado == 18: p1 = Vector2(50, 100); p2 = Vector2(0, 50)
		if estado == 19: p1 = Vector2(50, 0); p2 = Vector2(0, 50)
		if estado == 20: p1 = Vector2(50, 0); p2 = Vector2(100, 50)
		if estado == 21: p1 = Vector2(50, 100); p2 = Vector2(100, 50)
		draw_polyline_colors(PackedVector2Array([p1, Vector2(50, 50), p2]), [c, c, c], 8.0, true)
	
	if estado in [5, 6, 7]:
		var d_list = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)];
		var viz = []
		for d in d_list:
			var n = gm_ref._get_tile_at(pos_x + d.x, pos_y + d.y)
			if n and gm_ref._eh_trilho(n.estado_atual): viz.append(d)
		for d in viz: draw_line(Vector2(50, 50), Vector2(50, 50) + Vector2(d.x, d.y) * 50, c, 8.0)
		if estado == 7: draw_circle(Vector2(50, 50), 16.0, c)

	if estado == 23 or estado == 24: 
		draw_circle(Vector2(50, 22) if estado==23 else Vector2(22, 50), 5, Color(0, 1, 0, alpha) if semaforo_aberto else Color(1, 0, 0, alpha))
	
	if estado in [17, 8]: 
		var cor_base = Color(1, 0, 1, alpha) if estado == 17 else Color(1, 0.84, 0, alpha)
		draw_rect(Rect2(5, 5, 90, 90), cor_base)
		var texto = "CENTRAL" if estado == 17 else gm_ref.estacoes_oferta.get(Vector2i(pos_x, pos_y), "N/A")
		draw_string(font, Vector2(50, 55), texto, HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color(1,1,1,alpha))

func _draw():
	var rect = Rect2(Vector2.ZERO, size)
	_icon_rect.modulate = Color(1, 1, 1, 0)
	_icon_fantasma.modulate = Color(1, 1, 1, 0)
	var cor_chao = Color("#804d1a", 0.4)
	if base_bioma == 11: cor_chao = Color("#0077be")
	if base_bioma == 14: cor_chao = Color("#4b4b4b")
	draw_rect(rect, cor_chao)
	_desenhar_simbolo(estado_atual, 1.0, _icon_rect)
	
	if mouse_em_cima: 
		draw_rect(rect, Color(1, 1, 1, 0.2))
		if estado_atual not in [17, 8, 10]:
			var sel = gm_ref.estado_selecionado
			if sel not in [0, 1]:
				var prev = sel
				if sel == 22: prev = gm_ref._prever_pincel_magico(pos_x, pos_y)
				_desenhar_simbolo(prev, 0.4, _icon_fantasma)
