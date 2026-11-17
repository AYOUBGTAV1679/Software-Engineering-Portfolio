package.path = "./?.lua;" .. package.path

local classify = require("provider_error_classifier")

local cases = {
    {
        name = "provider rate-limit message",
        input = '{"error":{"message":"Rate limit reached for this model"}}',
        expected = "Rate limit: provider rejected the request"
    },
    {
        name = "machine-readable rate-limit code",
        input = '{"error":{"code":"rate_limit_exceeded"}}',
        expected = "Rate limit: provider rejected the request"
    },
    {
        name = "decommissioned model",
        input = "The model has been decommissioned",
        expected = "Model unavailable: provider rejected the selected model"
    },
    {
        name = "model-not-found code",
        input = '{"error":{"code":"model_not_found"}}',
        expected = "Model unavailable: provider rejected the selected model"
    },
    {
        name = "model name followed by does not exist",
        input = 'The model "example/model" does not exist or you do not have access',
        expected = "Model unavailable: provider rejected the selected model"
    },
    {
        name = "provider reports no model endpoints",
        input = '{"error":{"message":"No endpoints found for model"}}',
        expected = "Model unavailable: provider rejected the selected model"
    },
    {
        name = "unrecognized provider error",
        input = '{"error":{"message":"Invalid API key"}}',
        expected = nil
    }
}

for _, case in ipairs(cases) do
    local actual = classify(case.input)
    assert(actual == case.expected,
        case.name .. ": expected " .. tostring(case.expected) .. ", got " .. tostring(actual))
    print("PASS " .. case.name)
end

print(string.format("Provider error classifier: %d checks passed", #cases))
