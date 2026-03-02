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

local EARN_STATE_COLLECTION = "player_profile"
local EARN_STATE_KEY = "currency_earn_state"

local function get_env(name, fallback, context)
  if context and context.env and context.env[name] then
    return context.env[name]
  end
  local ok, value = pcall(function() return os.getenv(name) end)
  if ok and type(value) == "string" and value ~= "" then
    return value
  end
  return fallback
end

local DEFAULT_EARN_CAP = tonumber(get_env("CURRENCY_EARN_CAP", "2500")) or 2500
local DEFAULT_EARN_WINDOW_SEC = tonumber(get_env("CURRENCY_EARN_WINDOW_SEC", "600")) or 600

local function decode_request_payload(payload)
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
  return request
end

local function normalize_currency_map(input)
  local out = {}
  if type(input) ~= "table" then
    return out
  end

  for key, value in pairs(input) do
    local currency = string.lower(tostring(key))
    if currency == "coin" or currency == "coins" then
      currency = "gold"
    end
    local amount = tonumber(value) or 0
    amount = math.floor(amount)
    if amount > 0 then
      out[currency] = amount
    end
  end

  return out
end

local function get_wallet_table(user_id)
  local account = nk.account_get_id(user_id)
  if not account or account.wallet == nil then
    return {}
  end

  -- Nakama runtime can expose wallet as either a Lua table or a JSON string.
  if type(account.wallet) == "table" then
    return account.wallet
  end
  if type(account.wallet) == "string" then
    if account.wallet == "" then
      return {}
    end
    local ok, decoded = pcall(nk.json_decode, account.wallet)
    if ok and type(decoded) == "table" then
      return decoded
    end
  end
  return {}
end

local function read_earn_state(user_id, now, window_sec)
  local state = {
    window_start = now,
    earned = {}
  }

  local read_request = {
    {
      collection = EARN_STATE_COLLECTION,
      key = EARN_STATE_KEY,
      user_id = user_id
    }
  }
  local ok, objects = pcall(nk.storage_read, read_request)
  if not ok or type(objects) ~= "table" or #objects == 0 then
    return state
  end
  local first = objects[1]
  if type(first) ~= "table" or type(first.value) ~= "table" then
    return state
  end

  local loaded = first.value
  local loaded_window_start = tonumber(loaded.window_start) or now
  local loaded_earned = normalize_currency_map(loaded.earned)
  if (now - loaded_window_start) >= window_sec then
    return {
      window_start = now,
      earned = {}
    }
  end
  return {
    window_start = loaded_window_start,
    earned = loaded_earned
  }
end

local function write_earn_state(user_id, state)
  local write_request = {
    {
      collection = EARN_STATE_COLLECTION,
      key = EARN_STATE_KEY,
      user_id = user_id,
      value = state,
      permission_read = 0,
      permission_write = 0
    }
  }
  return nk.storage_write(write_request)
end

local function rpc_livekit_token(context, payload)
  local request = decode_request_payload(payload)

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

  local api_key = request.api_key or get_env("LIVEKIT_API_KEY", "devkey", context)
  local api_secret = request.api_secret or get_env("LIVEKIT_API_SECRET", "", context)
  local ws_url = request.ws_url or get_env("LIVEKIT_WS_URL", "ws://127.0.0.1:7880", context)
  local now = os.time()
  local exp = now + 86400
  if api_secret == "" then
    nk.logger_warn("livekit_token RPC: LIVEKIT_API_SECRET missing; cannot mint token")
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

local function rpc_currency_wallet_snapshot(context, _payload)
  local wallet = get_wallet_table(context.user_id)
  return nk.json_encode({
    ok = true,
    wallet = wallet,
    cap = DEFAULT_EARN_CAP,
    window_sec = DEFAULT_EARN_WINDOW_SEC
  })
end

