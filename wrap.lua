local FS1 = "4e33d6c6-7229-40da-9688-e1276d9f978b"
local SCREEN = "73822386-3f58-4d0b-8fad-fdf5a34d0a8a"
local KEYBOARD = "de3153c6-0a80-4c1a-9e5b-867935d759df"
local EEPROM = "56af8068-b597-4336-bfdb-b9df970309d8"
local io = io
local print = print
require "socket"
real_print = print
unicode = {
len = function(str)
	return string.len(str)
end,
sub = function (str,a,b)
	return string.sub(str,a,b)
end
}
local unicode = unicode
component = {
type = function (address)
	if address == FS1 then return "filesystem"
	elseif address == SCREEN then return "screen"
	else
		print("unknown addr",address)
	end
end,
slot = function(address)
	if address == FS1 then return 1
	elseif address == SCREEN then return 2
	elseif address == EEPROM then return 3
	else
		print("slot unknown for",address)
		return nil,"no such component"
	end
end,
methods = function(address)
	local info = {direct=true, getter=false, setter=false }
	if address == FS1 then
		return {open=info, close=info, read=info, list=info, exists=info }
	end
end,
isAvailable = function(name)
	if name == "gpu" then return true
	elseif name == "screen" then return true
	else return false
	end
end
}
os = {
sleep = function (time)
	socket.select(nil,nil,time)
end
}
local os = os
local component = component
-- from machine.lua in open computers
local function spcall(...)
	local result = table.pack(pcall(...))
	if not result[1] then
print(debug.traceback())
		error(tostring(result[2]), 0)
	else
		return table.unpack(result, 2, result.n)
	end
end
function checkArg(n, have, ...)
	have = type(have)
	local function check(want, ...)
		if not want then
			return false
		else
			return have == want or check(...)
		end
	end
	if not check(...) then
		local msg = string.format("bad argument #%d (%s expected, got %s)",n, table.concat({...}, " or "), have)
		error(msg, 3)
	end
end
local proxyCache = setmetatable({}, {__mode="v"})
local componentCallback = {
	__call = function(self, ...)
		return component.invoke(self.address, self.name, ...)
	end,
	__tostring = function(self)
		return component.doc(self.address, self.name) or "function"
	end
}
function component.proxy(address)
	local type, reason = spcall(component.type, address)
	if not type then
		return nil, reason
	end
	local slot, reason = spcall(component.slot, address)
	if not slot then
		return nil, reason
	end
	if proxyCache[address] then
		return proxyCache[address]
	end
	local proxy = {address = address, type = type, slot = slot, fields = {}}
	local methods, reason = spcall(component.methods, address)
	if not methods then
		return nil, reason
	end
	for method, info in pairs(methods) do
		if not info.getter and not info.setter then
			proxy[method] = setmetatable({address=address,name=method}, componentCallback)
		else
			proxy.fields[method] = info
		end
	end
	setmetatable(proxy, componentProxy)
	proxyCache[address] = proxy
	return proxy
end
-- end of copy/paste
function component.list(filter)
	print("listing:",filter)
	local ret = {}
	local first = nil
	local firstname = nil
	function test(name)
		-- todo, substring search
		if filter == name then
			return true
		elseif filter == nil then
			return true
		end
		return false
	end
	function addDev(addr,name)
		ret[addr] = name
		if first == nil then
			first = addr
			firstname = name
		end
	end
	if test("eeprom") then addDev(EEPROM,"eeprom") end
	if test("screen") then addDev(SCREEN,"screen") end
	if test("gpu") then addDev("1d721b0c-b681-4b80-ba46-7eacbc6d1cfb","gpu") end
	if test("filesystem") then addDev(FS1,"filesystem") end
	for k,v in pairs(ret) do print(k,v) end
	print(ret)
	local meta = {}
	meta.__call = function ()
		-- TODO, iterator
		local hack = first
		first = nil
		return hack,firstname
	end
	setmetatable(ret,meta)
	return ret
end
local eepromUserData = nil;
function component.invoke(address,method,...)
	if address == nil then
		print(debug.traceback())
	end
	print("calling ",method," on ",address)
	--if ... then print(...) end
	if address == FS1 then
		if method == "open" then
			local filename = ...
			if filename == "FS1/boot/00_base.lua" then print(debug.traceback()) end
			return io.open("FS1/"..filename,"r")
		elseif method == "read" then
			local fh,size = ...
			if size == math.huge then size = 4096 end
			return fh:read(size)
		elseif method == "close" then
			local fh = ...
			return fh:close()
		elseif method == "list" then
			local dir = ...
			if dir == "boot" then
				return {"00_base.lua","01_process.lua","02_os.lua","04_component.lua"}
			else
				print("list",dir)
				return {}
			end
		elseif method == "exists" then
			local filename = ...
			local f=io.open("FS1/"..filename,"r")
			if f~=nil then io.close(f) return true else return false end
		end
	elseif address == SCREEN then
		if method == "getKeyboards" then
			return KEYBOARD
		end
	elseif address == EEPROM then
		if method == "setData" then
			eepromUserData = ...
		elseif method == "getData" then
			return eepromUserData
		end
	end
end
function component.doc()
end
computer = {
pushSignal = function (...)
	print("unfinished pushSignal",...)
end,
freeMemory = function()
	return 1024*1024
end,
uptime = function ()
	-- TODO
	return 0
end
}
function computer.beep(...)
	print("BEEP!",...)
end
function table.pack(...)
	return { n=select("#",...), ... }
end
function table.unpack(...)
	return unpack(...)
end
function load(...)
	local chunk = loadstring(...)
	setfenv(chunk, getfenv())
	return chunk
end

local fh = assert(io.open("bios.lua","r"))
local eeprom = fh:read("*all")
local prom,err = loadstring(eeprom,"=eeprom")
if prom then
	setfenv(prom, getfenv())
	local result,ret = pcall(prom)
	if result then
		io.stdout:write("sucess")
	else
		print("fail:",ret)
	end
else
	io.stdout:write("failed to load prom:"..err.."\n")
end
