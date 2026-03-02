extends Node

signal cosmetics_changed
signal owned_items_changed
signal equipped_changed(slot: String, item_id: String)
signal purchase_processed(item_id: String, success: bool, message: String)

const STORAGE_COLLECTION := "player_profile"
const STORAGE_KEY := "cosmetics"
const STORAGE_KEY_FALLBACK := "cosmetics_v2"
const DEFAULT_SLOT := "head"

var _catalog := {
	"hat_basic_red": {
		"display_name": "Red Cap",
		"slot": "head",
		"price": 120,
		"currency_type": "gold",
		"auto_equip": true,
	},
	"hat_basic_black": {
		"display_name": "Black Cap",
		"slot": "head",
		"price": 90,
		"currency_type": "gold",
		"auto_equip": true,
	},
}

var _owned_items: Dictionary = {}
var _equipped: Dictionary = {DEFAULT_SLOT: ""}
var _nakama_version: String = ""
var _active_storage_key: String = STORAGE_KEY
var _remote_synced_once := false
var _sync_busy := false
var _pending_push := false
var _nakama_sync_disabled := false
var _nakama_sync_disabled_reason := ""


func _ready() -> void:
	_load_local_state()

	if NakamaManager:
		if NakamaManager.has_signal("authenticated") and not NakamaManager.authenticated.is_connected(_on_nakama_authenticated):
			NakamaManager.authenticated.connect(_on_nakama_authenticated)
		if NakamaManager.has_signal("connection_restored") and not NakamaManager.connection_restored.is_connected(_on_nakama_connection_restored):
			NakamaManager.connection_restored.connect(_on_nakama_connection_restored)

	if NetworkManager and NetworkManager.has_signal("connection_succeeded"):
		if not NetworkManager.connection_succeeded.is_connected(_on_network_connection_succeeded):
			NetworkManager.connection_succeeded.connect(_on_network_connection_succeeded)

	call_deferred("_bootstrap_network_state")


func _bootstrap_network_state() -> void:
	_broadcast_equipped_to_network(false)
	if NakamaManager and NakamaManager.is_authenticated:
		_process_nakama_sync()


func _on_nakama_authenticated(_session: Dictionary) -> void:
	_nakama_sync_disabled = false
	_nakama_sync_disabled_reason = ""
	_remote_synced_once = false
	_process_nakama_sync()


func _on_nakama_connection_restored() -> void:
	_process_nakama_sync()


func _on_network_connection_succeeded() -> void:
	_broadcast_equipped_to_network(true)


func get_catalog() -> Dictionary:
	return _catalog.duplicate(true)


func get_item_definition(item_id: String) -> Dictionary:
	if not _catalog.has(item_id):
		return {}
	return (_catalog[item_id] as Dictionary).duplicate(true)


func get_owned_items() -> Array:
	var owned: Array = []
	for item_id in _owned_items.keys():
		owned.append(String(item_id))
	owned.sort()
	return owned


func is_item_owned(item_id: String) -> bool:
	return _owned_items.has(item_id)


func get_equipped_item(slot: String = DEFAULT_SLOT) -> String:
	return String(_equipped.get(slot, ""))


func is_item_equipped(item_id: String) -> bool:
	for slot in _equipped.keys():
		if String(_equipped[slot]) == item_id:
			return true
	return false


func can_purchase(item_id: String) -> Dictionary:
	var item_def := get_item_definition(item_id)
	if item_def.is_empty():
		return {
			"ok": false,
			"reason": "unknown_item"
		}
	if is_item_owned(item_id):
		return {
			"ok": false,
			"reason": "already_owned"
		}
	var currency_type := String(item_def.get("currency_type", "gold"))
	var price := int(item_def.get("price", 0))
	var balance := _get_currency_balance(currency_type)
	if balance < price:
		return {
			"ok": false,
			"reason": "insufficient_funds",
			"currency_type": currency_type,
			"price": price,
			"balance": balance
		}
	return {
		"ok": true,
		"currency_type": currency_type,
		"price": price,
		"balance": balance
	}