local function rpc_currency_commit(context, payload)
  local request = decode_request_payload(payload)
  local now = os.time()
  local earn_cap = tonumber(request.cap) or DEFAULT_EARN_CAP
  local window_sec = tonumber(request.window_sec) or DEFAULT_EARN_WINDOW_SEC
  if earn_cap < 0 then
    earn_cap = 0
  end
  if window_sec < 1 then
    window_sec = DEFAULT_EARN_WINDOW_SEC
  end

  local requested_earned = normalize_currency_map(request.earned)
  local requested_spent = normalize_currency_map(request.spent)
  local strict_spend = request.strict_spend == true
  local reason = tostring(request.reason or "currency_commit")
  local session_id = tostring(request.session_id or "")

  local earn_state = read_earn_state(context.user_id, now, window_sec)
  local applied_earned = {}
  local earned_changeset = {}
  local earned_additions = {}
  for currency, amount in pairs(requested_earned) do
    local earned_so_far = tonumber(earn_state.earned[currency]) or 0
    local remaining = math.max(earn_cap - earned_so_far, 0)
    local allowed = math.min(amount, remaining)
    if allowed > 0 then
      earned_changeset[currency] = allowed
      applied_earned[currency] = allowed
      earned_additions[currency] = allowed
      earn_state.earned[currency] = earned_so_far + allowed
    else
      applied_earned[currency] = 0
    end
  end

  if next(earned_changeset) ~= nil then
    local earn_ok, earn_err = pcall(
      nk.wallet_update,
      context.user_id,
      earned_changeset,
      { reason = "earn_sync", session_id = session_id },
      true
    )
    if not earn_ok then
      nk.logger_warn("currency_commit earn update failed: " .. tostring(earn_err))
      for currency, addition in pairs(earned_additions) do
        local earned_so_far = tonumber(earn_state.earned[currency]) or 0
        local rolled_back = math.max(earned_so_far - addition, 0)
        earn_state.earned[currency] = rolled_back
        applied_earned[currency] = 0
      end
    end
  end

  local spend_changeset = {}
  for currency, amount in pairs(requested_spent) do
    spend_changeset[currency] = -amount
  end
  local applied_spent = {}
  local spend_error = ""
  if next(spend_changeset) ~= nil then
    local spend_ok, spend_err = pcall(
      nk.wallet_update,
      context.user_id,
      spend_changeset,
      { reason = reason, session_id = session_id, strict_spend = strict_spend },
      true
    )
    if spend_ok then
      for currency, amount in pairs(requested_spent) do
        applied_spent[currency] = amount
      end
    else
      spend_error = tostring(spend_err)
      for currency, _ in pairs(requested_spent) do
        applied_spent[currency] = 0
      end
    end
  end

  local write_ok, write_result = pcall(write_earn_state, context.user_id, earn_state)
  if not write_ok then
    nk.logger_warn("currency_commit could not write earn state: " .. tostring(write_result))
  end

  local wallet = get_wallet_table(context.user_id)
  if strict_spend and spend_error ~= "" then
    return nk.json_encode({
      ok = false,
      error = spend_error,
      wallet = wallet,
      applied_earned = applied_earned,
      applied_spent = applied_spent,
      cap = earn_cap,
      window_sec = window_sec
    })
  end

  return nk.json_encode({
    ok = true,
    wallet = wallet,
    applied_earned = applied_earned,
    applied_spent = applied_spent,
    cap = earn_cap,
    window_sec = window_sec,
    spend_error = spend_error
  })
end

nk.register_rpc(rpc_livekit_token, "livekit_token")
nk.register_rpc(rpc_currency_wallet_snapshot, "currency_wallet_snapshot")
nk.register_rpc(rpc_currency_commit, "currency_commit")

-- Startup Self-Check
local check_key = get_env("LIVEKIT_API_KEY", "")
local check_secret = get_env("LIVEKIT_API_SECRET", "")
local check_url = get_env("LIVEKIT_WS_URL", "")

if check_key == "" or check_secret == "" then
  nk.logger_warn("LIVEKIT CONFIGURATION MISSING: API Key or Secret not found in environment.")
else
  nk.logger_info("LiveKit Configuration Loaded: Key=" .. check_key .. ", URL=" .. (check_url ~= "" and check_url or "default"))
end
