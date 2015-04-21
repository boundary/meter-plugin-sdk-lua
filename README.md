# boundary-plugin-framework-lua
A starting point to make a library that can easy the development of Boundary Plugin using LUA/Luvit

## A simple plugin that generates random values

### param.json
```
{
  pollInterval = 1000,
  minValue     = 0,
  maxValue     = 100
}
```

### init.lua

```
local framework = require('./modules/framework')
local Plugin = framework.Plugin
local RandomDataSource = framework.RandomDataSource

local params = framework.params
params.name = 'Boundary Demo Plugin'
params.version = '1.0'
params.minValue = params.minValue or 1
params.maxValue = params.maxValue or 100

local data_source = RandomDataSource:new(params.minValue, params.maxValue)
local plugin = Plugin:new(params, data_source)

function plugin:onParseValues(val)
	local result = {}
	result['BOUNDARY_SAMPLE_METRIC'] = val
	return result 
end

plugin:run()

```

## Running the plugin

```

$ luvit init.lua

```