func purchase_item(item_id: String) -> Dictionary:
	var check := can_purchase(item_id)
	if not bool(check.get("ok", false)):
		var fail_msg := _purchase_failure_message(String(check.get("reason", "failed")), check)
		purchase_processed.emit(item_id, false, fail_msg)
		return {
			"ok": false,
			"message": fail_msg
		}

	var item_def := _catalog[item_id] as Dictionary
	var currency_type := String(item_def.get("currency_type", "gold"))
	var price := int(item_def.get("price", 0))
	if not _spend_currency(currency_type, price):
		var spend_msg := "Unable to spend %d %s" % [price, currency_type]
		purchase_processed.emit(item_id, false, spend_msg)
		return {
			"ok": false,
			"message": spend_msg
		}

	_owned_items[item_id] = true
	owned_items_changed.emit()

	var auto_equip := bool(item_def.get("auto_equip", true))
	if auto_equip:
		_equip_internal(String(item_def.get("slot", DEFAULT_SLOT)), item_id)

	_save_local_state()
	_schedule_push()
	_broadcast_equipped_to_network(true)
	cosmetics_changed.emit()

	var msg := "Purchased %s" % String(item_def.get("display_name", item_id))
	purchase_processed.emit(item_id, true, msg)
	return {
		"ok": true,
		"message": msg,
		"item_id": item_id
	}


func equip_item(item_id: String) -> Dictionary:
	if not is_item_owned(item_id):
		return {
			"ok": false,
			"message": "Item is not owned"
		}
	if not _catalog.has(item_id):
		return {
			"ok": false,
			"message": "Unknown item"
		}

	var item_def: Dictionary = _catalog[item_id]
	var slot := String(item_def.get("slot", DEFAULT_SLOT))
	if String(_equipped.get(slot, "")) == item_id:
		return {
			"ok": true,
			"message": "Already equipped",
			"slot": slot,
			"item_id": item_id
		}

	_equip_internal(slot, item_id)
	_save_local_state()
	_schedule_push()
	_broadcast_equipped_to_network(true)
	cosmetics_changed.emit()
	return {
		"ok": true,
		"message": "Equipped",
		"slot": slot,
		"item_id": item_id
	}


func unequip_slot(slot: String = DEFAULT_SLOT) -> Dictionary:
	if String(_equipped.get(slot, "")) == "":
		return {
			"ok": true,
			"message": "Nothing equipped",
			"slot": slot
		}

	_equipped[slot] = ""
	equipped_changed.emit(slot, "")
	_save_local_state()
	_schedule_push()
	_broadcast_equipped_to_network(true)
	cosmetics_changed.emit()
	return {
		"ok": true,
		"message": "Unequipped",
		"slot": slot
	}


func purchase_or_toggle(item_id: String) -> Dictionary:
	if not is_item_owned(item_id):
		return purchase_item(item_id)

	var item_def := get_item_definition(item_id)
	if item_def.is_empty():
		return {
			"ok": false,
			"message": "Unknown item"
		}

	var slot := String(item_def.get("slot", DEFAULT_SLOT))
	if String(_equipped.get(slot, "")) == item_id:
		return unequip_slot(slot)
	return equip_item(item_id)


func _equip_internal(slot: String, item_id: String) -> void:
	_equipped[slot] = item_id
	equipped_changed.emit(slot, item_id)


func _normalize_state(input_state: Dictionary) -> Dictionary:
	var normalized_owned: Dictionary = {}
	var owned_variant: Variant = input_state.get("owned", [])

	if owned_variant is Array:
		for item_variant in owned_variant:
			var item_id := String(item_variant)
			if _catalog.has(item_id):
				normalized_owned[item_id] = true
	elif owned_variant is Dictionary:
		var owned_dict: Dictionary = owned_variant
		for item_id_variant in owned_dict.keys():
			var item_id := String(item_id_variant)
			if _catalog.has(item_id) and bool(owned_dict[item_id_variant]):
				normalized_owned[item_id] = true

	var normalized_equipped := {DEFAULT_SLOT: ""}
	var equipped_variant: Variant = input_state.get("equipped", {})
	if equipped_variant is Dictionary:
		var equipped_dict: Dictionary = equipped_variant
		for slot_name in normalized_equipped.keys():
			var equipped_item := String(equipped_dict.get(slot_name, ""))
			if equipped_item != "" and normalized_owned.has(equipped_item):
				var item_def: Dictionary = _catalog.get(equipped_item, {})
				if String(item_def.get("slot", DEFAULT_SLOT)) == String(slot_name):
					normalized_equipped[slot_name] = equipped_item

	return {
		"owned": normalized_owned,
		"equipped": normalized_equipped
	}


