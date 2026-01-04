extends Control

signal visibility_toggle_requested(collider_name: String)

@onready var left_strength_vbox = $MainVBox/StrengthsHBox/LeftVBox
@onready var right_strength_vbox = $MainVBox/StrengthsHBox/RightVBox
@onready var signals_grid = $MainVBox/SignalsGrid

func _ready():
	# Connect buttons
	$MainVBox/TogglesHBox/LeftMesh.pressed.connect(func(): visibility_toggle_requested.emit("LeftHandMesh"))
	$MainVBox/TogglesHBox/LeftCapsules.pressed.connect(func(): visibility_toggle_requested.emit("LeftHandCapsules"))
	$MainVBox/TogglesHBox/RightMesh.pressed.connect(func(): visibility_toggle_requested.emit("RightHandMesh"))
	$MainVBox/TogglesHBox/RightCapsules.pressed.connect(func(): visibility_toggle_requested.emit("RightHandCapsules"))

func set_pinch_strength(hand: int, finger_name: String, value: float) -> void:
	var container = left_strength_vbox if hand == 0 else right_strength_vbox
	var bar = container.get_node_or_null(finger_name)
	if bar and bar is ProgressBar:
		bar.value = value * 100.0

func set_discrete_signal(hand: int, signal_name: String, active: bool) -> void:
	var prefix = "L_" if hand == 0 else "R_"
	var indicator = signals_grid.get_node_or_null(prefix + signal_name)
	if indicator and indicator is ColorRect:
		indicator.color = Color.GREEN if active else Color.DARK_RED
