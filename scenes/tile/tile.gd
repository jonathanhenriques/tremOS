# tile.gd - Interações, Borracha Inteligente e Proteção Total
extends ColorRect

var estado_atual = 2 
var base_bioma = 2 
var mouse_em_cima := false
var pos_x := 0; var pos_y := 0
var gm_ref = null
var chave_aberta := true 
var arvore_cortada := false

var _icon_rect: TextureRect
var _tex_trilho = preload("res://assets/trilho.png")

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP 
	mouse_entered.connect(func():
		mouse_em_cima = true
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and get_viewport().get_mouse_position().x > 130:
			if gm_ref.estado_selecionado == 22: _update_brush()
			elif gm_ref.estado_selecionado != 1: _aplicar_estado()
		queue_redraw())
	mouse_exited.connect(func(): mouse_em_cima = false; queue_redraw())
	_icon_rect = TextureRect.new(); _icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; _icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon_rect.pivot_offset = Vector2(50, 50); _icon_rect.modulate = Color(1, 1, 1, 0); add_child(_icon_rect)

func configurar(x, y, gm):
	pos_x = x; pos_y = y; gm_ref = gm; custom_minimum_size = Vector2(100, 100); color = Color(0, 0, 0, 0)

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
			if estado_atual == 17: gm_ref.tentar_lancar_trem(); return
			if gm_ref.estado_selecionado == 1:
				if estado_atual == 9: arvore_cortada = true 
				if estado_atual == 7: chave_aberta = not chave_aberta; gm_ref._reconstruir_malha()
				queue_redraw(); return
			if gm_ref.estado_selecionado == 22: _update_brush()
			else: _aplicar_estado()
		
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if estado_atual in [17, 8]:
				gm_ref.popup_confirmacao.popup_centered()
				if not gm_ref.popup_confirmacao.confirmed.is_connected(_confirmar_remocao):
					gm_ref.popup_confirmacao.confirmed.connect(_confirmar_remocao, CONNECT_ONE_SHOT)
			else:
				estado_atual = base_bioma
				gm_ref.atualizar_matriz(pos_x, pos_y, estado_atual); queue_redraw()

func _confirmar_remocao():
	estado_atual = base_bioma
	gm_ref.atualizar_matriz(pos_x, pos_y, estado_atual); queue_redraw()

func _aplicar_estado():
	var tool = gm_ref.estado_selecionado
	if estado_atual in [17, 8, 10]: return 
	
	if tool == 0: estado_atual = base_bioma
	else:
		if tool in [2, 11, 14]: base_bioma = tool
		if tool in [3,4,18,19,20,21,5,6,7] and (estado_atual == 9 and not arvore_cortada): return
		estado_atual = tool
	
	arvore_cortada = (estado_atual == 9 and arvore_cortada)
	gm_ref.atualizar_matriz(pos_x, pos_y, estado_atual); queue_redraw()

func _draw():
	var rect = Rect2(Vector2.ZERO, size); _icon_rect.modulate = Color(1, 1, 1, 0); var font = get_theme_default_font()
	var cor_chao = Color("#804d1a", 0.4)
	if base_bioma == 11: cor_chao = Color("#0077be")
	if base_bioma == 14: cor_chao = Color("#4b4b4b")
	draw_rect(rect, cor_chao)

	match estado_atual:
		3: _desenhar_trilho_tex(_tex_trilho, 0)
		4: _desenhar_trilho_tex(_tex_trilho, PI/2)
		18, 19, 20, 21: 
			var p1 = Vector2(50, 50); var p2 = Vector2(50, 50)
			if estado_atual == 18: p1 = Vector2(50, 100); p2 = Vector2(0, 50) 
			if estado_atual == 19: p1 = Vector2(50, 0); p2 = Vector2(0, 50)
			if estado_atual == 20: p1 = Vector2(50, 0); p2 = Vector2(100, 50)
			if estado_atual == 21: p1 = Vector2(50, 100); p2 = Vector2(100, 50)
			draw_polyline_colors(PackedVector2Array([p1, Vector2(50, 50), p2]), [Color.BLACK, Color.BLACK, Color.BLACK], 8.0, true)
		5: draw_string(font, Vector2(25, 65), "Y", HORIZONTAL_ALIGNMENT_CENTER, -1, 60, Color.BLACK)
		6: draw_string(font, Vector2(25, 65), "H", HORIZONTAL_ALIGNMENT_CENTER, -1, 60, Color.BLACK)
		7: 
			draw_rect(rect, Color(0.1, 0.5, 0.1, 0.3) if chave_aberta else Color(0.5, 0.1, 0.1, 0.3))
			draw_string(font, Vector2(35, 60), "S", HORIZONTAL_ALIGNMENT_CENTER, -1, 30, Color.WHITE)
		17: draw_rect(rect, Color("#ff00ff")); draw_rect(Rect2(10, 10, 80, 80), Color.WHITE, false, 4.0)
		8: draw_rect(rect, Color("#ffd700"))
		9: 
			if arvore_cortada: draw_circle(Vector2(50, 50), 25, Color("#d2b48c"))
			else: draw_colored_polygon(PackedVector2Array([Vector2(50, 15), Vector2(85, 85), Vector2(15, 85)]), Color("#228b22"))
		10: draw_rect(Rect2(25, 35, 50, 30), Color("#808080"))

	if mouse_em_cima: draw_rect(rect, Color(1, 1, 1, 0.2))

func _desenhar_trilho_tex(tex, rot):
	_icon_rect.texture = tex; _icon_rect.rotation = rot; _icon_rect.modulate = Color(0.1, 0.1, 0.1, 1.0)
