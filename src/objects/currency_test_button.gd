extends StaticBody3D
class_name CurrencyTestButton

@export var currency_type: String = "gold"
@export var amount_per_press: int = 50
@export var press_cooldown_sec: float = 0.25

@onready var status_label: Label3D = $StatusLabel

var _next_press_msec: int = 0


func _ready() -> void:
	collision_layer = 32
	collision_mask = 0
	add_to_group("pointer_interactable")
	_update_status("%s +%d\nTrigger/Click" % [currency_type.capitalize(), amount_per_press])


func handle_pointer_event(event: Dictionary) -> void:
	var event_type := String(event.get("type", ""))
	if event_type != "press" and event_type != "secondary_press":
		return
	_grant_currency()


func _grant_currency() -> void:
	var now_msec := Time.get_ticks_msec()
	if now_msec < _next_press_msec:
		return
	_next_press_msec = now_msec + int(press_cooldown_sec * 1000.0)

	var normalized_currency := currency_type.strip_edges().to_lower()
	if normalized_currency == "coin" or normalized_currency == "coins":
		normalized_currency = "gold"

	var granted := false
	if InventoryManager and InventoryManager.has_method("add_currency"):
		InventoryManager.add_currency(normalized_currency, amount_per_press)
		granted = true
	elif SaveManager and SaveManager.has_method("add_currency"):
		SaveManager.add_currency(normalized_currency, amount_per_press)
		granted = true

	if not granted:
		_update_status("No inventory/save manager")
		return

	var balance := 0
	if InventoryManager and InventoryManager.has_method("get_currency"):
		balance = InventoryManager.get_currency(normalized_currency)
	elif SaveManager and SaveManager.has_method("get_currency"):
		balance = SaveManager.get_currency(normalized_currency)
	_update_status("+%d %s\nTotal: %d" % [amount_per_press, normalized_currency, balance])


func _update_status(text_value: String) -> void:
	if status_label:
		status_label.text = text_value
