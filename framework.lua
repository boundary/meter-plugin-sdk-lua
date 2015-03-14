-- [author] Gabriel Nicolas Avellaneda <avellaneda.gabriel@gmail.com>
local boundary = require('boundary')
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

local framework = {}

framework.string = {}
framework.functional = {}
framework.table = {}
framework.util = {}

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

local DataSource = Emitter:extend()
framework.DataSource = DataSource
function DataSource:initialize(params)
	self.params = params
end

function DataSource:fetch(caller, callback)
	error('fetch: you must implement on class or object instance.')
end

local NetDataSource = DataSource:extend()
function NetDataSource:initialize(host, port)
	self.host = host
	self.port = port
end

function NetDataSource:onFetch(socket)
	p('you must override the NetDataSource:onFetch')
end

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

local Plugin = Emitter:extend()
framework.Plugin = Plugin

framework.boundary = boundary

function Plugin:poll()
	
	self:emit('before_poll')
	
	self:onPoll()

	self:emit('after_poll')
	timer.setTimeout(self.pollInterval, function () self.poll(self) end)
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

function Plugin:onFormat(metric, value, source, timestamp)
	return string.format('%s %f %s %s', metric, value, source, timestamp)
end

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
	self.dataSource:fetch(self, function (data) self:parseValues(data) end )	
end

function Plugin:parseValues(data)
	local metrics = self:onParseValues(data)

	self:report(metrics)
end

function Plugin:onParseValues(data)
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

function Plugin:error(err)
	local msg = tostring(err)

	print(msg)
end

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

local Accumulator = Emitter:extend()
function Accumulator:initialize()
	self.map = {}
end

function Accumulator:accumulate(key, value)
	local oldValue = self.map[key]
	if oldValue == nil then
		oldValue = value	
	end

	self.map[key] = value
	local diff = value - oldValue

	return diff
end

function Accumulator:reset(key)
	self.map[key] = nil
end

function Accumulator:resetAll()
	self.map = {}
end

framework.Accumulator = Accumulator

return framework
