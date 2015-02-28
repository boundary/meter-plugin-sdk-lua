-- Copyright 2015 Boundary
-- @brief convenience variables and functions for Lua scripts
-- @file boundary.lua
local fs = require('fs')
local json = require('json')

local boundary = {param = nil}

-- import param.json data into a Lua table (boundary.param)
local json_blob
if (pcall(function () json_blob = fs.readFileSync("param.json") end)) then
  pcall(function () boundary.param = json.parse(json_blob) end)
end

return boundary
