extends Node

## Simple inventory system for collecting resources

# Singleton instance
static var instance: Node

# Inventory storage: { "iron": 5, "gold": 2, etc. }
var inventory: Dictionary = {}

signal item_collected(item_type: String, amount: int, total: int)
signal inventory_changed()
signal currency_changed(type: String, amount: int)


func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
		return
	
	print("InventoryManager: Ready")


func add_item(item_type: String, amount: int = 1) -> void:
	"""Add items to inventory"""
	if not inventory.has(item_type):
		inventory[item_type] = 0
	
	inventory[item_type] += amount
	var total = inventory[item_type]
	
	print("InventoryManager: Collected ", amount, " ", item_type, " (Total: ", total, ")")
	
	item_collected.emit(item_type, amount, total)
	inventory_changed.emit()
	
	if item_type in ["gold", "gems", "tokens"]:
		currency_changed.emit(item_type, total)


func get_item_count(item_type: String) -> int:
	"""Get count of a specific item"""
	return inventory.get(item_type, 0)


func has_item(item_type: String, amount: int = 1) -> bool:
	"""Check if inventory has at least amount of item"""
	return get_item_count(item_type) >= amount


func remove_item(item_type: String, amount: int = 1) -> bool:
	"""Remove items from inventory, returns true if successful"""
	if not has_item(item_type, amount):
		return false
	
	inventory[item_type] -= amount
	if inventory[item_type] <= 0:
		inventory.erase(item_type)
	
	inventory_changed.emit()
	
	if item_type in ["gold", "gems", "tokens"]:
		currency_changed.emit(item_type, inventory[item_type] if inventory.has(item_type) else 0)
		
	return true


func clear_inventory() -> void:
	"""Clear all items"""
	inventory.clear()
	inventory_changed.emit()


func get_all_items() -> Dictionary:
	"""Get a copy of the entire inventory"""
	return inventory.duplicate()


func get_currency(currency_type: String) -> int:
	"""Helper to get currency amount"""
	return get_item_count(currency_type)
