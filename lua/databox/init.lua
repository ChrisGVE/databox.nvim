-- databox.nvim - Neovim plugin for deeply encrypted persistent dictionary

---@class DataboxConfig
---@field private_key string Path to the private key file (required)
---@field public_key string Public key string or path to public key file (required)
---@field store_path? string Custom storage path (optional)
---@field encryption_cmd? string Encryption command template (optional, default: "age")
---@field decryption_cmd? string Decryption command template (optional, default: "age")

---@class Databox
local M = {}

-- Internal state
---@type DataboxConfig|nil
local config = nil
---@type string|nil
local resolved_store_path = nil
---@type table
local data = {}

-- Default configuration
---@type DataboxConfig
local default_config = {
	private_key = "",
	public_key = "",
	store_path = nil,
	encryption_cmd = "age -e -a -r %s", -- Use ASCII armor (-a) for safe JSON storage
	decryption_cmd = "age -d -i %s",
}

---Safely escape shell arguments
---@param arg string
---@return string
local function shell_escape(arg)
	return "'" .. arg:gsub("'", "'\"'\"'") .. "'"
end

---Generate a secure temporary file path
---@return string|nil, string?
local function secure_tmpfile()
	local handle = io.popen("mktemp 2>/dev/null", "r")
	if not handle then
		return nil, "Failed to create secure temporary file"
	end
	local tmpfile = handle:read("*l")
	handle:close()

	if not tmpfile or tmpfile == "" then
		return nil, "Failed to get temporary file path"
	end

	return tmpfile
end

---Clean up temporary file
---@param filepath string
local function cleanup_tmpfile(filepath)
	if filepath and filepath ~= "" then
		os.remove(filepath)
	end
end

---Determine the storage path
---@return string
local function resolve_store_path()
	if config and config.store_path then
		return config.store_path
	end

	local xdg = os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")
	return xdg .. "/nvim/databox.txt"
end

---Run a command safely with proper error handling
---@param cmd string
---@param input? string
---@return string|nil, string?
local function run_command(cmd, input)
	local tmpfile_in, err

	if input then
		tmpfile_in, err = secure_tmpfile()
		if not tmpfile_in then
			return nil, err or "Failed to create input temporary file"
		end

		local file = io.open(tmpfile_in, "w")
		if not file then
			cleanup_tmpfile(tmpfile_in)
			return nil, "Failed to write to temporary file"
		end

		file:write(input)
		file:close()

		cmd = cmd .. " " .. shell_escape(tmpfile_in)
	end

	local handle = io.popen(cmd .. " 2>&1", "r")
	if not handle then
		cleanup_tmpfile(tmpfile_in)
		return nil, "Failed to execute command"
	end

	local output = handle:read("*a")
	local success = handle:close()
	cleanup_tmpfile(tmpfile_in)

	if not success then
		return nil, "Command failed: " .. (output or "unknown error")
	end

	return output
end

---Check if a value can be safely serialized
---@param obj any
---@return boolean, string?
local function is_serializable(obj)
	local obj_type = type(obj)

	if obj_type == "function" or obj_type == "userdata" or obj_type == "thread" then
		return false, "Cannot serialize " .. obj_type .. " values"
	end

	if obj_type == "table" then
		for k, v in pairs(obj) do
			local k_ok, k_err = is_serializable(k)
			if not k_ok then
				return false, "Key error: " .. (k_err or "unknown")
			end

			local v_ok, v_err = is_serializable(v)
			if not v_ok then
				return false, "Value error: " .. (v_err or "unknown")
			end
		end
	end

	return true
end

---Encode special values for JSON serialization
---@param obj any
---@return any
local function encode_special_values(obj)
	if obj == nil then
		return { __databox_type = "nil" }
	elseif type(obj) == "table" then
		local result = {}
		local is_empty = true

		for k, v in pairs(obj) do
			result[k] = encode_special_values(v)
			is_empty = false
		end

		-- Mark empty tables specially
		if is_empty then
			return { __databox_type = "empty_table" }
		end

		return result
	else
		return obj
	end
