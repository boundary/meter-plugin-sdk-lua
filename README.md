# boundary-plugin-framework-lua
A starting point to make a library that can easy the development of Boundary Plugin using LUA/Luvit

### Example 1 - Generating random metric values

#### param.json
```
{
  pollInterval = 1000,
  minValue     = 0,
  maxValue     = 100
}
```

#### init.lua

```lua
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

#### Running the plugin

```sh
> luvit init.lua
```

### Example 2 - Chaining DataSources

In this example we will see how to extract the page total bytes for a dynamic web request using two chained DataSources. We first simulate a request with a DataSource that returns a tag and then pass this to a WebRequestDataSource to generate a new request. Finally we count the bytes returned by the RequestDataSource to generate the metric.

```lua
local framework = require('./framework')
local Plugin = framework.Plugin
local WebRequestDataSource = framework.WebRequestDataSource
local DataSource = framework.DataSource
local math = require('math')
local url = require('url')

-- A DataSource to simulate a request that returns a different tag each time its called.
local getTag = (function () 
  local tags = { 'python', 'nodejs', 'lua', 'luvit', 'ios' } 
  return function () 
    local idx = math.random(1, #tags)
    return tags[idx]
  end
end)()

local tags_ds = DataSource:new(getTag)

-- A WebRequestDataSource that will request a dynamic generated url. The {tagname} will be replaced by the value returned from the first DataSource.
local options = url.parse('http://stackoverflow.com/questions/tagged/{tagname}')
options.wait_for_end = true
local questions_ds = WebRequestDataSource:new(options)

-- Now chain/pipe the DataSources
local function transform(tag) return { tagname = tag } end
tags_ds:chain(questions_ds, transform) 

local params = {}
params.pollInterval = 5000

local plugin = Plugin:new(params, tags_ds)

-- Finally parse the result from the chained DataSources to produce the metric that Plugin will process.
function plugin:onParseValues(data)
  result = { PAGE_BYTES_TOTAL = #data }
  return result
end

plugin:run()
```
