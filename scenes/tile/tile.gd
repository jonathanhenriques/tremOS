# tile.gd - Consertos, Bloqueios e Visuais de Desastre
extends ColorRect

var estado_atual = 2; var base_bioma = 2; var mouse_em_cima := false; var pos_x := 0; var pos_y := 0; var gm_ref = null
var chave_aberta := true; var arvore_cortada := false; var semaforo_aberto := true 
var _icon_rect: TextureRect; var _icon_fantasma: TextureRect; var _tex_trilho = preload("res://assets/trilho.png")

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP; mouse_entered.connect(func():
		mouse_em_cima = true
		# Removida trava de Engine.time_scale para permitir feedback visual no pause
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and get_viewport().get_mouse_position().x > 130:
			if gm_ref.estado_selecionado == 22: _update_brush()
			if gm_ref.estado_selecionado != 1 and gm_ref.estado_selecionado != 22 and gm_ref.estado_selecionado != 0: _aplicar_estado()
		queue_redraw())
	mouse_exited.connect(func(): mouse_em_cima = false; queue_redraw())
	_icon_rect = TextureRect.new(); _icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; _icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT); _icon_rect.pivot_offset = Vector2(50, 50); _icon_rect.modulate = Color(1, 1, 1, 0); add_child(_icon_rect)
	_icon_fantasma = TextureRect.new(); _icon_fantasma.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; _icon_fantasma.set_anchors_preset(Control.PRESET_FULL_RECT); _icon_fantasma.pivot_offset = Vector2(50, 50); _icon_fantasma.modulate = Color(1, 1, 1, 0); add_child(_icon_fantasma)

func configurar(x, y, gm): 
	pos_x = x; pos_y = y; gm_ref = gm; custom_minimum_size = Vector2(100, 100); color = Color(0, 0, 0, 0)
	# FUNDAMENTAL: Permitir que o tile processe cliques durante o Pause
	process_mode = Node.PROCESS_MODE_ALWAYS

func get_grid_pos() -> Vector2i: return Vector2i(pos_x, pos_y)

func _update_brush():
	gm_ref.aplicar_pincel_magico(pos_x, pos_y)
	var ds = [Vector2i(0,1),Vector2i(0,-1),Vector2i(1,0),Vector2i(-1,0)]
	for d in ds:
		var n = gm_ref._get_tile_at(pos_x+d.x, pos_y+d.y)
		if n: n.queue_redraw()

func _gui_input(event):
	# Removida trava de Engine.time_scale para permitir construção no pause
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if estado_atual == 17 or estado_atual == 8:
				if gm_ref.estado_selecionado != 0: gm_ref.tentar_lancar_trem(); return
			if gm_ref.estado_selecionado == 1:
				if gm_ref.trilhos_quebrados.has(Vector2i(pos_x, pos_y)): gm_ref.consertar_trilho(pos_x, pos_y); return
				if estado_atual == 7: chave_aberta = not chave_aberta; gm_ref._reconstruir_malha(); queue_redraw()
				return
			if gm_ref.estado_selecionado == 0: _apagar_tile(); return
			if gm_ref.estado_selecionado == 22: _update_brush(); return
			_aplicar_estado()
		if event.button_index == MOUSE_BUTTON_RIGHT: _apagar_tile()

func _apagar_tile():
	if estado_atual == 17 or estado_atual == 8:
		gm_ref.popup_confirmacao.popup_centered()
		if not gm_ref.popup_confirmacao.confirmed.is_connected(_confirmar_remocao): gm_ref.popup_confirmacao.confirmed.connect(_confirmar_remocao, CONNECT_ONE_SHOT)
		return
	var pos_tela = Vector2(pos_x * 100 + 25, pos_y * 100)
	if estado_atual == 9 and not arvore_cortada:
		gm_ref.gastar_dinheiro_especifico(50, pos_tela); arvore_cortada = true; queue_redraw(); return
	if estado_atual != base_bioma:
		if gm_ref.trilhos_quebrados.has(Vector2i(pos_x, pos_y)): gm_ref.trilhos_quebrados.erase(Vector2i(pos_x, pos_y))
		gm_ref.reembolsar_dinheiro(estado_atual, pos_tela)
		estado_atual = base_bioma; gm_ref.atualizar_matriz(pos_x, pos_y, estado_atual); queue_redraw()

func _confirmar_remocao(): estado_atual = base_bioma; gm_ref.atualizar_matriz(pos_x, pos_y, estado_atual); queue_redraw()

func _aplicar_estado():
	var tool = gm_ref.estado_selecionado
	if estado_atual in [17, 8, 10] or tool == estado_atual: return 
	if tool in [2, 11, 14]: base_bioma = tool
	if tool in [12, 13] and base_bioma != 11: return
	if tool in [15, 16] and base_bioma != 14: return
	if tool in [3,4,18,19,20,21,5,6,7,23,24] and (base_bioma in [11, 14] or (estado_atual==9 and not arvore_cortada)): return
	
	if gm_ref.trilhos_quebrados.has(Vector2i(pos_x, pos_y)): gm_ref.trilhos_quebrados.erase(Vector2i(pos_x, pos_y))
	
	var pos_tela = Vector2(pos_x * 100 + 25, pos_y * 100)
	if gm_ref.gastar_dinheiro(tool, pos_tela):
		if estado_atual != base_bioma and estado_atual != 9: gm_ref.reembolsar_dinheiro(estado_atual, pos_tela + Vector2(0, 20))
		estado_atual = tool
	arvore_cortada = (estado_atual == 9 and arvore_cortada); gm_ref.atualizar_matriz(pos_x, pos_y, estado_atual); queue_redraw()

