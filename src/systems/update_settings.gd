@tool
extends SceneTree

func _init():
	print("Updating Editor Settings...")
	var settings = EditorInterface.get_editor_settings()
	if settings:
		settings.set_setting("export/android/debug_keystore", "C:/Users/Admin/GodotPhysicsRig/debug.keystore")
		settings.set_setting("export/android/debug_keystore_user", "androiddebugkey")
		settings.set_setting("export/android/debug_keystore_pass", "android")
		settings.set_setting("export/android/android_sdk_path", "C:/Users/Admin/AppData/Local/Android/Sdk")
		
		# Ensure NDK path is also set if needed, though usually auto-detected
		# settings.set_setting("export/android/ndk_path", "C:/Users/Admin/AppData/Local/Android/Sdk/ndk/29.0.14206865")
		
		var err = settings.save()
		if err == OK:
			print("Editor settings saved successfully.")
		else:
			print("Error saving editor settings: ", err)
	else:
		print("Could not get EditorSettings singleton.")
	quit()