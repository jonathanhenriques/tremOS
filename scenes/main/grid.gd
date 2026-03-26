# grid.gd
extends Control

var tamanho: int = 20
var tile_size: int = 100

func configurar(novo_tamanho: int, novo_tile_size: int):
	tamanho = novo_tamanho; tile_size = novo_tile_size; z_index = 5; mouse_filter = Control.MOUSE_FILTER_IGNORE
	var area = tamanho * tile_size
	custom_minimum_size = Vector2(area, area); size = Vector2(area, area)
	queue_redraw()

func _draw():
	var largura = tamanho * tile_size; var altura = tamanho * tile_size; var font = get_theme_default_font()
	for x in range(tamanho + 1):
		var pos_x = x * tile_size; draw_line(Vector2(pos_x, 0), Vector2(pos_x, altura), Color(1, 1, 1, 0.25), 4.0)
		if x < tamanho: draw_string(font, Vector2(pos_x + 40, -15), str(x), HORIZONTAL_ALIGNMENT_CENTER, -1, 20, Color.WHITE)
	for y in range(tamanho + 1):
		var pos_y = y * tile_size; draw_line(Vector2(0, pos_y), Vector2(largura, pos_y), Color(1, 1, 1, 0.25), 4.0)
		if y < tamanho: draw_string(font, Vector2(-35, pos_y + 60), str(y), HORIZONTAL_ALIGNMENT_CENTER, -1, 20, Color.WHITE)
