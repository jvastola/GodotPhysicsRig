local nk = require("nakama")

local function b64url(input)
  local out = nk.base64_encode(input)
  out = string.gsub(out, "+", "-")
  out = string.gsub(out, "/", "_")
  out = string.gsub(out, "=", "")
  return out
end

local function hex_to_bytes(hex)
  if string.match(hex, "^[0-9a-fA-F]+$") == nil or (#hex % 2 ~= 0) then
    return hex
  end
  return (hex:gsub("..", function(cc)
    return string.char(tonumber(cc, 16))
  end))
end

local function hmac_sha256_bytes(message, secret)
  local hash = nk.hmac_sha256_hash(message, secret)
  if #hash == 64 and string.match(hash, "^[0-9a-fA-F]+$") ~= nil then
    return hex_to_bytes(hash)
  end
  return hash
end

local function rpc_livekit_token(context, payload)
  local request = {}
  if payload and payload ~= "" then
    local ok, decoded = pcall(nk.json_decode, payload)
    if ok then
      if type(decoded) == "table" then
        request = decoded
      elseif type(decoded) == "string" and decoded ~= "" then
        local ok2, decoded2 = pcall(nk.json_decode, decoded)
        if ok2 and type(decoded2) == "table" then
          request = decoded2
        end
      end
    end
  end

  local room = request.room or "default-room"
  local participant_id = request.participant_id or context.user_id or ""
  local display_name = request.display_name or ""
  local metadata = request.metadata
  if type(metadata) ~= "table" then
    metadata = {}
  end

  if participant_id == "" then
    return nk.json_encode({ error = "participant_id missing" })
  end

  -- NOTE: keep these in sync with server runtime secret provisioning.
  local api_key = "devkey"
  local api_secret = "__SET_ON_SERVER__"
  local ws_url = request.ws_url or "ws://158.101.21.99:7880"
  local now = os.time()
  local exp = now + 86400
  if api_secret == "__SET_ON_SERVER__" then
    return nk.json_encode({ error = "livekit api secret not configured" })
  end

  local header = nk.json_encode({ alg = "HS256", typ = "JWT" })
  local claims = {
    exp = exp,
    iss = api_key,
    nbf = now - 60,
    sub = participant_id,
    video = {
      room = room,
      roomJoin = true,
      canPublish = true,
      canSubscribe = true,
      canPublishData = true,
      canUpdateOwnMetadata = true
    }
  }
  if display_name ~= "" then
    claims.name = display_name
  end
  if next(metadata) ~= nil then
    claims.metadata = nk.json_encode(metadata)
  end

  local header_b64 = b64url(header)
  local payload_b64 = b64url(nk.json_encode(claims))
  local signing_input = header_b64 .. "." .. payload_b64
  local signature_b64 = b64url(hmac_sha256_bytes(signing_input, api_secret))
  local token = signing_input .. "." .. signature_b64

  return nk.json_encode({
    token = token,
    ws_url = ws_url,
    room = room,
    participant_id = participant_id
  })
end

nk.register_rpc(rpc_livekit_token, "livekit_token")
