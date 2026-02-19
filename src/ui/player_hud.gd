extends Control

# UI References
# Joystick (Bottom Left)
@onready var joystick_base: Control = %JoystickBase
@onready var joystick_handle: Control = %JoystickHandle
@onready var indicator_up: Control = %IndicatorUp
@onready var indicator_down: Control = %IndicatorDown
@onready var indicator_left: Control = %IndicatorLeft
@onready var indicator_right: Control = %IndicatorRight

# Stats (Center)
@onready var health_label: Label = %HealthLabel
@onready var weight_label: Label = %WeightLabel
@onready var gold_label: Label = %GoldLabel
@onready var gems_label: Label = %GemsLabel
@onready var tokens_label: Label = %TokensLabel

# Settings
@export var joystick_max_distance: float = 35.0
@export var joystick_activation_threshold: float = 0.5
@export var active_color: Color = Color(0.2, 1.0, 0.2, 1.0)
@export var inactive_color: Color = Color(0.3, 0.3, 0.3, 1.0)

# Data
var health: float = 100.0
var max_health: float = 100.0
var player_body: RigidBody3D

func _ready() -> void:
	# Find player body for weight
	var player = get_tree().get_first_node_in_group("xr_player")
	if player and player.has_node("PlayerBody"):
		player_body = player.get_node("PlayerBody")
	
	# Connect to InventoryManager
	if InventoryManager:
		InventoryManager.currency_changed.connect(_on_currency_changed)
		_update_currencies()
	
	# Initial updates
	_update_stats()

func _process(_delta: float) -> void:
	_process_joystick()
	if player_body:
		_update_stats() # Update weight/health continuously or optimize? continuous is fine for now.

func _process_joystick() -> void:
	# Find movement controller (usually left)
	var controller = _get_movement_controller()
	if not controller:
		return
		
	var input = controller.get_vector2("primary")
	
	# Update Handle
	var offset = Vector2(input.x, -input.y) * joystick_max_distance
	if joystick_base and joystick_handle:
		var center = joystick_base.size / 2.0
		joystick_handle.position = center + offset - (joystick_handle.size / 2.0)
	
	# Update Indicators
	if indicator_up: _update_indicator(indicator_up, input.y > joystick_activation_threshold)
	if indicator_down: _update_indicator(indicator_down, input.y < -joystick_activation_threshold)
	if indicator_left: _update_indicator(indicator_left, input.x < -joystick_activation_threshold)
	if indicator_right: _update_indicator(indicator_right, input.x > joystick_activation_threshold)

func _update_indicator(indicator: Control, active: bool) -> void:
	indicator.modulate = active_color if active else inactive_color

func _get_movement_controller() -> XRController3D:
	# Walk up to find XRPlayer then get LeftController
	# Or just use the group
	var player = get_tree().get_first_node_in_group("xr_player")
	if player:
		# Assuming left hand is movement for now, or check PlayerMovementComponent
		# access component via player
		# For simplicity, default to LeftController
		if player.has_node("PlayerBody/XROrigin3D/LeftController"):
			return player.get_node("PlayerBody/XROrigin3D/LeftController")
	return null

func _update_stats() -> void:
	if health_label:
		health_label.text = "HP: %.0f/%0.f" % [health, max_health]
	
	if weight_label:
		var weight = 0.0
		if player_body:
			weight = player_body.mass
		weight_label.text = "Weight: %.1f kg" % weight

func _update_currencies() -> void:
	if not InventoryManager:
		return
		
	if gold_label: gold_label.text = "Gold: %d" % InventoryManager.get_currency("gold")
	if gems_label: gems_label.text = "Gems: %d" % InventoryManager.get_currency("gems")
	if tokens_label: tokens_label.text = "Tokens: %d" % InventoryManager.get_currency("tokens")

func _on_currency_changed(_type: String, _amount: int) -> void:
	_update_currencies()
