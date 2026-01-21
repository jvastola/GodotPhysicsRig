class_name LiveKitUtils
extends RefCounted
## Utility functions for LiveKit - JWT generation and encoding helpers

# Local development keys
const DEFAULT_API_KEY = "devkey"
const DEFAULT_API_SECRET = "secret12345678901234567890123456"
const TOKEN_VALIDITY_HOURS = 24

# TODO: IMPORTANT - Verify these keys match your self-hosted LiveKit instance settings!
# You should update these with the keys from your Oracle Cloud LiveKit configuration.


static func generate_token(participant_id: String, room_name: String = "test-room", 
		api_key: String = DEFAULT_API_KEY, api_secret: String = DEFAULT_API_SECRET) -> String:
	"""Generate a LiveKit JWT access token using HS256"""
	var now = int(Time.get_unix_time_from_system())
	var expire_time = now + (TOKEN_VALIDITY_HOURS * 3600)
	
	# JWT Header
	var header = {
		"alg": "HS256",
		"typ": "JWT"
	}
	
	# JWT Claims
	var claims = {
		"exp": expire_time,
		"iss": api_key,
		"nbf": now,
		"sub": participant_id,
		"video": {
			"room": room_name,
			"roomJoin": true,
			"canPublish": true,
			"canSubscribe": true
		}
	}
	
	# Encode header and payload
	var header_b64 = base64url_encode(JSON.stringify(header).to_utf8_buffer())
	var payload_b64 = base64url_encode(JSON.stringify(claims).to_utf8_buffer())
	
	# Create signing input and signature
	var signing_input = header_b64 + "." + payload_b64
	var signature = hmac_sha256(signing_input.to_utf8_buffer(), api_secret.to_utf8_buffer())
	var signature_b64 = base64url_encode(signature)
	
	return signing_input + "." + signature_b64


static func base64url_encode(data: PackedByteArray) -> String:
	"""Encode data as base64url (JWT standard)"""
	var b64 = Marshalls.raw_to_base64(data)
	b64 = b64.replace("+", "-")
	b64 = b64.replace("/", "_")
	b64 = b64.replace("=", "")
	return b64


static func hmac_sha256(message: PackedByteArray, key: PackedByteArray) -> PackedByteArray:
	"""Compute HMAC-SHA256"""
	var ctx = HMACContext.new()
	ctx.start(HashingContext.HASH_SHA256, key)
	ctx.update(message)
	return ctx.finish()
