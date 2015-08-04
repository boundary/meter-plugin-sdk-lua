-- Copyright 2015 Boundary, Inc.
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--    http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.-

---------------
-- A Boundary Plugin Framework for easy development of custom Boundary.com plugins.
--
-- [https://github.com/boundary/boundary-plugin-framework-lua](https://github.com/boundary/boundary-plugin-framework-lua)
-- @module Boundary Plugin Framework for LUA
-- @author Gabriel Nicolas Avellaneda <avellaneda.gabriel@gmail.com>
-- @license Apache 2.0
-- @copyright 2015 Boundary, Inc

local Emitter = require('core').Emitter
local Object = require('core').Object
local timer = require('timer')
local math = require('math')
local string = require('string')
local os = require('os')
local fs = require('fs')
local http = require('http')
local https = require('https')
local net = require('net')
local bit = require('bit')
local table = require('table')
local childprocess = require('childprocess')
local json = require('json')
local _url = require('url')
local framework = {}
local querystring = require('querystring')
local boundary = require('boundary')
local io = require('io')
local hrtime = require('uv').Process.hrtime

local callable = function (class, func)
  class.meta.__call = func 
end

local factory = function (class)
  local mt = getmetatable(class)
  mt.__call = function (t, ...)
    return t:new(...)
  end
end

framework.version = '0.9.9'
framework.boundary = boundary
framework.params = boundary.param or json.parse(fs.readFileSync('param.json')) or {}
framework.plugin_params = boundary.plugin or json.parse(fs.readFileSync('plugin.json')) or {}
framework.metrics = boundary.metrics or json.parse(fs.readFileSync('metrics.json')) or {}
local plugin_params = framework.plugin_params

framework.string = {}
framework.functional = {}
framework.table = {}
framework.util = {}
framework.http = {}

do
  local encode_alphabet = {
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '+', '/'
  }

  local decode_alphabet = {}
  for i, v in ipairs(encode_alphabet) do
    decode_alphabet[v] = i-1
  end

  local function translate(sixbit)
    return encode_alphabet[sixbit + 1]
  end

  local function unTranslate(char)
    return decode_alphabet[char]
  end

  local function toBytes(str)
    return { str:byte(1, #str) }
  end

  local function mask6bits(byte)
    return bit.band(0x3f, byte)
  end

  local function pad(bytes)
    local to_pad = 3 - #bytes % 3
    while to_pad > 0 and to_pad ~= 3 do
      table.insert(bytes, 0x0)
      to_pad = to_pad - 1
    end

    return bytes
  end

  local function encode(str, no_padding)
    local bytes = toBytes(str)
    local bytesTotal = #bytes
    if bytesTotal == 0 then
        return ''
    end
    bytes = pad(bytes)
    local output = {}

    local i = 1
    while i < #bytes do
      -- read three bytes into a 24 bit buffer to produce 4 coded bytes.
      local buffer = bit.rol(bytes[i], 16)
      buffer = bit.bor(buffer, bit.rol(bytes[i+1], 8))
      buffer = bit.bor(buffer, bytes[i+2])

      -- get six bits at a time and translate to base64
      for j = 18, 0, -6 do
        table.insert(output, translate(mask6bits(bit.ror(buffer, j))))
      end
      i = i + 3
    end
    -- If was padded then replace with = characters
    local padding_char = no_padding and '' or '='

    if bytesTotal % 3 == 1  then
      output[#output-1] = padding_char
      output[#output] = padding_char
    elseif bytesTotal % 3 == 2 then
      output[#output] = padding_char
     end

    return table.concat(output)
  end

  local function decode(str)
    -- take four encoded octets and produce 3 decoded bytes.
    local output = {}
    local i = 1
    while i < #str do
      local buffer = 0
      -- get the octet represented by the coded base64 char
      -- shift left by 6 bits and or
      -- mask the 3 bytes, and convert to ascii

      for j = 18, 0, -6 do
        local octet = unTranslate(str:sub(i, i))
        buffer = bit.bor(bit.rol(octet, j), buffer)
        i = i + 1
      end

      for j = 16, 0, -8 do
        local byte = bit.band(0xff, bit.ror(buffer, j))
        table.insert(output, byte)
      end
    end

    return string.char(unpack(output))
  end
  framework.util.base64Encode = encode
  framework.util.base64Decode = decode
end
local base64Encode = framework.util.base64Encode

do
  local _pairs = pairs({ a = 0 }) -- get the generating function from pairs
  local gpairs = function(t, key)
    local value
    key, value = _pairs(t, key)
    return key, key, value
  end
  local function iterator (obj, param, state)
    if (type(obj) == 'table') then
      if #obj > 0 then
        return ipairs(obj)
      else
        return gpairs, obj, nil
      end
    elseif type(obj) == 'function' then
      return obj, param, state
    end
    error(("object %s of type %s can not be iterated."):format(obj, type(obj))) 
  end

  local function call(func, state, ...)
    if state == nil then
      return nil
    end
    return state, func(...)
  end
  
  local function _each(func, gen, param, state)
    repeat
      state = call(func, gen(param, state))
    until state == nil
  end
  local function each(func, gen, param, state)
    _each(func, iterator(gen, param, state))
  end
  framework.functional.each = each

  local function toMap(gen, param, state)
    local t = {}
    each(function (k, v) 
      v = v or k
      t[k] = v 
    end, gen, param, state)
    return t
  end
  framework.functional.toMap = toMap

  -- naive version of map
  local function map(func, xs)
    local t = {}
    table.foreach(xs, function (i, v) 
      --t[i] = func(v, i) 
      table.insert(t, func(v))
    end)  
    return t
  end
  framework.functional.map = map
 
  -- naive version of filter
  local function filter(func, xs)
    local t = {}
    table.foreach(xs, function (i, v)
      if func(v) then
        table.insert(t, v)
        --t[i] = v
      end
    end)
    return t
  end
  framework.functional.filter = filter
  -- naive version of reduce
  local function reduce(func, acc, xs)
    table.foreach(xs, function (i, v)
      acc = func(acc, v)
    end)
    return acc
  end
  framework.functional.reduce = reduce
end


--- String functions
-- @section string

--- Trim blanks from the string.
-- @param self The string to trim
-- @return The string with trimmed blanks
function framework.string.trim(self)
  return string.match(self, '^%s*(.-)%s*$')
end
local trim = framework.string.trim

function framework.util.parseUrl(url, parseQueryString)
  assert(url, 'parse expect a non-nil value')
  url = trim(url)
  local href = url
  local chunk, protocol = url:match("^(([a-zA-Z0-9+]+)://)")
  url = url:sub((chunk and #chunk or 0) + 1)

  local auth
  chunk, auth = url:match('(([0-9a-zA-Z]+:?[0-9a-zA-Z]+)@)')
  url = url:sub((chunk and #chunk or 0) + 1)

  local host
  local hostname
  local port
  if protocol then
    host = url:match("^([%a%.%d-]+:?%d*)")
    if host then
      hostname = host:match("^([^:/]+)")
      port = host:match(":(%d+)$")
    end
  url = url:sub((host and #host or 0) + 1)
  end

  host = hostname -- Just to be compatible with our code base. Discuss this.

  local path
  local pathname
  local search
  local query
  local hash
  hash = url:match("(#.*)$")
  url = url:sub(1, (#url - (hash and #hash or 0)))

  if url ~= '' then
    path = url
    local temp
    temp = url:match("^[^?]*")
    if temp ~= '' then
      pathname = temp
    end
    temp = url:sub((pathname and #pathname or 0) + 1)
    if temp ~= '' then
      search = temp
    end
    if search then
    temp = search:sub(2)
      if temp ~= '' then
        query = temp
      end
    end
  end

  if parseQueryString then
    query = querystring.parse(query)
  end

  return {
    href = href,
    protocol = protocol,
    host = host,
    hostname = hostname,
    port = port,
    path = path or '/',
    pathname = pathname or '/',
    search = search,
    query = query,
    auth = auth,
    hash = hash
  }
end

_url.parse = framework.util.parseUrl

--- Returns the char from a string at the specified position. 
-- @param str the string from were a char will be extracted. 
-- @param pos the position in the string. Should be a numeric value greater or equal than 1.
-- @return the char at the specified position. If the position does not exist in the string, nil is returned. 
function framework.string.charAt(str, pos)
  return string.sub(str, pos, pos)
end
local charAt = framework.string.charAt

--- Check if a string contains the specified pattern.
-- @param pattern the pattern to look for.
-- @param str the string to search from
-- @return true if the pattern exist inside the string.
function framework.string.contains(pattern, str)
  local s,_ = string.find(str, pattern)
  return s ~= nil
end

--- Replace placeholders with named keys inside a string.
-- @param str the string that has placeholders to be replaced. In example "Hello, {name}"
-- @param map a table with a list of key and values for replacement.
-- @return a string with all the ocurrences of placedholders replaced.
function framework.string.replace(str, map)
  for k, v in pairs(map) do
    str = str:gsub('{' .. k .. '}', v)
  end
  return str
end
local replace = framework.string.replace

--- Escape special characters used by pattern matching functionality.
-- @param str the string that will be escaped.
-- @return a new string with all the special characters escaped.
function framework.string.escape(str)
  local s, _ = string.gsub(str, '%.', '%%.')
  s, _ = string.gsub(s, '%-', '%%-')
  return s
end

--- Decode an URL encoded string
-- @param str the URL encoded string
-- @return a new string decoded
function framework.string.urldecode(str)
  local char, gsub, tonumber = string.char, string.gsub, tonumber
  local function _(hex) return char(tonumber(hex, 16)) end

  str = gsub(str, '%%(%x%x)', _)

  return str
end

--- URL encode a string
-- @param str the string that will be encoded
-- @return a new string URL encoded
function framework.string.urlencode(str)
  if str then
    str = string.gsub(str, '\n', '\r\n')
    str = string.gsub(str, '([^%w])', function(c)
      return string.format('%%%02X', string.byte(c))
    end)
  end

  return str
end

function framework.string.jsonsplit(self)
  local outResults = {}
  local theStart,theSplitEnd = string.find(self, "{")
  local numOpens = theStart and 1 or 0
  theSplitEnd = theSplitEnd and theSplitEnd + 1
  while theSplitEnd < string.len(self) do
    if self[theSplitEnd] == '{' then
      numOpens = numOpens + 1
    elseif self[theSplitEnd] == '}' then
      numOpens = numOpens - 1
    end
    if numOpens == 0 then
      table.insert( outResults, string.sub ( self, theStart, theSplitEnd ) )
      theStart,theSplitEnd = string.find(self, "{", theSplitEnd)
      numOpens = theStart and 0 or 1
      theSplitEnd = theSplitEnd or string.len(self)
    end
    theSplitEnd = theSplitEnd + 1
  end
  return outResults
end

--- TODO: To be composable we need to change this interface to gsplit(separator, data)
function framework.string.gsplit(data, separator)
  local pos = 1
  local iter = function()
    if not pos then -- stop the generator (maybe using stateless is a better option?)
      return nil
    end
    local s, e = string.find(data, separator, pos)
    if s then
      local part = string.sub(data, pos, s-1)
      pos = e + 1
      return part
    else
      local part = string.sub(data, pos)
      pos = nil
      return part
    end
  end
  return iter, data, 1
end
local gsplit = framework.string.gsplit

--- Split as an iterator
-- @param data that will be splitted.
-- @param separator a string or character for the split
-- @func func a function to call for each splitted part of the string
function framework.string.isplit(data, separator, func)
  for part in gsplit(data, separator) do
    func(part)
  end
end
local isplit = framework.string.isplit

-- Split a string into parts
-- @param data the string to split
-- @param separator a string or character that breaks each part of the string.
-- @return a table with all the parts splitted from the string.
function framework.string.split(data, separator)
  if not data then
    return nil
  end
  local result = {}
  isplit(data, separator, function (part) table.insert(result, part) end)
  return result
end
local split = framework.string.split

--- Check if the string is empty. Before checking it will be trimmed to remove blank spaces.
function framework.string.isEmpty(str)
  return (str == nil or framework.string.trim(str) == '')
end
local isEmpty = framework.string.isEmpty

--- If not empty returns the value. If is empty, an a default value was specified, it will return that value.
-- @param str the string that will be checked for empty
-- @param default a default value that will be returned if the string is empty
-- @return str or default is str is an empty string.
function framework.string.notEmpty(str, default)
  return not framework.string.isEmpty(str) and str or default
end
local notEmpty = framework.string.notEmpty

--- Join two strings using a character
-- @param s1 any string
-- @param s2 any string
-- @param char a character
-- @return a new string with the join of s1 and s2 with character inbetween.
function framework.string.concat(s1, s2, char)
  if isEmpty(s2) then
    return s1
  end
  return s1 .. char .. s2
end

--- Utility functions.
-- Various functions that helps with common tasks.
-- @section util

--- Parses anchor links from an HTML string
-- @param html_str the html string from where links will be parsed.
-- @return a table with extracted links
function framework.util.parseLinks(html_str)
  local links = {}
  for link in string.gmatch(html_str, '<a%s+h?ref=["\']([^"^\']+)["\'][^>]*>[^<]*</%s*a>') do
    table.insert(links, link)
  end

  return links
end

--- Creates an absolute link from a basePath and a relative link.
-- @param basePath the base path to generate an absolute link.
-- @param link a relative link
-- @return A string that represents the absolute link.
function framework.util.absoluteLink(basePath, link)
  return basePath .. trim(link)
end

--- Check if the a link is a relative one.
-- @param link the link to check
-- @return true if the link is relative.  false otherwise.
function framework.util.isRelativeLink(link)
  return not string.match(string.lower(link), '^https?')
end

--- Wraps a function to calculate the time passed between the wrap and the function execution.
function framework.util.timed(func, startTime)
  startTime = startTime or os.time()
  return function(...)
    return os.time() - startTime, func(...)
  end
end

--- Check if an HTTP Status code is of a success kind.
-- @param status the status code number
-- @return true if status code is a success one.
function framework.util.isHttpSuccess(status)
  return status >= 200 and status < 300
end

--- Round a number by the to the specified decimal places.
-- @param val the value that will be rounded
-- @param decimal the number of decimal places
-- @return the val rounded at decimal places
function framework.util.round(val, decimal)
  assert(val, 'round expect a non-nil value')
  if (decimal) then
    return math.floor( (val * 10^decimal) + 0.5) / (10^decimal)
  else
    return math.floor(val+0.5)
  end
end

--- Return the current timestamp
-- @return the current timestamp
function framework.util.currentTimestamp()
  return os.time()
end

--- Convert megabytes to bytes.
-- @param mb the number of megabytes
-- @return the number of bytes that represent mb 
function framework.util.megaBytesToBytes(mb)
  return mb * 1024 * 1024
end

--- Represent a number as a percentage
-- @param number the number to represent as a percentage
-- @return number/100
function framework.util.percentage(number)
  return number/100
end

--- Pack a tuple that represent a metric into a table
function framework.util.pack(metric, value, timestamp, source)
  if value then
    return { metric = metric, value = value, timestamp = timestamp, source = source }
  end
  return nil
end

--- Pack a value for a metric into a table
function framework.util.packValue(value, timestamp, source)
  return { value = value, timestamp = timestamp, source = source }
end

function framework.util.ipack(metrics, ...)
  table.insert(metrics, framework.util.pack(...))  
end

--- Create an auth for HTTP Basic Authentication
function framework.util.auth(username, password)
  return notEmpty(username) and notEmpty(password) and (username .. ':' .. password) or nil
end

-- Returns an string for a Boundary Meter event.
-- @param type could be 'CRITICAL', 'ERROR', 'WARN', 'INFO'
function framework.util.eventString(type, message, tags)
  tags = tags or ''
  return string.format('_bevent:%s|t:%s|tags:%s', message, type, tags)
end
local eventString = framework.util.eventString

--- Functional functions
-- @section functional 

--- Return the partial application of a function.
-- @param func a function that will be partially applied.
-- @param x the parameter to partially apply.
-- @return A new function with the application of the x parameter.
function framework.functional.partial(func, x)
  return function (...)
    return func(x, ...)
  end
end

--- Represents the identity function  
-- @param x any value
-- @return x
function framework.functional.identity(...)
  return ... 
end
local identity = framework.functional.identity

-- Propagate the event to another emitter.
function Emitter:propagate(eventName, target, transform)
  if (target and target.emit) then
    transform = transform or identity
    self:on(eventName, function (...) target:emit(eventName, transform(...)) end)
    return target
  end
  return self
end

--- Compose to functions g(f(x))
-- @param f any function
-- @param g any function
-- @return A new function that is the composition of f and g
function framework.functional.compose(f, g)
  return function(...)
    return g(f(...))
  end
end

--- Table functions
-- @section table

--- Get the value at the specified key for a table
-- @param key the key for indexing the table
-- @param t a any table
-- @return the value at the specified key. If t is not a table nil will be returned.
function framework.table.get(key, t)
  if type(t) ~= 'table' then
    return nil
  end
  return t[key]
end

--- Find a value inside a table
-- @param a predicate function that test the items of the table
-- @return the first item in the table that satisfy the test condition
function framework.table.find(func, t)
  for i, v in pairs(t) do
    if func(v, i, t) then
      return v, i 
    end
  end
  return nil
end

--- Get the number of elements of a table
-- @param t a table
-- @return the number of items from the table
function framework.table.count(t)
  local count = 0
  for _ in pairs(t) do
    count = count + 1
  end
  return count
end

function framework.table.toSet(t)
  if not t then return nil end

  local result = {}
  local n = 0
  for _, v in pairs(t) do
    v = trim(v)
    if v ~= '' then
      n = n + 1  
      result[v] = true
    end
  end
  return n > 0 and result or nil
end

function framework.util.add(a, b)
  return a + b
end
local add = framework.util.add 

local reduce = framework.functional.reduce

function framework.util.sum(t)
  return reduce(add, 0, t)
end
local sum = framework.util.sum

--- Get the mean value of the elements from a table
-- @param t a table 
-- @return the mean value 
function framework.util.mean(t)
  local count = table.getn(t) 
  if count == 0 then
    return 0
  end
  local s = sum(add, 0, t) 
  return s/count
end

function framework.util.ratio(x, y)
  if y and tonumber(y) > 0 then
    return x / y
  end
  return 0
end

function framework.util.parseJson(body)
  return pcall(json.parse, body)
end
local parseJson = framework.util.parseJson

--- Get returns true if there is any element in the table.
-- @param t a table
-- @return true if there is any element in the table, false otherwise
function framework.table.hasAny(t)
  return next(t) ~= nil
end

--- Get the index in the table for the specified value.
-- @param self any table
-- @param value the value to look for
-- @return a number that represent the index of value in the table. If the value does not exist, or t is not a table, nil will be returned.
function framework.table.indexOf(self, value)
  if type(self) ~= 'table' then
    return nil
  end
  for i,v in ipairs(self) do
    if value == v then
      return i
    end
  end
  return nil
end

--- Get all the keys from the  table.
-- @param t any table
-- @return a table with all the keys of t
function framework.table.keys(t)
  local result = {}
  for k,_ in pairs(t) do
    table.insert(result, k)
  end

  return result
end

--- Get a deep copy of a table
-- @param t a table to be cloned
-- @return a new table that is the copy of t.
local clone
clone = function (t)
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
framework.table.clone = clone

--- Creates a table from a list of keys and values
-- @param keys a list of keys
-- @param values a list of kayes
-- @return a new table with the corresponding keys and values
function framework.table.create(keys, values)
  local result = {}
  for i, k in ipairs(keys) do
    if notEmpty(trim(k)) then
      result[k] = values[i]
    end
  end
  return result
end

--- Merge to tables
-- @param t1 any table
-- @param t2 any table
-- @return return a new table with t1 and t2 merged.
function framework.table.merge(t1, t2)
  local output = clone(t1)
  for k, v in pairs(t2) do
    if type(k) == 'number' then
      table.insert(output, v)
    else
      output[k] = v
    end
  end
  return output
end
local merge = framework.table.merge

--- Try to coerce a number or at least to a string.
-- @param x the value that will be converted.
-- @return return a number if x can be parsed, 0 if is an empty string or a string if is not convertible to a number.
function framework.util.parseValue(x)
  return tonumber(x) or (isEmpty(x) and 0) or tostring(x) or 0
end
local parseValue = framework.util.parseValue

local map = framework.functional.map

-- TODO: Convert this to a generator
-- TODO: Use gsplit instead of split
function framework.string.parseCSV(data, separator, comment, header)
  separator = separator or ','
  local parsed = {}
  local lines = split(data, '\n')
  local headers
  if header then
    local header_line = string.match(lines[1], comment .. '%s*([' .. separator .. '%S]+)%s*')
    headers = split(trim(header_line), separator)
  end
  for _, v in ipairs(lines) do
    if notEmpty(v) then
      if not comment or not (charAt(v, 1) == comment) then
        local values = split(v, separator)
        values = map(parseValue, values)
        if headers then
          table.insert(parsed, framework.table.create(headers, values))
        else
          table.insert(parsed, values)
        end
      end
    end
  end
  return parsed
end

-- You can call framework.string() to export all functions to the string table to the global table for easy access.
local function exportable(t)
  setmetatable(t, {
    __call = function (u, warn)
      for k,v in pairs(u) do
        if (warn) then
          if _G[k] ~= nil then
            process.stderr:write('Warning: Overriding function ' .. k ..' on global space.')
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

--- Cache class.
-- Work as a cache of values
-- @type Cache
local Cache = Object:extend()
factory(Cache, factory)

--- Cache constructor.
-- @name Cache:new
-- @param func a function that provides a default value for an inexisting key.
function Cache:initialize(func)
  self.func = func
  self.cache = {}
end

--- Get a cached value or create a default one.
-- @param key the key associated with the cached value.
-- @return return the value associated with the speciifed key or create a new default value using the constructor function.
function Cache:get(key)
  assert(key, 'Cache:get key must be non-nil')
  local result = self.cache[key]
  if not result then
    result = self.func()
    self.cache[key] = result -- now cache the value
  end
  return result
end

framework.Cache = Cache

--- DataSource class.
-- @type DataSource
local DataSource = Emitter:extend()
--- DataSource is the base class for any DataSource. By default accepts a function/closure that will be called each fetch call.
framework.DataSource = DataSource
--- DataSource constructor.
-- @name DataSource:new
-- @param func a function that will be called on each fetch request.
function DataSource:initialize(func)
  self.func = func
end

--- Chain the fetch result to the execution of the fetch on another DataSource.
-- @param data_source the DataSource that will be fetched passing the transformed result of the fetch operation.
-- @param transform (optional) transform function to be called on the result of the fetch operation in this instance.
-- @usage: first_ds:chain(second_ds, transformFunc):chain(third_ds, transformFunc)
function DataSource:chain(data_source, transform)
  assert(data_source, 'chain: data_source not set.')
  self.chained = { data_source, transform }

  return data_source
end

function DataSource:onFetch()
  self:emit('onFetch')
end

--- Fetch data from the datasource. This is an abstract method.
-- @param context Context information, this can be the caller or another object that you want to set.
-- @param callback A function that will be called when the fetch operation is done. If there are another DataSource chained, this call will be made when the ultimate DataSource in the chain is done.
-- @param params Additional parameters that will be send to the internal DataSource functioan.
function DataSource:fetch(context, callback, params)

  self:onFetch(context, callback, params)

  local result = self.func(params)
  self:processResult(context, callback, result)
end

function DataSource:processResult(context, callback, ...)
  if self.chained then
    local ds, transform = unpack(self.chained)
    if type(ds) == 'function' then
      local f = ds
      local data_sources = f(self, callback, ...)
      if type(data_sources) == 'table' then
        for i, v in ipairs(data_sources) do
          v:fetch(self, callback, ...) -- TODO: This datasources where created by the function chained. Pass parameters on the constructor?
        end
      else
        --TODO: Use the result of f() or just result? because f can be also a transform function and if you are asigning to a chain the result of this will be the continuated value.
        callback(...)
      end
    else
      transform = transform or identity
      ds:fetch(self, callback, transform(...))
    end
  else
    callback(...)
  end
end

--- CachedDataSource class
-- @type CachedDataSource
local CachedDataSource = DataSource:extend()

--- CachedDataSource allows to cache DataSource fetch calls and refresh  
framework.CachedDataSource = CachedDataSource
function CachedDataSource:initialize(ds, refresh_by)
  self.ds = ds
  self.refresh_by = refresh_by
  self.expiration = nil
  ds:propagate('error', self)
end

--- Fetch from the provided DataSource or return the cached value
function CachedDataSource:fetch(context, callback, params)
  local now = os.time()
  if not self.expiration or (now >= self.expiration and self.refresh_by) then
    self.expiration = now + (self.refresh_by or 0)
    local cache = function (result)
      self.cached = result
      self:processResult(context, callback, result)
    end
    self.ds:fetch(context, cache, params)
  else
    self:processResult(context, callback, self.cached)
  end
end

--- NetDataSource class.
-- @type NetDataSource
local NetDataSource = DataSource:extend()

--- NetDataSource constructor
-- @param host the host to connect
-- @param port the port to connect
-- @param close_connection if true, the connection will be closed on each fetch operation.
-- @return a new instance of NetDataSource 
function NetDataSource:initialize(host, port, close_connection)
  self.host = host
  self.port = port
  self.close_connection = close_connection or false 
end

function NetDataSource:onFetch(socket)
  error('you must override the NetDataSource:onFetch')
end

--- Fetch data from the configured host and port
-- @param context A context object that can be used by the fetch operation.
-- @func callback A callback that gets called when there is some data on the socket.
function NetDataSource:fetch(context, callback)
  self:connect(function ()
    self:onFetch(self.socket)
    if callback then
      self.socket:once('data', function (data)
        callback(data, {context = self})
        if self.close_connection then
          self:disconnect()
        end
      end)
    else
      if self.close_connection then
        self:disconnect()
      end
    end
  end)
end

--- Disconnect the internal socket 
function NetDataSource:disconnect()
  self.socket:done()
  self.socket = nil
end

--- Connect to the initialized host and port and call the callback function on success.
-- @func callback a callback to run on a successfull connection. If called for an already open connection, the callback will be executed immediatelly.
function NetDataSource:connect(callback)
  if self.socket and not self.socket.destroyed then
    callback()
    return
  end
  assert(notEmpty(self.port), 'You must specify a port to connect to.')
  assert(notEmpty(self.host), 'You must specify a host to connect to.')
  self.socket = net.createConnection(self.port, self.host, callback) 
  self.socket:on('error', function (err) self:emit('error', 'Socket error: ' .. err.message) end)
end

framework.NetDataSource = NetDataSource

--- DataSourcePoller class
-- @type DataSourcePoller
local DataSourcePoller = Emitter:extend()
factory(DataSourcePoller)

--- DataSourcePoller constructor.
-- DataSourcePoller Polls a DataSource at the specified interval and calls a callback when there is some data available.
-- @int pollInterval number of milliseconds to poll for data
-- @param dataSource A DataSource to be polled
-- @name DataSourcePoller:new
function DataSourcePoller:initialize(pollInterval, dataSource)
  self.pollInterval = (pollInterval < 1000 and 1000) or pollInterval
  self.dataSource = dataSource
  dataSource:propagate('error', self)
end

function DataSourcePoller:_poll(callback)
  local success, err = pcall(function () 
    self.dataSource:fetch(self, callback)
  end)
  if not success then
    self:emit('error', err) 
  end
  timer.setTimeout(self.pollInterval, function () self:_poll(callback) end)
end

--- Start polling for data.
-- @func callback A callback function to call when the DataSource returns some data.
function DataSourcePoller:run(callback)
  if self.running then
    return
  end

  self.running = true
  self:_poll(callback)
end

--- Plugin Class.
-- @type Plugin
local Plugin = Emitter:extend()
framework.Plugin = Plugin
factory(Plugin)

--- Plugin constructor.
-- A base plugin implementation that accept a dataSource and polls periodically for new data and format the output so the boundary meter can collect the metrics.
-- @param params is a table of options that can be:
--  pollInterval (optional) the poll interval between data fetchs. This is required if you pass a plain DataSource and not a DataSourcePoller.
--  source (optional)
--  version (options) the version of the plugin.
-- @param dataSource A DataSource that will be polled for data.
-- If is a DataSource a DataSourcePoller will be created internally to pool for data
-- It can also be a DataSourcePoller or PollerCollection.
-- @name Plugin:new
function Plugin:initialize(params, dataSource)

  assert(dataSource, 'Plugin:new dataSource is required.')

  local pollInterval = (params.pollInterval < 1000 and 1000) or params.pollInterval

  if not Plugin:_isPoller(dataSource) then
    self.dataSource = DataSourcePoller:new(pollInterval, dataSource)
    self.dataSource:propagate('error', self)
  else
    self.dataSource = dataSource
    dataSource:propagate('error', self)
  end
  self.source = notEmpty(params.source, os.hostname())
  if (plugin_params) then
    self.version = notEmpty(plugin_params.version, notEmpty(params.version, '0.0'))
    self.name = notEmpty(plugin_params.name, notEmpty(params.name, 'Boundary Plugin'))
    self.tags = notEmpty(plugin_params.tags, notEmpty(params.tags, ''))
  else
    self.version = notEmpty(params.version, '0.0')
    self.name = notEmpty(params.name, 'Boundary Plugin')
    self.tags = notEmpty(params.tags, '')
  end

  self:on('error', function (err) self:error(err) end)
end

function Plugin:printError(title, host, source, msg)
  self:printEvent('error', title, host, source, msg)
end

function Plugin:printInfo(title, host, source, msg)
  self:printEvent('info', title, host, source, msg)
end

function Plugin:printWarn(title, host, source, msg)
  self:printEvent('warn', title, host, source, msg)
end

function Plugin:printCritical(title, host, source, msg)
  self:printEvent('critical', title, host, source, msg)
end

function Plugin.formatMessage(name, version, title, host, source, msg)
  if title and title ~= "" then title = '-'..title else title = "" end
  if msg and msg ~= "" then msg = '|m:'..msg else msg = "" end
  if host and host ~= "" then host = '|h:'..host else host = "" end
  if source and source ~= "" then source = '|s:'..source else source = "" end
  return string.format('%s version %s%s%s%s%s', name, version, title, msg, host, source)
end

function Plugin.formatTags(tags)
  tags = tags or {}
  if type(tags) == 'string' then
    tags = split(tags, ',')
  end
  return table.concat(merge({'lua', 'plugin'}, tags), ',')
end

function Plugin:printEvent(eventType, title, host, source, msg)
  msg = Plugin.formatMessage(self.name, self.version, title, host, source, msg)
  local tags = Plugin.formatTags(self.tags)
  print(eventString(eventType, msg, tags))
end

--- Emit an event to the Boundary platform. 
-- @type a string that represent the type of the event. It can be 'info', 'warning', 'critical', 'error'.
-- @param msg an string message to send
function Plugin:emitEvent(type, title, host, source, msg)
  self:printEvent(type, title, host, source, msg)
end

function Plugin:_isPoller(poller)
  return poller.run
end

--- Called when the Plugin detect and error in one of his components.
-- @param err the error emitted by one of the component that failed.
function Plugin:error(err)
  err = self:onError(err)
  local msg
  if type(err) == 'table' and err.message then
    msg = err.message
  else
    msg = tostring(err)
  end
  local source = err.source or self.source
  self:printError(self.source .. ' Error', self.source, source, msg)
end

function Plugin:onError(err)
  return err 
end

--- Run the plugin and start polling from the configured DataSource
function Plugin:run()
  self:emitEvent('info', self.source .. ' Status', self.source, self.source, 'Up')
  self.dataSource:run(function (...) self:parseValues(...) end)
end

function Plugin:parseValues(...)
  local success, result = pcall(self.onParseValues, self, unpack({...}))
  if not success then
    self:emitEvent('critical', result)
  elseif result then
    self:report(result)
  end
end

function Plugin:onParseValues(...)
  error('You must implement onParseValues')
end

function Plugin:report(metrics)
  self:emit('report')
  self:onReport(metrics)
end

--- Called by the framework when there are some metrics to send to Boundary platform
-- @param metrics a table that represent the metrics to send
function Plugin:onReport(metrics)
  -- metrics can be { metric = value }
  -- or {metric = {value, source}}
  -- or {metric = {{value, source}, {value, source}, {value, source}}
  -- or {metric, value, source}
  -- or {{metric, value, source, timestamp}}
  for metric, v in pairs(metrics) do
    -- { { metric, value .. }, { metric, value .. } }
    if type(metric) == 'number' then
      print(self:format(v.metric, v.value, notEmpty(v.source, self.source), v.timestamp))
    elseif type(v) ~= 'table' then
      print(self:format(metric, v, self.source))
    elseif type(v[1]) ~= 'table' and v.value then
      -- looking for { metric = { value, source, timestamp }}
      local source = v.source or self.source
      local value = v.value
      local timestamp = v.timestamp
      print(self:format(metric, value, source, timestamp))
    else
      -- looking for { metric = {{ value, source, timestamp }}}
      for _, j in pairs(v) do
        local source = j.source or self.source
        local value = j.value
        local timestamp = j.timestamp
        print(self:format(metric, value, source, timestamp))
      end
    end
  end
end

function Plugin:format(metric, value, source, timestamp)
  self:emit('format')
  return self:onFormat(metric, value, source, timestamp)
end

--- Called by the framework before formating the metric output.
-- @string metric the metric name
-- @number value the value to format
-- @string source the source to report for the metric
-- @param timestamp the time the metric was retrieved
-- You can override this on your plugin instance.
function Plugin:onFormat(metric, value, source, timestamp)
  source = string.gsub(source, '[!@#$%%^&*() {}<>/\\|]', '_')
  if timestamp then
    return string.format('%s %f %s %s', metric, value, source, timestamp)
  else
    return string.format('%s %f %s', metric, value, source)
  end
end

--- Acumulator Class
-- @type Accumulator
local Accumulator = Emitter:extend()
factory(Accumulator)

--- Accumulator constructor.
-- Track values and return the delta for accumulated metrics.
-- @name Accumulator:new
function Accumulator:initialize()
  self.map = {}
end

--- Accumulates a value an return the delta between the actual an latest value.
-- @string key the key for the item
-- @param value the item value
-- @return diff the delta between the latests and actual value.
function Accumulator:accumulate(key, value)
  assert(value, "Accumulator:accumulate#value must not be null for key " .. key)

  local oldValue = self.map[key]
  if oldValue == nil then
    oldValue = value
  end

  self.map[key] = value
  local diff = value - oldValue

  return diff
end

--- Return the last accumulated valor or 0 if there isnt any for the key
-- @param key the key for the item to retrieve
function Accumulator:get(key)
  return self.map[key] or 0
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

-- The object instance can be used as a function call that calls accumulate.
callable(Accumulator, function (t, ...) return t:accumulate(...) end)

framework.Accumulator = Accumulator

--- A Collection of DataSourcePoller
-- @type PollerCollection
local PollerCollection = Emitter:extend()
factory(PollerCollection)

--- PollerCollection constructor
-- @param[opt] pollers a list of poller to initially add to this collection.
function PollerCollection:initialize(pollers)
  self.pollers = pollers or {}
  -- TODO: Configure propagation of errors.
end

--- Add a poller to the collection
-- @param poller a DataSourcePoller to add to the collection
function PollerCollection:add(poller)
  table.insert(self.pollers, poller)
  poller:propagate('error', self)
end

--- Run all the DataSourcePollers in the collection.
-- @func callback a callback function that will be passed to the DataSourcePollers.
function PollerCollection:run(callback)
  if self.running then
    return
  end

  self.running = true
  for _,p in pairs(self.pollers) do
    p:run(callback)
  end
end

--- WebRequestDataSource Class
-- @type WebRequestDataSource
local WebRequestDataSource = DataSource:extend()

--- WebRequestDataSource
-- @name WebRequestDataSource:new
-- @param params a table with the configuraiton parameters. 
-- TODO: Document params options
function WebRequestDataSource:initialize(params)
  local options = params or {}
  if type(params) == 'string' then
    options = _url.parse(params)
  end

  self.wait_for_end = options.wait_for_end or false

  self.options = options
  self.info = options.meta
end

function WebRequestDataSource:onError(...)
  return ...
end

--- Fetch data from the initialized url
function WebRequestDataSource:fetch(context, callback, params)
  assert(callback, 'WebRequestDataSource:fetch: callback is required')

  local start_time = hrtime()
  local options = clone(self.options)

  -- Replace variables
  params = params or {}
  if type(params) == 'table' then
    options.path = replace(options.path, params)
    options.pathname = replace(options.pathname, params)
  end

  local buffer = ''

  local success = function (res)
    if self.wait_for_end then
      res:on('end', function ()
        local exec_time = hrtime() - start_time
        success, error = pcall(function () 
          self:processResult(context, callback, buffer, {context = self, info = self.info, response_time = exec_time, status_code = res.statusCode}) end)
        if not success then
          self:emit('error', error)
        end
        res:destroy()
      end)
    else
      res:once('data', function (data)
        local exec_time = hrtime() - start_time
        buffer = buffer .. data
        if not self.wait_for_end then
          self:processResult(context, callback, buffer, {context = self, info = self.info, response_time = exec_time, status_code = res.statusCode})
          res:destroy()
        end
      end)
    end

    res:on('data', function (d)
      buffer = buffer .. d
    end)

    res:propagate('data', self)
    res:propagate('error', self)
  end

  options.headers = {}
  options.headers['User-Agent'] = 'Boundary Meter <support@boundary.com>'

  if options.auth then
    options.headers['Authorization'] = 'Basic ' .. base64Encode(options.auth, false)
  end

  local data = options.data
  local body
  if data and table.getn(data) > 0 then
    body = table.concat(data, '&')
    options.headers['Content-Type'] = 'application/x-www-form-urlencoded'
    options.headers['Content-Length'] = #body
  end

  local req
  if string.lower(options.protocol) == 'https' then
    req = https.request(options, success)
  else
    req = http.request(options, success)
  end

  if body and #body > 0 then
    req:write(body)
  end

  req:propagate('error', self, function (err)
    err.context = self
    err.params = params
    return err
  end)
  req:done()
end

--- RandomDataSource class returns a random number each time it get called.
-- @type RandomDataSource
-- @param context the object that called the fetch
-- @func callback A callback to call with the random generated number
-- @usage local ds = RandomDataSource:new(1, 100) -- Generate numbers from 1 to 100
local RandomDataSource = DataSource:extend()

--- RandomDataSource constructor
-- @int minValue the lower bounds for the random number generation.
-- @int maxValue the upper bound for the random number generation.
-- @usage local ds = RandomDataSource:new(1, 100)
function RandomDataSource:initialize(minValue, maxValue)
  DataSource.initialize(self, function ()
    return math.random(minValue, maxValue)
  end)
end

--- CommandOutputDataSource. A DataSource for parsing the output of command line programs. 
-- @type CommandOutputDataSource
local CommandOutputDataSource = DataSource:extend()

--- CommandOutputDataSource constructor
-- @param params a table with path and args of the command to execute
function CommandOutputDataSource:initialize(params)
  -- TODO: Handle commands for each operating system.
  assert(params, 'CommandOuptutDataSource:new expect a non-nil params parameter')
  self.path = params.path
  self.args = params.args
  self.success_exitcode = params.success_exitcode or 0
  self.info = params.info
  self.callback_on_errors = params.callback_on_errors
  self.use_popen = params.use_popen
end

--- Returns true if is a success exitcode.
-- @param exitcode the exit code to check for success
-- @return true if exitcode is success 
function CommandOutputDataSource:isSuccess(exitcode)
  return tonumber(exitcode) == self.success_exitcode
end

--- Returns the output of execution of the command
function CommandOutputDataSource:fetch(context, callback, parser, params)
  local output = ''

  if self.use_popen then
    local proc, err = io.popen(self.path .. " " .. table.concat(self.args, ' '), 'r')
    if not proc then
      self:emit('error', err)
      return
    end
    output = proc:read('*all')
    local result = {proc:close()}
    callback({context = self, info = self.info, output = output})
  else
    local proc = childprocess.spawn(self.path, self.args)
    local code, ended
    proc:propagate('error', self)
    proc.stdout:on('data', function (data) output = output .. data end)
    proc.stderr:on('data', function (data) output = output .. data end)

    local function done()
      if not code or not ended then
        return
      end

      if not self:isSuccess(code) then
        self:emit('error', {message = 'Command terminated with exitcode \'' .. code .. '\' and message \'' .. string.gsub(output, '\r?\n', ' ') .. '\''})
        if not self.callback_on_errors then
          return
        end
      end
      if callback then
        process.nextTick(function ()
          callback({context = self, info = self.info, output = output})
        end)
      end
    end

    proc.stdout:on('end', function ()
      ended = true
      done()
    end)
    proc:on('exit', function (exitcode)
      code = exitcode
      done()
    end)
  end
end


--- MeterDataSource class.
-- @type MeterDataSource
local MeterDataSource = NetDataSource:extend()

--- MeterDatasource to get data from the meter. The meter has various metrics already for use inside plugins.
-- @name MeterDataSource:new
function MeterDataSource:initialize(host, port)
  host = host or '127.0.0.1'
  port = port or 9192
  NetDataSource.initialize(self, host, port)
end

function MeterDataSource:fetch(context, callback)
  local parse = function (value)
    local success, parsed = parseJson(value)
    if not success then
      self:emit('error', string.gsub(parsed, '\n', ' ')) 
      return
    end
    local result = {}
    if parsed.result.status ~= 'Ok' then
      self:emit('error', 'Error with status: ' .. parsed.result.status)
      return
    end

    local query_metric = parsed.result.query_metric
    -- TODO: Return a generator
    if query_metric then
      for i = 1, table.getn(query_metric), 3 do
        table.insert(result, {metric = query_metric[i], value = query_metric[i+1], timestamp = query_metric[i+2]})
      end
    end
    callback(result)
  end
  NetDataSource.fetch(self, context, parse)
end

--- Returns a json formatted string for query a metric
-- @param params the option for query a metric
function MeterDataSource:queryMetricCommand(params)
  params = params or { match = ''}
  return '{"jsonrpc":"2.0","method":"query_metric","id":1,"params":' .. json.stringify(params) .. '}\n'
end

local FileReaderDataSource = DataSource:extend()
function FileReaderDataSource:initialize(path)
  self.path = path 
end

function FileReaderDataSource:fetch(context, func, params)
  if not fs.existsSync(self.path) then
    self:emit('error', 'The "' .. self.path .. '" was not found.')
  else 
    local success, result = pcall(fs.readFileSync, self.path)
	  if not success then
      self:emit('error', failure)
    else
      func(result)
    end
  end
end

framework.FileReaderDataSource = FileReaderDataSource
framework.CommandOutputDataSource = CommandOutputDataSource
framework.RandomDataSource = RandomDataSource
framework.DataSourcePoller = DataSourcePoller
framework.WebRequestDataSource = WebRequestDataSource
framework.PollerCollection = PollerCollection
framework.MeterDataSource = MeterDataSource

return framework
