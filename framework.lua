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

local framework = {}

local Plugin = Emitter:extend()
framework.Plugin = Plugin

framework.boundary = boundary

function Plugin:initialize(params)
	self.pollInterval = 1000
	self.source = os.hostname()
	self.minValue = 0
	self.maxValue = 10
	self.version = params.version or '0.0'
	self.name = params.name or 'Boundary Plugin'

	if params ~= nil then
		self.pollInterval = params.pollInterval or self.pollInterval
		self.source = params.source or self.source
		self.minValue = params.minValue or self.minValue
		self.maxvalue = params.maxValue or self.minValue
	end

	print("_bevent:" .. self.name .. " up : version " .. self.version ..  "|t:info|tags:lua,plugin")
end

function Plugin:poll()
	
	self:emit('before_poll')
	
	self:onPoll()

	self:emit('after_poll')
	timer.setTimeout(self.pollInterval, function () self.poll(self) end)
end

function Plugin:onPoll()
	local metrics = self:getMetrics()

	self:report(metrics)
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

function Plugin:onGetMetrics()
	local value = math.random(self.minValue, self.maxValue)
	return {BOUNDARY_LUA_SAMPLE = value}
end

function Plugin:getMetrics()
    local metrics = self:onGetMetrics()	

	return metrics
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

function HttpPlugin:error(err)
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
			local msg = 'Error while receiving a responde: ' .. err
			self.error(msg)
		end)

	end)
	
	req:on('error', function (err)
		local msg = 'Error while sending a request: ' .. err
		self.error(msg)
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

return framework
