---------------
---- ## A Boundary Plugin Framework for Luvit.
----
---- For easy development of custom Boundary.com plugins.
----
---- [Github Page](https://github.com/GabrielNicolasAvellaneda/boundary-plugin-framework-lua)
----
---- @author Gabriel Nicolas Avellaneda <avellaneda.gabriel@gmail.com>
---- @copyright Boundary.com 2015
---- @license MIT
---------------
local fs = require('fs')
local json = require('json')
local Emitter = require('core').Emitter
local Error = require('core').Error
local Object = require('core').Object
local Process = require('uv').Process
local timer = require('timer')
local math = require('math')
local string = require('string')
local os = require('os')
local io = require('io')
local http = require('http')
local table = require('table')
local net = require('net')
local json = require('json')
local framework = {}
local params = {}

-- import param.json data into a Lua table (boundary.param)
local json_blob
if (pcall(function () json_blob = fs.readFileSync("param.json") end)) then
  pcall(function () params = json.parse(json_blob) end)
else
	print('param.json not found!')
end

framework.params = params


framework.string = {}
framework.functional = {}
framework.table = {}
framework.util = {}
framework.http = {}

function framework.http.get(options, data, callback, dataType, debug)
	local headers = {}
	if type(options.headers) == 'table' then
		headers = options.headers
	end

	if dataType == 'json' then
		headers['Accept'] = 'application/json'
	end
	
	local reqOptions = {
		host = options.host,
		port = options.port,
		path = options.path,
		headers = headers
	}

	local req = http.request(reqOptions, function (res) 


		local response = ''
		res:on('end', function ()
			if dataType == 'json' then
				response = json.parse(response)	
			end

			if callback then callback(response) end
		end)

		res:on('data', function (chunk) 
			if debug then
				print(chunk)
			end
			response = response .. framework.string.trim(chunk)
		end)

		-- Propagate errors
		res:on('error', function (err)  req:emit('error', err.message) end)
	end)

	if data ~= nil then
		req:write(data)
	end
	req:done()

	return req
end

function framework.http.post(options, data, callback, dataType)
	local headers = {} 
	if type(options.headers) == 'table' then
		headers = options.headers
	end

	if dataType == 'json' then
		headers['Content-Type'] = 'application/json'
		headers['Content-Length'] = #data 
		headers['Accept'] = 'application/json'
	end

	local reqOptions = {
		host = options.host,
		port = options.port,
		path = options.path,
		method = 'POST',
		headers = headers
	}

	local req = http.request(reqOptions, function (res) 
	
		local response = ''
		res:on('end', function () 
			if dataType == 'json' then
				response = json.parse(response)	
			end

			if callback then callback(response) end	
		end)

		res:on('data', function (chunk) 
			
			response = response .. chunk
		end) 

		res:on('error', function (err)  req:emit('error', err.message) end)
	end)

	req:write(data)
	req:done()

	return req
end

function framework.util.megaBytesToBytes(mb)
	return mb * 1024 * 1024
end

function framework.functional.partial(func, x) 
	return function (...)
		return func(x, ...) 
	end
end

function framework.functional.compose(f, g)
	return function(...) 
		return g(f(...))
	end
end

function framework.table.get(key, map)
	if type(map) ~= 'table' then
		return nil 
	end

	return map[key]
end

function framework.table.keys(t)
	local result = {}
	for k,_ in pairs(t) do
		table.insert(result, k)
	end

	return result
end

function framework.table.clone(t)
	if type(t) ~= 'table' then return t end

	local meta = getmetatable(t)
	local target = {}
	for k,v in pairs(t) do
		if type(v) == 'table' then
			target[k] = clone(v)
		else
			target[k] = v
		end
	end
	setmetatable(target, meta)
	return target
end

function framework.string.contains(pattern, str)
	local s,e = string.find(str, pattern)

	return s ~= nil
end

function framework.string.escape(str)
	local s, c = string.gsub(str, '%.', '%%.')
	s, c = string.gsub(s, '%-', '%%-')
	return s
end

function framework.string.split(self, pattern)
	local outResults = {}
	local theStart = 1
	local theSplitStart, theSplitEnd = string.find(self, pattern, theStart)
	while theSplitStart do
	  table.insert( outResults, string.sub( self, theStart, theSplitStart-1 ) )
	  theStart = theSplitEnd + 1
	  theSplitStart, theSplitEnd = string.find( self, pattern, theStart )
	end
	table.insert( outResults, string.sub( self, theStart ) )
	return outResults
end

function framework.string.trim(self)
   return string.match(self,"^()%s*$") and "" or string.match(self,"^%s*(.*%S)" )
end 

function framework.string.isEmpty(str)
	return (str == nil or framework.string.trim(str) == '')
end

function framework.string.notEmpty(str)
	return not framework.string.isEmpty(str)
end

-- You can call framework.string() to export all functions to the string table to the global table for easy access.
function exportable(t)
	setmetatable(t, {
		__call = function (t, warn)
			for k,v in pairs(t) do 
				if (warn) then
					if _G[k] ~= nil then
						print('Warning: Overriding function ' .. k ..' on global space.')
					end
				end
				_G[k] = v
			end
		end
	})
end

-- Allow to export functions to global table
exportable(framework.string)
exportable(framework.util)
exportable(framework.functional)
exportable(framework.table)
exportable(framework.http)

-- TODO: Commit this to luvit repository
function Emitter:propagate(eventName, target)
	if target and target.emit then
		self:on(eventName, function (...) target:emit(eventName, ...) end)
		return target
	end

	return self
end

--- DataSource class.
-- @type DataSource
local DataSource = Emitter:extend()
--- DataSource is the base class for any DataSource you want to implement.
framework.DataSource = DataSource
--- DataSource constructor.
-- @name DataSource:new
function DataSource:initialize(params)
	self.params = params
end

--- Fetch data from the datasource. This is an abstract method.
function DataSource:fetch(caller, callback)
	error('fetch: you must implement on class or object instance.')
end

--- NetDataSource class.
-- @type NetDataSource
local NetDataSource = DataSource:extend()
function NetDataSource:initialize(host, port)

	self.host = host
	self.port = port
end

function NetDataSource:onFetch(socket)
	p('you must override the NetDataSource:onFetch')
end

--- Fetch data from the configured host and port
-- @param context How calls this functions
-- @func callback A callback that gets called when there is some data on the socket.
function NetDataSource:fetch(context, callback)

	local socket
	socket = net.createConnection(self.port, self.host, function ()

		self:onFetch(socket)

		if callback then
			socket:once('data', function (data)
				callback(data)
				socket:shutdown()
			end)
		else
			socket:shutdown()
		end

		end)
	socket:on('error', function (err) self:emit('error', 'Socket error: ' .. err.message) end)
end

framework.NetDataSource = NetDataSource

--- Plugin Class.
-- @type Plugin
local Plugin = Emitter:extend()
framework.Plugin = Plugin

function Plugin:_poll()

	self:emit('before_poll')
	
	self:onPoll()

	self:emit('after_poll')
	timer.setTimeout(self.pollInterval, function () self:_poll() end)
end

--- Run the plugin and start polling from the configured DataSource
function Plugin:run()
	self:_poll()	
end

function Plugin:report(metrics)
	self:emit('report')
	self:onReport(metrics)
end

function currentTimestamp()
	return os.time()
end

function Plugin:onReport(metrics)
	for metric, value in pairs(metrics) do
		print(self:format(metric, value, self.source, currentTimestamp()))
	end
end

function Plugin:format(metric, value, source, timestamp)
	self:emit('format')
	return self:onFormat(metric, value, source, timestamp) 
end

--- Called by the framework before formating the metric output. 
-- @string metric the metric name
-- @param value the value to format
-- @string source the source to report for the metric
-- @param timestamp the time the metric was retrieved
-- You can override this on your plugin instance.
function Plugin:onFormat(metric, value, source, timestamp)
	return string.format('%s %f %s %s', metric, value, source, timestamp)
end

--- Plugin constructor.
-- A base plugin implementation that accept a dataSource and polls periodically for new data and format the output so the boundary meter can collect the metrics.
-- @param params is a table of options that can be:
-- 	pollInterval (requried) the poll interval between data fetchs.
-- 	source (optional)
--	version (options) the version of the plugin. 		
-- @param dataSource A DataSource that will be polled for data.
-- @name Plugin:new
function Plugin:initialize(params, dataSource)
	self.pollInterval = params.pollInterval or 1000
	self.source = params.source or os.hostname()
	self.dataSource = dataSource
	self.version = params.version or '1.0'
	self.name = params.name or 'Boundary Plugin'

	self.dataSource:on('error', function (msg) self:error(msg) end)

    print("_bevent:" .. self.name .. " up : version " .. self.version ..  "|t:info|tags:lua,plugin")
end

function Plugin:onPoll()
	self.dataSource:fetch(self, function (...) self:parseValues(...) end )	
end

function Plugin:parseValues(...)
	local metrics = self:onParseValues(...)

	self:report(metrics)
end

function Plugin:onParseValues(...)
	p('Plugin:onParseValues')
	return {}	
end

local CommandPlugin = Plugin:extend()
framework.CommandPlugin = CommandPlugin

function CommandPlugin:initialize(params)
	Plugin.initialize(self, params)

	if not params.command then
		error('params.command undefined. You need to define the command to excetue.')
	end
	
	self.command = params.command
end

function CommandPlugin:execCommand(callback)
	local proc = io.popen(self.command, 'r')	
	local output = proc:read("*a")
	proc:close()
	if callback then
		callback(output)
	end
end

function CommandPlugin:onPoll()
	self:execCommand(function (output) self.parseCommandOutput(self, output) end)
end

function CommandPlugin:parseCommandOutput(output)
	local metrics = self:onParseCommandOutput(output)
	self:report(metrics)
end

function CommandPlugin:onParseCommandOutput(output)
	print(output)
	return {}
end

local NetPlugin = Plugin:extend()
framework.NetPlugin = NetPlugin

local HttpPlugin = Plugin:extend()
framework.HttpPlugin = HttpPlugin

function HttpPlugin:initialize(params)
	Plugin.initialize(self, params)
	
	self.reqOptions = {
		host = params.host,
		port = params.port,
		path = params.path
	}
end

--- Called when the Plugin detect and error in one of his components.
function Plugin:error(err)
	local msg = ''
	if type(err) == 'table' then
		msg = err.message
	else
		msg = tostring(err)
	end
	print(msg)
end

local PollingPlugin = Plugin:extend()

framework.PollingPlugin = PollingPlugin

function HttpPlugin:makeRequest(reqOptions, successCallback)
	local req = http.request(reqOptions, function (res)


		local data = ''
		
		res:on('data', function (chunk)
			data = data .. chunk	
			successCallback(data)
			-- TODO: Verify when data its complete or when we need to use de end
		end)

		res:on('error', function (err)
			local msg = 'Error while receiving a response: ' .. err.message
			self:error(msg)
		end)

	end)
	
	req:on('error', function (err)
		local msg = 'Error while sending a request: ' .. err.message
		self:error(msg)
	end)

	req:done()
end

function HttpPlugin:onPoll()
	self:makeRequest(self.reqOptions, function (data)
		self:parseResponse(data)
	end)
end

function HttpPlugin:parseResponse(data)
	local metrics = self:onParseResponse(data) 
	self:report(metrics)
end

function HttpPlugin:onParseResponse(data)
	-- To be overriden on class instance
	print(data)
	return {}
end

--- Acumulator Class
-- @type Accumulator
local Accumulator = Emitter:extend()
 
--- Accumulator constructor.
-- Keep track of values so we can return the delta for accumulated metrics.
-- @name Accumulator:new
function Accumulator:initialize()
	self.map = {}
end

--- Accumulates a value an return the delta between the actual an latest value.
-- @string key the key for the item
-- @param value the item value
-- @return diff the delta between the latests and actual value.
function Accumulator:accumulate(key, value)
	local oldValue = self.map[key]
	if oldValue == nil then
		oldValue = value	
	end

	self.map[key] = value
	local diff = value - oldValue

	return diff
end

--- Reset the specified value
-- @string key A key to untrack
function Accumulator:reset(key)
	self.map[key] = nil
end

--- Clean up all the tracked key/values.
function Accumulator:resetAll()
	self.map = {}
end

framework.Accumulator = Accumulator

--- DataSourcePoller class
-- @type DataSourcePoller
local DataSourcePoller = Emitter:extend() 

--- DataSourcePoller constructor.
-- DataSourcePoller Polls a DataSource at the specified interval and calls a callback when there is some data available. 
-- @int pollInterval number of milliseconds to poll for data 
-- @param dataSource A DataSource to be polled
-- @name DataSourcePoller:new 
function DataSourcePoller:initialize(pollInterval, dataSource)
	self.pollInterval = pollInterval
	self.dataSource = dataSource
	dataSource:propagate('error', self)
end

function DataSourcePoller:_poll(callback)
	self.dataSource:fetch(self, callback)

	timer.setTimeout(self.pollInterval, function () self:_poll(callback) end)
end

--- Start polling for data.
-- @func callback A callback function to call when the DataSource returns some data. 
function DataSourcePoller:run(callback)
	self:_poll(callback)
end

--- RandomDataSource class
-- @type RandomDataSource
local RandomDataSource = DataSource:extend()

--- RandomDataSource constructor
-- @int minValue the lower bounds for the random number generation.
-- @int maxValue the upper bound for the random number generation.
--@usage local ds = RandomDataSource:new(1, 100)
function RandomDataSource:initialize(minValue, maxValue)
	self.minValue = minValue
	self.maxValue = maxValue
end

--- Returns a random number
-- @param context the object that called the fetch
-- @func callback A callback to call with the random generated number
-- @usage local ds = RandomDataSource:new(1, 100) -- Generate numbers from 1 to 100
--ds.fetch(nil, print)
function RandomDataSource:fetch(context, callback)
	
	local value = math.random(self.minValue, self.maxValue)
	if not callback then error('fetch: you must set a callback when calling fetch') end

	callback(value)
end

framework.RandomDataSource = RandomDataSource
framework.DataSourcePoller = DataSourcePoller

return framework
