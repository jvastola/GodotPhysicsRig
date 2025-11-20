extends Node

signal inventory_changed(items: Array)
signal currency_changed(type: String, amount: int)

# List of all possible item resources, loaded at start
var item_database: Dictionary = {}

# Current inventory state (Array of Dictionaries: { "id": "item_id", "amount": 1 })
var inventory: Array = []

func _ready() -> void:
	# Load inventory from save manager
	load_inventory()
	
	# Example: Load item database (in a real app, you might scan a folder)
	# _load_item_database()


func load_inventory() -> void:
	# Assuming SaveManager is an autoload
	if has_node("/root/SaveManager"):
		var save_mgr = get_node("/root/SaveManager")
		inventory = save_mgr.get_inventory()
		emit_signal("inventory_changed", inventory)


func save_inventory() -> void:
	if has_node("/root/SaveManager"):
		var save_mgr = get_node("/root/SaveManager")
		save_mgr.save_inventory(inventory)


func add_item(item_id: String, amount: int = 1) -> void:
	# Check if item stacks
	var added = false
	
	# Ideally check against database for max stack, but for now assume simple stacking
	for slot in inventory:
		if slot["id"] == item_id:
			slot["amount"] += amount
			added = true
			break
	
	if not added:
		inventory.append({ "id": item_id, "amount": amount })
	
	save_inventory()
	emit_signal("inventory_changed", inventory)
	print("InventoryManager: Added ", amount, " of ", item_id)


func remove_item(item_id: String, amount: int = 1) -> bool:
	for i in range(inventory.size()):
		if inventory[i]["id"] == item_id:
			if inventory[i]["amount"] >= amount:
				inventory[i]["amount"] -= amount
				if inventory[i]["amount"] <= 0:
					inventory.remove_at(i)
				
				save_inventory()
				emit_signal("inventory_changed", inventory)
				return true
			break
	return false


func has_item(item_id: String, amount: int = 1) -> bool:
	for slot in inventory:
		if slot["id"] == item_id:
			return slot["amount"] >= amount
	return false


# Wrapper for currency to emit signals
func add_currency(type: String, amount: int) -> void:
	if has_node("/root/SaveManager"):
		get_node("/root/SaveManager").add_currency(type, amount)
		emit_signal("currency_changed", type, get_currency(type))

func get_currency(type: String) -> int:
	if has_node("/root/SaveManager"):
		return get_node("/root/SaveManager").get_currency(type)
	return 0
