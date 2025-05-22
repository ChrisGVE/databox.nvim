-- databox.lua — Neovim plugin for deeply encrypted persistent dictionary

local M = {}

-- Configuration variables
local private_key_file = nil
local public_key = nil
local store_path = nil
local data = {}

-- Utility: Determine the storage path
local function resolve_store_path()
	local xdg = os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")
	return xdg .. "/nvim/databox.txt"
end

-- Utility: Run a command with input/output
local function run_pipe(cmd, mode, input)
	local handle = io.popen(cmd, mode)
	if not handle then
		return nil, "Failed to open pipe"
	end
	if mode == "w" then
		if input then
			handle:write(input)
		end
		handle:close()
		return true
	elseif mode == "r" then
		local output = handle:read("*a")
		handle:close()
		return output
	end
end

-- Recursively encrypt all strings in a table
local function deep_encrypt(obj)
	if type(obj) == "table" then
		local result = {}
		for k, v in pairs(obj) do
			local ek = deep_encrypt(k)
			local ev = deep_encrypt(v)
			if ek and ev then
				result[ek] = ev
			end
		end
		return result
	elseif type(obj) == "string" then
		local tmp_in = os.tmpname()
		local fout = io.open(tmp_in, "w")
		if not fout then
			return nil
		end
		fout:write(obj)
		fout:close()
		local cmd = string.format("age -e -r %q %q", public_key, tmp_in)
		local out = run_pipe(cmd, "r")
		os.remove(tmp_in)
		return out and out:gsub("\n", "\\n") or nil
	else
		return obj
	end
end

-- Recursively decrypt all strings in a table
local function deep_decrypt(obj)
	if type(obj) == "table" then
		local result = {}
		for k, v in pairs(obj) do
			local dk = deep_decrypt(k)
			local dv = deep_decrypt(v)
			if dk and dv then
				result[dk] = dv
			end
		end
		return result
	elseif type(obj) == "string" then
		local tmp_in = os.tmpname()
		local fout = io.open(tmp_in, "w")
		if not fout then
			return nil
		end
		fout:write(obj:gsub("\\n", "\n"))
		fout:close()
		local cmd = string.format("age -d -i %q %q", private_key_file, tmp_in)
		local decrypted = run_pipe(cmd, "r")
		os.remove(tmp_in)
		return decrypted and decrypted:gsub("\n$", "") or nil
	else
		return obj
	end
end

-- Public API: Initialize the plugin
function M.setup(opts)
	assert(opts and opts.private_key, "Missing private_key in setup")
	assert(opts and opts.public_key, "Missing public_key in setup")
	private_key_file = opts.private_key
	public_key = opts.public_key
	store_path = resolve_store_path()
	M.load()
end

-- Public API: Save encrypted dictionary to disk
function M.save()
	local enc = deep_encrypt(data)
	if not enc then
		return
	end
	local ok, json = pcall(vim.fn.json_encode, enc)
	if not ok then
		return
	end
	local f = io.open(store_path, "w")
	if not f then
		return
	end
	f:write(json)
	f:close()
end

-- Public API: Load and decrypt dictionary from disk
function M.load()
	local f = io.open(store_path, "r")
	if not f then
		data = {}
		return
	end
	local json = f:read("*a")
	f:close()
	local ok, parsed = pcall(vim.fn.json_decode, json)
	if ok and type(parsed) == "table" then
		data = deep_decrypt(parsed)
	else
		data = {}
	end
end

-- Public API: Check if a key exists
function M.exists(key)
	return type(key) == "string" and data[key] ~= nil
end

-- Public API: Set a new key
function M.set(key, value, save)
	assert(type(key) == "string", "Key must be a string")
	if data[key] ~= nil then
		error("Key already exists: " .. key)
	end
	data[key] = value
	if save == nil or save then
		M.save()
	end
end

-- Public API: Update existing key
function M.update(key, value, save)
	assert(type(key) == "string", "Key must be a string")
	data[key] = value
	if save == nil or save then
		M.save()
	end
end

-- Public API: Retrieve value for a key
function M.get(key)
	assert(type(key) == "string", "Key must be a string")
	return data[key]
end

return M
