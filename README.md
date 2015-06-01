# boundary-plugin-framework-lua
A starting point to make a library that can easy the development of Boundary Plugin using LUA/Luvit

### Example 1 - Generating random metric values

#### plugin.json
```
{
  "name"            : "Boundary Demo Plugin",
  "version"         : "1.0",
  "tags"            : "applicationA",
  "description"     : "This is a sample boundary plugin generating random metric values",
  "icon"            : "icon.png",
  "command"         : "boundary-meter init.lua",
  "command_lua"     : "boundary-meter init.lua",
  "postExtract"     : "",
  "postExtract_lua" : "",
  "ignore"          : "",

  "metrics"     : [
    "BOUNDARY_SAMPLE_METRIC"
  ],

  "dashboards"  : [
    {
      "name"        : "Nginx Plus Summary",
      "layout"      : "d-w=1&d-h=1&d-pad=5&d-bg=none&d-g-BOUNDARY_SAMPLE_METRIC=1-1-1-1"
    }
  ],

  "paramSchema" : [
    {
     "title"        : "Poll Interval",
      "name"        : "pollInterval",
      "description" : "The Poll Interval in milliseconds. Ex. 5000",
      "type"        : "number",
      "default"     : 5000,
      "required"    : false
    },
    {
      "title"       : "Maximum Value",
      "name"        : "maxValue",
      "description" : "The upper bound of the random numbers being generated",
      "type"        : "number",
      "default"     : 5
    },
    {
      "title"       : "Minimum Value",
      "name"        : "minValue",
      "description" : "The lower bound of the random numbers being generated",
      "type"        : "number"
    }
}
```

#### param.json
```
{
  "pollInterval"    : 1000,
  "minValue"        : 0,
  "maxValue"        : 100
}
```

#### init.lua

```lua
local framework = require('framework')
local Plugin = framework.Plugin
local RandomDataSource = framework.RandomDataSource

local params = framework.params
-- For compatability with lua versions prior to 4.1.2
if framework.plugin_params.name == nil then
  params.name = 'Boundary Demo Plugin'
  params.version = '1.0'
  params.tags = 'applicationA'
end
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
> boundary-meter --lua init.lua
```

### Example 2 - Chaining DataSources

In this example we will see how to extract the page total bytes for a dynamic web request using two chained DataSources. We first simulate a request with a DataSource that returns a tag and then pass this to a WebRequestDataSource to generate a new request. Finally we count the bytes returned by the RequestDataSource to generate the metric.

```lua
local framework = require('framework')
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

### Example 3 - Emitting a metric with various sources

If we have the same metric comming from various sources at the same time, we can pass an structure to the plugin to generate the correct output.

```lua
local framework = require('framework')

local DataSource = framework.DataSource
local Plugin = framework.Plugin
local math = require('math')
local table = require('table')

-- Simulate generating metrics for CPU core utilization.
local cpucores_ds = DataSource:new(function () 
  local info = {
    ['CPU_1'] = math.random(0, 100)/100,
    ['CPU_2'] = math.random(0, 100)/100,
    ['CPU_3'] = math.random(0, 100)/100,
    ['CPU_4'] = math.random(0, 100)/100
  }

  return info;
end)

local params = {pollInterval = 3000}
local plugin = Plugin:new(params, cpucores_ds)
function plugin:onParseValues(data)
  local metrics = {}
  metrics['CPU_CORE'] = {}

  for k, v in pairs(data) do
    table.insert(metrics['CPU_CORE'], {value = v, source = k})
  end
  return metrics
end

plugin:run()
```
The following output will be generated by the Plugin:

```
CPU_CORE 0.740000 CPU_4 1430181477
CPU_CORE 0.080000 CPU_1 1430181477
CPU_CORE 0.340000 CPU_3 1430181477
CPU_CORE 0.570000 CPU_2 1430181480
```
### Example 4 - Creating DataSources dynamically

In this example we will get the page response time for each link on the site http://lua-urers.org/wiki. We create a WebRequestDataSource to get the initial page, parse the links and create a WebRequestDataSource for each link extracted. For each new request we will get the page response time and send it the Plugin to report the metric.


```lua
local framework = require('framework')
local url = require('url')
local Plugin = framework.Plugin
local WebRequestDataSource = framework.WebRequestDataSource
local DataSource = framework.DataSource
local string = require('string')
local table = require('table')
local parseLinks = framework.util.parseLinks
local isRelativeLink = framework.util.isRelativeLink
local absoluteLink = framework.util.absoluteLink

local options = url.parse('http://lua-users.org/wiki/')
options.wait_for_end = true
local ds = WebRequestDataSource:new(options)

ds:chain(function (context, callback, data) 
  local links = parseLinks(data)
  local data_sources = {}
  for i, v in ipairs(links) do
    if isRelativeLink(v) then
      v = absoluteLink('http://lua-users.org', v)
      local options = url.parse(v)
      options.meta = v
      local child_ds = WebRequestDataSource:new(options))
      child_ds:propagate('error', context) -- just propagate any error up-to the chain
      table.insert(data_sources, child_ds) 
    end
  end
  return data_sources
end)

local params = { pollInterval = 2000 }
local plugin = Plugin:new(params, ds)

function plugin:onParseValues(data, extra)
  local result = {}

  result['PAGE_RESPONSE_TIME'] = { value = extra.response_time, source = extra.info }

  return result
end

plugin:run()
```
Running this Plugin we will see the following ouptut:

```sh
> /usr/bin/boundary-meter --lua init.lua
_bevent:Boundary Plugin up : version 1.0|t:info|tags:lua,plugin
PAGE_RESPONSE_TIME 1.000000 http://lua-users.org/wiki/ 1430248084
PAGE_RESPONSE_TIME 1.000000 http://lua-users.org/wiki/LuaDirectory 1430248084
PAGE_RESPONSE_TIME 1.000000 http://lua-users.org/wiki/LuaAddons 1430248084
PAGE_RESPONSE_TIME 1.000000 http://lua-users.org/wiki/LuaFaq 1430248084
PAGE_RESPONSE_TIME 1.000000 http://lua-users.org/wiki/SampleCode 1430248084
PAGE_RESPONSE_TIME 1.000000 http://lua-users.org/wiki/CastOfCharacters 1430248084
PAGE_RESPONSE_TIME 1.000000 http://lua-users.org/wiki/WikiHelp 1430248084
PAGE_RESPONSE_TIME 1.000000 http://lua-users.org/wiki/GuestBook 1430248084
PAGE_RESPONSE_TIME 1.000000 http://lua-users.org/wiki/RecentChanges 1430248084
```