func _serialize_state() -> Dictionary:
	var owned_items: Array = []
	for item_id in _owned_items.keys():
		owned_items.append(String(item_id))
	owned_items.sort()
	return {
		"owned": owned_items,
		"equipped": _equipped.duplicate(true)
	}


func _load_local_state() -> void:
	if SaveManager and SaveManager.has_method("get_cosmetics_state"):
		var saved_variant: Variant = SaveManager.get_cosmetics_state()
		if saved_variant is Dictionary:
			var normalized := _normalize_state(saved_variant)
			_owned_items = normalized["owned"]
			_equipped = normalized["equipped"]


func _save_local_state() -> void:
	if SaveManager and SaveManager.has_method("save_cosmetics_state"):
		SaveManager.save_cosmetics_state(_serialize_state())


func _get_currency_balance(currency_type: String) -> int:
	if InventoryManager and InventoryManager.has_method("get_currency"):
		return int(InventoryManager.get_currency(currency_type))
	if SaveManager and SaveManager.has_method("get_currency"):
		return int(SaveManager.get_currency(currency_type))
	return 0


func _spend_currency(currency_type: String, amount: int) -> bool:
	if amount <= 0:
		return true
	if InventoryManager and InventoryManager.has_method("spend_currency"):
		return bool(InventoryManager.spend_currency(currency_type, amount))
	if SaveManager and SaveManager.has_method("spend_currency"):
		return bool(SaveManager.spend_currency(currency_type, amount))
	return false


func _purchase_failure_message(reason: String, details: Dictionary) -> String:
	match reason:
		"unknown_item":
			return "Unknown cosmetic"
		"already_owned":
			return "Already owned"
		"insufficient_funds":
			return "Need %d %s (have %d)" % [
				int(details.get("price", 0)),
				String(details.get("currency_type", "coins")),
				int(details.get("balance", 0))
			]
		_:
			return "Purchase failed"


func _broadcast_equipped_to_network(broadcast: bool) -> void:
	if NetworkManager and NetworkManager.has_method("set_local_equipped_cosmetics"):
		NetworkManager.set_local_equipped_cosmetics(_equipped.duplicate(true), broadcast)


func _schedule_push() -> void:
	_pending_push = true
	_process_nakama_sync()


func _process_nakama_sync() -> void:
	if _sync_busy:
		return
	if _nakama_sync_disabled:
		return
	if not NakamaManager or not NakamaManager.is_authenticated:
		return
	_sync_busy = true
	call_deferred("_run_nakama_sync")


func _run_nakama_sync() -> void:
	await _run_nakama_sync_async()


func _run_nakama_sync_async() -> void:
	if not _remote_synced_once:
		await _pull_remote_state_once()

	while _pending_push:
		_pending_push = false
		await _push_state_once()

	_sync_busy = false


func _pull_remote_state_once() -> void:
	if not NakamaManager or not NakamaManager.has_method("read_storage_object"):
		_remote_synced_once = true
		return

	var read_keys: Array[String] = [STORAGE_KEY, STORAGE_KEY_FALLBACK]
	var found_existing := false
	var last_error := ""
	var last_error_code := 0

	for storage_key in read_keys:
		var result: Dictionary = await NakamaManager.read_storage_object(STORAGE_COLLECTION, storage_key)
		if not bool(result.get("ok", false)):
			last_error_code = int(result.get("code", 0))
			last_error = String(result.get("error", "unknown"))
			continue
		if not bool(result.get("exists", false)):
			continue

		found_existing = true
		_active_storage_key = storage_key
		_nakama_version = String(result.get("version", ""))
		var value_variant: Variant = result.get("value", {})
		if value_variant is Dictionary:
			var remote := _normalize_state(value_variant)
			var changed := _merge_remote_state(remote)
			if changed:
				_save_local_state()
				_broadcast_equipped_to_network(true)
				cosmetics_changed.emit()
		break

	_remote_synced_once = true
	if found_existing:
		return
	if last_error != "":
		push_warning("CosmeticsManager: Failed to read Nakama storage: %s" % last_error)
		if last_error_code == 501:
			_disable_nakama_sync("Storage read endpoint not available (HTTP 501)")
		return

	# No existing object in either key; write to the primary key.
	_active_storage_key = STORAGE_KEY
	_nakama_version = ""
	_pending_push = true


