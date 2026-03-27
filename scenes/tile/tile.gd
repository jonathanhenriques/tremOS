# tile.gd - Interações, Borracha e Proteção Total (SEM ELIF)
extends ColorRect

var estado_atual = 2; var base_bioma = 2; var mouse_em_cima := false; var pos_x := 0; var pos_y := 0; var gm_ref = null
var chave_aberta := true; var arvore_cortada := false; var semaforo_aberto := true 
var _icon_rect: TextureRect; var _tex_trilho = preload("res://assets/trilho.png")

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP; mouse_entered.connect(func():
		mouse_em_cima = true
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and get_viewport().get_mouse_position().x > 130:
			if gm_ref.estado_selecionado == 22: _update_brush()
			if gm_ref.estado_selecionado != 1 and gm_ref.estado_selecionado != 22 and gm_ref.estado_selecionado != 0: _aplicar_estado()
		queue_redraw())
	mouse_exited.connect(func(): mouse_em_cima = false; queue_redraw())
	_icon_rect = TextureRect.new(); _icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; _icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon_rect.pivot_offset = Vector2(50, 50); _icon_rect.modulate = Color(1, 1, 1, 0); add_child(_icon_rect)

func configurar(x, y, gm): pos_x = x; pos_y = y; gm_ref = gm; custom_minimum_size = Vector2(100, 100); color = Color(0, 0, 0, 0)
func get_grid_pos() -> Vector2i: return Vector2i(pos_x, pos_y)
func _update_brush():
	gm_ref.aplicar_pincel_magico(pos_x, pos_y)
	var ds = [Vector2i(0,1),Vector2i(0,-1),Vector2i(1,0),Vector2i(-1,0)]
	for d in ds:
		var n = gm_ref._get_tile_at(pos_x+d.x, pos_y+d.y)
		if n: n.queue_redraw()

func _gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# PROTEÇÃO: Se for estação, lança o trem e retorna (não constrói por cima)
			if estado_atual == 17 or estado_atual == 8:
				if gm_ref.estado_selecionado != 0:
					gm_ref.tentar_lancar_trem()
					return
			
			if gm_ref.estado_selecionado == 1: # SELEÇÃO
				if estado_atual == 7: chave_aberta = not chave_aberta; gm_ref._reconstruir_malha(); queue_redraw()
				return
			if gm_ref.estado_selecionado == 0: # BORRACHA
				_apagar_tile(); return
			if gm_ref.estado_selecionado == 22: # PINCEL
				_update_brush(); return
			
			_aplicar_estado() # CONSTRUÇÃO NORMAL
			
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_apagar_tile()

func _apagar_tile():
	if estado_atual == 17 or estado_atual == 8:
		gm_ref.popup_confirmacao.popup_centered()
		if not gm_ref.popup_confirmacao.confirmed.is_connected(_confirmar_remocao): gm_ref.popup_confirmacao.confirmed.connect(_confirmar_remocao, CONNECT_ONE_SHOT)
		return
	
	var pos_tela = Vector2(pos_x * 100 + 25, pos_y * 100)
	if estado_atual == 9 and not arvore_cortada:
		# Extração paga de árvore
		if gm_ref.dinheiro >= 50:
			gm_ref.dinheiro -= 50; gm_ref._atualizar_status_bar(); gm_ref._spawn_floating_text(pos_tela, "- $50", Color.RED)
			arvore_cortada = true; queue_redraw()
		return
	if estado_atual != base_bioma:
		gm_ref.reembolsar_dinheiro(estado_atual, pos_tela)
		estado_atual = base_bioma; gm_ref.atualizar_matriz(pos_x, pos_y, estado_atual); queue_redraw()

func _confirmar_remocao():
	estado_atual = base_bioma; gm_ref.atualizar_matriz(pos_x, pos_y, estado_atual); queue_redraw()