end

---Decode special values from JSON
---@param obj any
---@return any
local function decode_special_values(obj)
	if type(obj) == "table" and obj.__databox_type then
		if obj.__databox_type == "nil" then
			return nil
		elseif obj.__databox_type == "empty_table" then
			return {}
		end
	elseif type(obj) == "table" then
		local result = {}
		for k, v in pairs(obj) do
			result[k] = decode_special_values(v)
		end
		return result
	end

	return obj
end

---Recursively encrypt all strings in a table
---@param obj any
---@return any, string?
local function deep_encrypt(obj)
	-- First encode special values (nil, empty tables)
	local encoded = encode_special_values(obj)

	if type(encoded) == "table" then
		local result = {}
		for k, v in pairs(encoded) do
			local ek, ek_err = deep_encrypt(k)
			if ek == nil and ek_err then
				return nil, "Failed to encrypt key: " .. ek_err
			end

			local ev, ev_err = deep_encrypt(v)
			if ev == nil and ev_err then
				return nil, "Failed to encrypt value: " .. ev_err
			end

			if ek ~= nil then
				result[ek] = ev
			end
		end
		return result
	elseif type(encoded) == "string" then
		if not config then
			return nil, "Plugin not initialized"
		end

		local cmd = string.format(config.encryption_cmd, shell_escape(config.public_key))
		local encrypted, err = run_command(cmd, encoded)

		if not encrypted then
			return nil, err or "Encryption failed"
		end

		-- Store encrypted content directly (ASCII armor is already safe for JSON)
		return encrypted
	else
		return encoded
	end
end

---Recursively decrypt all strings in a table
---@param obj any
---@return any, string?
local function deep_decrypt(obj)
	if type(obj) == "table" then
		local result = {}
		for k, v in pairs(obj) do
			local dk, dk_err = deep_decrypt(k)
			if dk == nil and dk_err then
				return nil, "Failed to decrypt key: " .. dk_err
			end

			local dv, dv_err = deep_decrypt(v)
			if dv == nil and dv_err then
				return nil, "Failed to decrypt value: " .. dv_err
			end

			if dk ~= nil then
				result[dk] = dv
			end
		end

		-- Decode special values after decryption
		return decode_special_values(result)
	elseif type(obj) == "string" then
		if not config then
			return nil, "Plugin not initialized"
		end

		-- ASCII armor format is safe to use directly
		local cmd = string.format(config.decryption_cmd, shell_escape(config.private_key))
		local decrypted, err = run_command(cmd, obj)

		if not decrypted then
			return nil, err or "Decryption failed"
		end

		-- Remove trailing newline that age might add
		return decrypted:gsub("\n$", "")
	else
		return obj
	end
end

---Initialize the plugin with configuration
---@param opts? DataboxConfig User configuration
---@return boolean success
---@return string? error
function M.setup(opts)
	opts = opts or {}

	-- Merge with defaults
	config = vim.tbl_deep_extend("force", default_config, opts)

	-- Validate required fields
	if not config.private_key or config.private_key == "" then
		return false, "Missing required field: private_key"
	end

	if not config.public_key or config.public_key == "" then
		return false, "Missing required field: public_key"
	end

	-- Expand tilde in paths
	config.private_key = vim.fn.expand(config.private_key)
	if config.store_path then
		config.store_path = vim.fn.expand(config.store_path)
	end

	resolved_store_path = resolve_store_path()

	-- Ensure storage directory exists
	local store_dir = vim.fn.fnamemodify(resolved_store_path, ":h")
	if vim.fn.isdirectory(store_dir) == 0 then
		vim.fn.mkdir(store_dir, "p")
	end

	local success, err = M.load()
	if not success then
		return false, "Failed to load existing data: " .. (err or "unknown error")
	end

	return true
end

