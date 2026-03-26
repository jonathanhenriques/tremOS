# camera_gestor.gd - Movimentação RTS
extends Camera2D

var target_zoom: Vector2 = Vector2.ONE
var zoom_speed: float = 0.15
var min_zoom: float = 0.2 
var max_zoom: float = 3.0
var smooth_speed: float = 10.0

func _ready():
	self.make_current()
	RenderingServer.set_default_clear_color(Color("#004d40")) 

func _input(event):
	var mouse_pos = get_viewport().get_mouse_position()
	if mouse_pos.x < 130: return # Bloqueia pan/zoom na barra lateral

	# MOVIMENTAÇÃO: Botão direito agarra e move
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			self.global_position -= event.relative / self.zoom

	# ZOOM: Apenas com CTRL pressionado (Pedido do Usuário)
	if event is InputEventMouseButton:
		if event.is_pressed() and Input.is_key_pressed(KEY_CTRL):
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_ajustar_target_zoom(zoom_speed)
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_ajustar_target_zoom(-zoom_speed)

func _ajustar_target_zoom(delta):
	target_zoom += Vector2(delta, delta)
	target_zoom = target_zoom.clamp(Vector2(min_zoom, min_zoom), Vector2(max_zoom, max_zoom))

func _process(delta):
	var mouse_pos_antes = get_global_mouse_position()
	self.zoom = self.zoom.lerp(target_zoom, smooth_speed * delta)
	var mouse_pos_depois = get_global_mouse_position()
	self.global_position += (mouse_pos_antes - mouse_pos_depois)
