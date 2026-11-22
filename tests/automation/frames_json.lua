-- Purpose: deterministic JSON encoder for the gameplay-frame tests (sorted keys,
-- fixed number format) so results from every platform compare exactly.
-- Location/runtime: tests/automation/frames_json.lua; LuaJIT (LÖVE or plain).
-- Inputs: a Lua value. Outputs: a JSON string. Sequences become arrays, other
-- tables objects with string keys; NaN/inf become NaN/Infinity (Python's json
-- reads them); functions and userdata become null. No files, no side effects.
-- Run/check: loaded by tests/automation/main.lua and tests/decky_frames.py.
local M = {}
local escapes = {
    ['"'] = '\\"',
    ["\\"] = "\\\\",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
}
local function str(s)
    return '"'
        .. s:gsub('[%c"\\]', function(c)
            return escapes[c] or string.format("\\u%04x", c:byte())
        end)
        .. '"'
end
local function num(n)
    if n ~= n then
        return "NaN"
    end
    if n == math.huge then
        return "Infinity"
    end
    if n == -math.huge then
        return "-Infinity"
    end
    if n == math.floor(n) and math.abs(n) < 2 ^ 53 then
        return string.format("%d", n)
    end
    return string.format("%.10g", n)
end
local function isArray(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
            return false
        end
        n = n + 1
    end
    for i = 1, n do
        if t[i] == nil then
            return false
        end
    end
    return true, n
end
local function encode(v, seen)
    local kind = type(v)
    if kind == "nil" then
        return "null"
    end
    if kind == "boolean" then
        return tostring(v)
    end
    if kind == "number" then
        return num(v)
    end
    if kind == "string" then
        return str(v)
    end
    if kind ~= "table" then
        return "null"
    end
    if seen[v] then
        return '"<cycle>"'
    end
    seen[v] = true
    local out = {}
    local array, n = isArray(v)
    if array and n > 0 then
        for i = 1, n do
            out[i] = encode(v[i], seen)
        end
        seen[v] = nil
        return "[" .. table.concat(out, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    for _, k in ipairs(keys) do
        out[#out + 1] = str(tostring(k)) .. ":" .. encode(v[k], seen)
    end
    seen[v] = nil
    return "{" .. table.concat(out, ",") .. "}"
end
function M.encode(v)
    return encode(v, {})
end
return M
