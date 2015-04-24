# boundary-plugin-framework-lua
A starting point to make a library that can easy the development of Boundary Plugin using LUA/Luvit

### A simple plugin that generates random values

#### param.json
```
{
  pollInterval = 1000,
  minValue     = 0,
  maxValue     = 100
}
```

#### init.lua

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

#### Running the plugin

```

$ luvit init.lua

```

### Example 2 - Chaining DataSourcesAn example of chainig DataSources


In this example we will see how to extract the page total bytes for a dynamic web request. We first simulate a request with a DataSource that returns a tag and then chain this result to a WebRequestDataSource to generate a parametrized request. Ultimatly we count the bytes returned by the RequestDataSource to generate the metric.

```
local framework = require('./framework')
local Plugin = framework.Plugin
local WebRequestDataSource = framework.WebRequestDataSource
local DataSource = framework.DataSource
local math = require('math')
local url = require('url')

-- Randombly get a tag  
local getTag = (function () 
  local tags = { 'python', 'nodejs', 'lua', 'luvit', 'ios' } 
  return function () 
    local idx = math.random(1, #tags)
    return tags[idx]
  end
end)()

-- This DataSource simulate a request that get some tags for later processing
local tags_ds = DataSource:new(getTag)

-- Passing an url with {variablename} can be evaluated with the parameters passed to WebRequestDataSource:fetch
local options = url.parse('http://stackoverflow.com/questions/tagged/{tagname}')
options.wait_for_end = true

-- create a parsing/transformation function that transform the result of tags_ds fetch operation before passing to the questions_ds:fetch operation.
local questions_ds = WebRequestDataSource:new(options)
local function transform(tag) return { tagname = tag } end
tags_ds:chain(questions_ds, transform) 

local params = {}
params.pollInterval = 5000

local plugin = Plugin:new(params, tags_ds)

-- Ultimately parse the last fetch request to produce the metric
function plugin:onParseValues(data)
  result = { PAGE_BYTES_TOTAL = #data }
  return result
end

plugin:run()
```
