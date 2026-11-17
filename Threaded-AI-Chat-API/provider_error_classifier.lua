-- Pure classifier for common OpenAI-compatible provider error payloads.
-- Returns a normalized message for model rotation, or nil for unrecognized errors.
local function classify(raw)
    local lower = tostring(raw or ""):lower()
    if lower:find("rate limit", 1, true)
        or lower:find("rate_limit", 1, true)
        or lower:find("too many requests", 1, true) then
        return "Rate limit: provider rejected the request"
    end
    if lower:find("decommissioned", 1, true)
        or lower:find("model_not_found", 1, true)
        or lower:find("unknown model", 1, true)
        or lower:find("model does not exist", 1, true)
        or lower:find("does not exist", 1, true)
        or lower:find("no endpoints found for model", 1, true) then
        return "Model unavailable: provider rejected the selected model"
    end
    return nil
end

return classify