func _push_state_once() -> void:
	if not NakamaManager or not NakamaManager.has_method("write_storage_object"):
		return

	var payload := _serialize_state()
	var result: Dictionary = await NakamaManager.write_storage_object(
		STORAGE_COLLECTION,
		_active_storage_key,
		payload,
		_nakama_version,
		1,
		1
	)

	if bool(result.get("ok", false)):
		_nakama_version = String(result.get("version", _nakama_version))
		return

	var code := int(result.get("code", 0))
	if code == 409 or code == 412:
		# Version conflict: pull latest, merge, retry once.
		_remote_synced_once = false
		await _pull_remote_state_once()
		payload = _serialize_state()
		result = await NakamaManager.write_storage_object(
			STORAGE_COLLECTION,
			_active_storage_key,
			payload,
			_nakama_version,
			1,
			1
		)
		if bool(result.get("ok", false)):
			_nakama_version = String(result.get("version", _nakama_version))
			return

	var write_code := int(result.get("code", 0))
	var write_error := String(result.get("error", "unknown"))
	push_warning("CosmeticsManager: Failed to write Nakama storage: %s" % write_error)
	if write_error.contains("permission denied") and _active_storage_key == STORAGE_KEY:
		# Existing primary object may have been created with restrictive write permissions.
		_active_storage_key = STORAGE_KEY_FALLBACK
		_nakama_version = ""
		var fallback_result: Dictionary = await NakamaManager.write_storage_object(
			STORAGE_COLLECTION,
			_active_storage_key,
			payload,
			_nakama_version,
			1,
			1
		)
		if bool(fallback_result.get("ok", false)):
			_nakama_version = String(fallback_result.get("version", ""))
			return
		write_code = int(fallback_result.get("code", 0))
		write_error = String(fallback_result.get("error", write_error))
		push_warning("CosmeticsManager: Fallback key write failed: %s" % write_error)
	if write_code == 403 or write_error.contains("permission denied"):
		_disable_nakama_sync("Storage write denied by server permissions")


func _merge_remote_state(remote: Dictionary) -> bool:
	var changed := false
	var remote_owned_variant: Variant = remote.get("owned", {})
	var remote_equipped_variant: Variant = remote.get("equipped", {})
	if remote_owned_variant is Dictionary:
		var remote_owned: Dictionary = remote_owned_variant
		for item_id in remote_owned.keys():
			if not _owned_items.has(item_id):
				_owned_items[item_id] = true
				changed = true
	if remote_equipped_variant is Dictionary:
		var remote_equipped: Dictionary = remote_equipped_variant
		for slot in _equipped.keys():
			var remote_item := String(remote_equipped.get(slot, ""))
			if remote_item == "":
				if String(_equipped.get(slot, "")) != "":
					_equipped[slot] = ""
					equipped_changed.emit(slot, "")
					changed = true
				continue
			if _owned_items.has(remote_item) and String(_equipped.get(slot, "")) != remote_item:
				_equipped[slot] = remote_item
				equipped_changed.emit(slot, remote_item)
				changed = true

	# Ensure equipped items are still owned.
	for slot in _equipped.keys():
		var equipped_item := String(_equipped[slot])
		if equipped_item != "" and not _owned_items.has(equipped_item):
			_equipped[slot] = ""
			equipped_changed.emit(slot, "")
			changed = true

	if changed:
		owned_items_changed.emit()
	return changed


func _disable_nakama_sync(reason: String) -> void:
	if _nakama_sync_disabled:
		return
	_nakama_sync_disabled = true
	_nakama_sync_disabled_reason = reason
	push_warning("CosmeticsManager: Disabling Nakama sync for this session: %s" % reason)
