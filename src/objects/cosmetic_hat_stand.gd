extends StaticBody3D
class_name CosmeticHatStand

const CosmeticVisuals = preload("res://src/systems/cosmetic_visuals.gd")

@export var item_id: String = "hat_basic_red"
@export var rotation_speed: float = 45.0 # Degrees per second
@export var float_speed: float = 2.0
@export var float_amplitude: float = 0.05
@export var interact_cooldown_sec: float = 0.3

@onready var status_label: Label3D = $Geometry/Console/StatusLabel
@onready var preview_anchor: Node3D = $RotatingPlatform/Mannequin/HeadMesh/PreviewAnchor
@onready var poke_button: PokeableButton = $Geometry/Console/PokeableButton
@onready var rotating_platform: Node3D = $RotatingPlatform
@onready var mannequin_grid_painter: GridPainter = $MannequinGridPainter

var _cooldown_until_msec: int = 0


func _ready() -> void:
	collision_layer = 32
	collision_mask = 0
	
	if mannequin_grid_painter:
		mannequin_grid_painter.load_grid_data("res://assets/textures/grid_painter_surfaces.json")
		mannequin_grid_painter.refresh_all_surfaces()
	
	_setup_preview_mesh()
	_refresh_status_label()

	if poke_button:
		poke_button.pressed.connect(_on_button_pressed)

	if CosmeticsManager and CosmeticsManager.has_signal("cosmetics_changed"):
		CosmeticsManager.cosmetics_changed.connect(_refresh_status_label)
	if CosmeticsManager and CosmeticsManager.has_signal("purchase_processed"):
		CosmeticsManager.purchase_processed.connect(_on_purchase_processed)
	if InventoryManager and InventoryManager.has_signal("currency_changed"):
		InventoryManager.currency_changed.connect(_on_currency_changed)


func _process(delta: float) -> void:
	# Rotate platform
	if rotating_platform:
		rotating_platform.rotate_y(deg_to_rad(rotation_speed * delta))
	

func _on_button_pressed() -> void:
	_interact()


func _interact() -> void:
	var now_msec := Time.get_ticks_msec()
	if now_msec < _cooldown_until_msec:
		return
	_cooldown_until_msec = now_msec + int(interact_cooldown_sec * 1000.0)

	if not CosmeticsManager or not CosmeticsManager.has_method("purchase_or_toggle"):
		_set_status_message("Cosmetics system unavailable")
		return

	var result_variant: Variant = await CosmeticsManager.purchase_or_toggle(item_id)
	var result: Dictionary = result_variant if result_variant is Dictionary else {}
	_set_status_message(String(result.get("message", "Done")))
	_refresh_status_label()


func _setup_preview_mesh() -> void:
	if not preview_anchor:
		return
	for child in preview_anchor.get_children():
		child.queue_free()

	if not CosmeticVisuals:
		return
	var preview := CosmeticVisuals.create_head_cosmetic(item_id, false)
	if not preview:
		return
	
	# Fitting to mannequin head
	preview.scale = Vector3(1.1, 1.1, 1.1)
	preview_anchor.add_child(preview)


func _refresh_status_label() -> void:
	if not status_label:
		return
	if not CosmeticsManager:
		status_label.text = "Cosmetics manager missing"
		return

	var item_def: Dictionary = CosmeticsManager.get_item_definition(item_id)
	var display_name := String(item_def.get("display_name", item_id))
	if item_def.is_empty():
		status_label.text = "%s\nUnknown item" % display_name
		return

	var owned := bool(CosmeticsManager.is_item_owned(item_id))
	var equipped := bool(CosmeticsManager.is_item_equipped(item_id))
	
	if poke_button:
		if owned and equipped:
			poke_button.key_character = "REMOVE"
		elif owned:
			poke_button.key_character = "EQUIP"
		else:
			poke_button.key_character = "BUY"

	if owned and equipped:
		status_label.text = "%s\nOwned + Equipped\nTap button: Unequip" % display_name
		return
	if owned:
		status_label.text = "%s\nOwned\nTap button: Equip" % display_name
		return

	var currency_type := String(item_def.get("currency_type", "gold"))
	var price := int(item_def.get("price", 0))
	var balance := 0
	if InventoryManager:
		balance = InventoryManager.get_currency(currency_type)
	status_label.text = "%s\nPrice: %d %s\nBalance: %d\nTap button: Buy" % [
		display_name,
		price,
		currency_type,
		balance
	]


func _set_status_message(message: String) -> void:
	if not status_label:
		return
	status_label.text = message


func _on_purchase_processed(processed_item_id: String, _success: bool, message: String) -> void:
	if processed_item_id != item_id:
		return
	_set_status_message(message)


func _on_currency_changed(_type: String, _amount: int) -> void:
	_refresh_status_label()
