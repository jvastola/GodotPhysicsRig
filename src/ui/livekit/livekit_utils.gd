class_name LiveKitUtils
extends RefCounted
## Legacy utility retained for compatibility.
## Do not generate LiveKit JWTs on the client; use Nakama RPC.

static func generate_token(_participant_id: String, _room_name: String = "test-room", _api_key: String = "", _api_secret: String = "") -> String:
	push_warning("LiveKitUtils.generate_token is disabled. Use NakamaManager.request_livekit_token instead.")
	return ""