func _desenhar_simbolo(estado, alpha, tex_node):
	var c = Color(0, 0, 0, alpha); var c_white = Color(1, 1, 1, alpha); var font = get_theme_default_font(); var rect = Rect2(Vector2.ZERO, size)
	if estado in [3, 12, 15, 23]: tex_node.texture = _tex_trilho; tex_node.rotation = 0; tex_node.modulate = Color(0.1, 0.1, 0.1, alpha)
	if estado in [4, 13, 16, 24]: tex_node.texture = _tex_trilho; tex_node.rotation = PI/2; tex_node.modulate = Color(0.1, 0.1, 0.1, alpha)
	if estado in [18, 19, 20, 21]:
		var p1 = Vector2(50, 50); var p2 = Vector2(50, 50)
		if estado == 18: p1 = Vector2(50, 100); p2 = Vector2(0, 50)
		if estado == 19: p1 = Vector2(50, 0); p2 = Vector2(0, 50)
		if estado == 20: p1 = Vector2(50, 0); p2 = Vector2(100, 50)
		if estado == 21: p1 = Vector2(50, 100); p2 = Vector2(100, 50)
		draw_polyline_colors(PackedVector2Array([p1, Vector2(50, 50), p2]), [c, c, c], 8.0, true)
	if estado == 5 or estado == 6:
		var d_list = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]; var viz = []
		for d in d_list:
			var n = gm_ref._get_tile_at(pos_x + d.x, pos_y + d.y)
			if n and gm_ref._eh_trilho_ou_estacao(n.estado_atual): viz.append(d)
		if viz.size() == 0: draw_string(font, Vector2(25, 65), "Y" if estado==5 else "H", HORIZONTAL_ALIGNMENT_CENTER, -1, 60, c)
		if viz.size() > 0:
			for d in viz: draw_line(Vector2(50, 50), Vector2(50, 50) + Vector2(d.x, d.y) * 50, c, 8.0)
			draw_circle(Vector2(50, 50), 6.0, c)
	if estado == 7: draw_rect(rect, Color(0.1, 0.5, 0.1, 0.3 * alpha) if chave_aberta else Color(0.5, 0.1, 0.1, 0.3 * alpha)); draw_string(font, Vector2(35, 60), "S", HORIZONTAL_ALIGNMENT_CENTER, -1, 30, c_white)
	if estado == 23 or estado == 24: 
		draw_rect(Rect2(40, 15, 20, 15) if estado==23 else Rect2(15, 40, 15, 20), c); draw_circle(Vector2(50, 22) if estado==23 else Vector2(22, 50), 5, Color(0, 1, 0, alpha) if semaforo_aberto else Color(1, 0, 0, alpha))
	if estado == 17: draw_rect(rect, Color(1, 0, 1, alpha)); draw_rect(Rect2(10, 10, 80, 80), c_white, false, 4.0); draw_string(font, Vector2(50, 20), "CENTRAL", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, c)
	if estado == 8: draw_rect(rect, Color(1, 0.84, 0, alpha)); draw_string(font, Vector2(50, 20), "TEM " + gm_ref.estacoes_oferta.get(Vector2i(pos_x, pos_y), "N/A"), HORIZONTAL_ALIGNMENT_CENTER, -1, 12, c)
	if estado == 9: 
		if arvore_cortada: draw_circle(Vector2(50, 50), 25, Color(0.82, 0.7, 0.55, alpha))
		if not arvore_cortada: draw_colored_polygon(PackedVector2Array([Vector2(50, 15), Vector2(85, 85), Vector2(15, 85)]), Color(0.13, 0.54, 0.13, alpha))
	if estado == 10: draw_rect(Rect2(25, 35, 50, 30), Color(0.5, 0.5, 0.5, alpha))

func _draw():
	var rect = Rect2(Vector2.ZERO, size); _icon_rect.modulate = Color(1, 1, 1, 0); _icon_fantasma.modulate = Color(1, 1, 1, 0)
	var cor_chao = Color("#804d1a", 0.4)
	if base_bioma == 11: cor_chao = Color("#0077be")
	if base_bioma == 14: cor_chao = Color("#4b4b4b")
	draw_rect(rect, cor_chao)
	_desenhar_simbolo(estado_atual, 1.0, _icon_rect)
	
	if gm_ref and gm_ref.trilhos_quebrados.has(Vector2i(pos_x, pos_y)):
		draw_line(Vector2(20, 20), Vector2(80, 80), Color.RED, 8.0)
		draw_line(Vector2(80, 20), Vector2(20, 80), Color.RED, 8.0)
	
	if mouse_em_cima: 
		draw_rect(rect, Color(1, 1, 1, 0.2))
		if estado_atual not in [17, 8, 10]:
			var sel = gm_ref.estado_selecionado
			if sel not in [0, 1]:
				var prev = sel
				if sel == 22: prev = gm_ref._prever_pincel_magico(pos_x, pos_y)
				if prev != estado_atual: _desenhar_simbolo(prev, 0.4, _icon_fantasma)