# APLICAÇÃO DE ESTADO PROTEGIDA CONTRA SOBREPOSIÇÃO
func _aplicar_estado():
	var tool = gm_ref.estado_selecionado
	if estado_atual in [17, 8, 10] or tool == estado_atual: return # BLOQUEIO TOTAL
	
	if tool == 0: 
		estado_atual = base_bioma
	if tool != 0:
		if tool in [2, 11, 14]: base_bioma = tool
		if tool in [12, 13] and base_bioma != 11: return
		if tool in [15, 16] and base_bioma != 14: return
		if tool in [3,4,18,19,20,21,5,6,7,23,24] and (base_bioma in [11, 14] or (estado_atual==9 and not arvore_cortada)): return
		
		var pos_tela = Vector2(pos_x * 100 + 25, pos_y * 100)
		if gm_ref.gastar_dinheiro(tool, pos_tela):
			if estado_atual != base_bioma and estado_atual != 9: gm_ref.reembolsar_dinheiro(estado_atual, pos_tela + Vector2(0, 20))
			estado_atual = tool
		
	arvore_cortada = (estado_atual == 9 and arvore_cortada); gm_ref.atualizar_matriz(pos_x, pos_y, estado_atual); queue_redraw()

func _draw():
	var rect = Rect2(Vector2.ZERO, size); _icon_rect.modulate = Color(1, 1, 1, 0); var font = get_theme_default_font()
	var cor_chao = Color("#804d1a", 0.4)
	if base_bioma == 11: cor_chao = Color("#0077be")
	if base_bioma == 14: cor_chao = Color("#4b4b4b")
	draw_rect(rect, cor_chao)
	if estado_atual in [3, 12, 15, 23]: _desenhar_trilho_tex(_tex_trilho, 0)
	if estado_atual in [4, 13, 16, 24]: _desenhar_trilho_tex(_tex_trilho, PI/2)
	if estado_atual in [18, 19, 20, 21]:
		var p1 = Vector2(50, 50); var p2 = Vector2(50, 50)
		if estado_atual == 18: p1 = Vector2(50, 100); p2 = Vector2(0, 50) 
		if estado_atual == 19: p1 = Vector2(50, 0); p2 = Vector2(0, 50)
		if estado_atual == 20: p1 = Vector2(50, 0); p2 = Vector2(100, 50)
		if estado_atual == 21: p1 = Vector2(50, 100); p2 = Vector2(100, 50)
		draw_polyline_colors(PackedVector2Array([p1, Vector2(50, 50), p2]), [Color.BLACK, Color.BLACK, Color.BLACK], 8.0, true)
	if estado_atual == 5: draw_string(font, Vector2(25, 65), "Y", HORIZONTAL_ALIGNMENT_CENTER, -1, 60, Color.BLACK)
	if estado_atual == 6: draw_string(font, Vector2(25, 65), "H", HORIZONTAL_ALIGNMENT_CENTER, -1, 60, Color.BLACK)
	if estado_atual == 7: draw_rect(rect, Color(0.1, 0.5, 0.1, 0.3) if chave_aberta else Color(0.5, 0.1, 0.1, 0.3)); draw_string(font, Vector2(35, 60), "S", HORIZONTAL_ALIGNMENT_CENTER, -1, 30, Color.WHITE)
	if estado_atual == 23: draw_rect(Rect2(40, 15, 20, 15), Color.BLACK); draw_circle(Vector2(50, 22), 5, Color.GREEN if semaforo_aberto else Color.RED)
	if estado_atual == 24: draw_rect(Rect2(15, 40, 15, 20), Color.BLACK); draw_circle(Vector2(22, 50), 5, Color.GREEN if semaforo_aberto else Color.RED)
	if estado_atual == 17: draw_rect(rect, Color("#ff00ff")); draw_rect(Rect2(10, 10, 80, 80), Color.WHITE, false, 4.0); draw_string(font, Vector2(50, 20), "CENTRAL", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.BLACK)
	if estado_atual == 8: draw_rect(rect, Color("#ffd700")); draw_string(font, Vector2(50, 20), "TEM " + gm_ref.estacoes_oferta.get(Vector2i(pos_x, pos_y), "N/A"), HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.BLACK)
	if estado_atual == 9: 
		if arvore_cortada: draw_circle(Vector2(50, 50), 25, Color("#d2b48c"))
		if not arvore_cortada: draw_colored_polygon(PackedVector2Array([Vector2(50, 15), Vector2(85, 85), Vector2(15, 85)]), Color("#228b22"))
	if estado_atual == 10: draw_rect(Rect2(25, 35, 50, 30), Color("#808080"))
	if mouse_em_cima: draw_rect(rect, Color(1, 1, 1, 0.2))

func _desenhar_trilho_tex(tex, rot): _icon_rect.texture = tex; _icon_rect.rotation = rot; _icon_rect.modulate = Color(0.1, 0.1, 0.1, 1.0)
