-- crash_guard_log_writer
-- Protect each file operation independently so a write failure still closes
-- the handle and cannot unwind the caller's monitoring loop.
local M = {}

function M.append(openFile, path, record)
    if type(openFile) ~= "function" then
        return false, "openFile must be a function"
    end
    if type(path) ~= "string" or path == "" then
        return false, "path must be a non-empty string"
    end
    if type(record) ~= "string" then
        return false, "record must be a string"
    end

    local openOk, file, openError = pcall(openFile, path, "a")
    if not openOk then
        return false, "open threw: " .. tostring(file)
    end
    if not file then
        return false, "open failed: " .. tostring(openError)
    end

    local writeOk, writeResult, writeError = pcall(file.write, file, record)
    -- Always attempt close even when write returned an error or threw.
    local closeOk, closeResult, closeError = pcall(file.close, file)

    if not writeOk then
        return false, "write threw: " .. tostring(writeResult)
    end
    if writeResult == nil or writeResult == false then
        return false, "write failed: " .. tostring(writeError)
    end
    if not closeOk then
        return false, "close threw: " .. tostring(closeResult)
    end
    if closeResult == nil or closeResult == false then
        return false, "close failed: " .. tostring(closeError)
    end
    return true
end

return M
