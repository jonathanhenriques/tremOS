# camera_gestor.gd - Câmera de Mão Única com Tolerância de Arraste (Deadzone)
extends Camera2D

var target_zoom: Vector2 = Vector2.ONE
var zoom_speed: float = 0.08 
var min_zoom: float = 0.2 
var max_zoom: float = 3.0
var smooth_speed: float = 8.0 

# Variáveis para a Zona Morta do arraste
var _pos_clique_direito: Vector2
var _arrastando_camera: bool = false
var _tolerancia_arraste: float = 10.0 # Pixels de folga para não mover a tela ao apagar

func _ready():
	self.make_current()
	RenderingServer.set_default_clear_color(Color("#004d40")) 

# _input lê o movimento ANTES dos tiles, garantindo o arraste em qualquer lugar
func _input(event):
	var mouse_pos = get_viewport().get_mouse_position()
	if mouse_pos.x < 130: 
		return 

	# Registra o clique inicial
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_pos_clique_direito = event.position
				_arrastando_camera = false
			else:
				_arrastando_camera = false

	# Lógica do arraste com Tolerância
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			# Só começa a arrastar a tela se o mouse se afastar do ponto inicial do clique
			if not _arrastando_camera:
				if event.position.distance_to(_pos_clique_direito) > _tolerancia_arraste:
					_arrastando_camera = true
			
			if _arrastando_camera:
				self.global_position -= event.relative / self.zoom

# _unhandled_input lê o Zoom apenas se o game_manager não consumir a rodinha
func _unhandled_input(event):
	var mouse_pos = get_viewport().get_mouse_position()
	if mouse_pos.x < 130: 
		return 
	
	if event is InputEventMouseButton:
		if event.pressed:
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
