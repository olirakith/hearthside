local MS = _G.MS
MS.Community = MS.Community or {}
-- Strict transport interface: adapter.send(target, packet) and runtime-delivered
-- receive({ from, mode }, packet). The local return value is diagnostic only: Forever accepts
-- a 256-byte send and delivers 255 bytes, so SEND_SUCCESS is never DELIVERY.
-- Policy: content travels only on a targeted mode. PARTY/RAID/CHANNEL are broadcast audiences
-- and are refused for every Peer packet in V1, both directions. BNET is not implemented.
local C = MS.Community
local T = { prefix = "AJCX1", nativeLimit = 255 }
C.Transport = T

T.POLICY = {
    WHISPER = { targeted = true, allowed = true },
    PARTY = { targeted = false, allowed = false, reason = "BROADCAST_AUDIENCE" },
    RAID = { targeted = false, allowed = false, reason = "BROADCAST_AUDIENCE" },
    CHANNEL = { targeted = false, allowed = false, reason = "CHANNEL_DISABLED" },
    BNET = { targeted = true, allowed = false, reason = "NOT_IMPLEMENTED" },
}

function T.Allowed(mode)
    local policy = T.POLICY[mode]
    return policy ~= nil and policy.allowed == true, policy and policy.reason or "UNKNOWN_MODE"
end

-- Native WoW adapter. Errors are raised so the peer records LOCAL_SEND_ERROR; a returned
-- success means only "handed to the client".
function T.Native(mode, chat)
    local allowed, reason = T.Allowed(mode)
    return { mode = mode, send = function(target, packet)
        if not allowed then error(reason, 0) end
        if type(packet) ~= "string" or #packet > MS.Community.Wire.LIMITS.wire or #packet > T.nativeLimit then error("WIRE_SIZE", 0) end
        if type(target) ~= "string" or target == "" then error("TARGET", 0) end
        local api = chat or _G.C_ChatInfo
        if type(api) ~= "table" or type(api.SendAddonMessage) ~= "function" then error("API_UNAVAILABLE", 0) end
        local result = api.SendAddonMessage(T.prefix, packet, mode, target)
        if result == false then error("CLIENT_REFUSED", 0) end
        -- Newer clients return an enum where 0 is Success; anything else is a local refusal.
        if type(result) == "number" and result ~= 0 then error("CLIENT_RESULT_" .. result, 0) end
        return result
    end }
end
