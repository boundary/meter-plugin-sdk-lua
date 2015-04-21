# boundary-plugin-framework-lua
A starting point to make a library that can easy the development of Boundary Plugin using LUA/Luvit

## A simple plugin that generates random values

### param.json
{
  pollInterval = 1000,
  minValue     = 0,
  maxValue     = 100
}

### init.lua

```
local framework = require('framework')
local Plugin = framework.Plugin
local RandomDataSource = framework.RandomDataSource 

local params = framework.params

local data_source = RandomDataSource(params.minValue, params.maxValue)
local plugin = Plugin:new(params, data_source)

plugin:onParseValues(value)
  local result = {BOUNDARY_SAMPLE_METRIC = value}
  return result
end

plugin:run()

```