---Save encrypted dictionary to disk
---@return boolean success
---@return string? error
function M.save()
	if not config then
		return false, "Plugin not initialized. Call setup() first"
	end

	local enc, enc_err = deep_encrypt(data)
	if enc == nil and enc_err then
		return false, "Encryption failed: " .. enc_err
	end

	-- Handle case where data is empty
	if enc == nil then
		enc = {}
	end

	local ok, json = pcall(vim.fn.json_encode, enc)
	if not ok then
		return false, "JSON encoding failed: " .. tostring(json)
	end

	local file, file_err = io.open(resolved_store_path, "w")
	if not file then
		return false, "Failed to open storage file: " .. (file_err or "unknown error")
	end

	file:write(json)
	file:close()

	return true
end

---Load and decrypt dictionary from disk
---@return boolean success
---@return string? error
function M.load()
	if not config then
		return false, "Plugin not initialized. Call setup() first"
	end

	local file = io.open(resolved_store_path, "r")
	if not file then
		-- File doesn't exist yet, start with empty data
		data = {}
		return true
	end

	local json = file:read("*a")
	file:close()

	if not json or json == "" then
		data = {}
		return true
	end

	local ok, parsed = pcall(vim.fn.json_decode, json)
	if not ok then
		return false, "Failed to parse stored data: " .. tostring(parsed)
	end

	if type(parsed) ~= "table" then
		data = {}
		return true
	end

	local decrypted, dec_err = deep_decrypt(parsed)
	if decrypted == nil and dec_err then
		return false, "Decryption failed: " .. dec_err
	end

	data = decrypted or {}
	return true
end

---Check if a key exists
---@param key string
---@return boolean
function M.exists(key)
	assert(type(key) == "string", "Key must be a string")
	return data[key] ~= nil
end

---Set a new key (fails if key already exists)
---@param key string
---@param value any
---@param save? boolean Whether to save immediately (default: true)
---@return boolean success
---@return string? error
function M.set(key, value, save)
	assert(type(key) == "string", "Key must be a string")

	if data[key] ~= nil then
		return false, "Key already exists: " .. key
	end

	local serializable, ser_err = is_serializable(value)
	if not serializable then
		return false, ser_err or "Value is not serializable"
	end

	data[key] = value

	if save == nil or save then
		return M.save()
	end

	return true
end

---Update existing key (fails if key doesn't exist)
---@param key string
---@param value any
---@param save? boolean Whether to save immediately (default: true)
---@return boolean success
---@return string? error
function M.update(key, value, save)
	assert(type(key) == "string", "Key must be a string")

	if not M.exists(key) then
		return false, "Key does not exist: " .. key .. ". Use set() to create new keys"
	end

	local serializable, ser_err = is_serializable(value)
	if not serializable then
		return false, ser_err or "Value is not serializable"
	end

	data[key] = value

	if save == nil or save then
		return M.save()
	end

	return true
end

---Remove a key
---@param key string
---@param save? boolean Whether to save immediately (default: true)
---@return boolean success
---@return string? error
function M.remove(key, save)
	assert(type(key) == "string", "Key must be a string")

	if not M.exists(key) then
		return false, "Key does not exist: " .. key
	end

	data[key] = nil

	if save == nil or save then
		return M.save()
	end

	return true
end

---Retrieve value for a key
---@param key string
---@return any|nil value
---@return string? error
function M.get(key)
	assert(type(key) == "string", "Key must be a string")

	if not M.exists(key) then
		return nil, "Key does not exist: " .. key
	end

	return data[key]
end

---Get all keys
---@return string[]
function M.keys()
	local result = {}
	for k, _ in pairs(data) do
		table.insert(result, k)
	end
	return result
end

---Clear all data
---@param save? boolean Whether to save immediately (default: true)
---@return boolean success
---@return string? error
function M.clear(save)
	data = {}

	if save == nil or save then
		return M.save()
	end

	return true
end

return M
