# 📦 databox.nvim

**databox.nvim** is a robust and secure Neovim plugin that provides encrypted storage for Lua tables (dictionaries), using [`age`](https://age-encryption.org) or compatible encryption tools for cryptographic safety. Data is stored deeply encrypted, meaning every string — including nested keys and values — is protected.

- 🔐 Built on [age](https://github.com/FiloSottile/age) (or compatible tools like [rage](https://github.com/str4d/rage))
- 🧐 Supports deeply nested data structures with preserved empty tables and nil values
- 📂 Automatically saves encrypted data to disk
- 🧰 Simple Lua API for manipulating entries
- 🛡️ Secure temporary file handling with cryptographically safe practices
- ✅ Comprehensive error handling and validation
- 🏷️ Full LSP support with Lua annotations
- ⚡ Efficient single-pass processing with per-string encryption security
- 🔧 Configurable encryption utilities (age, rage, or custom commands)

---

## ✨ Use Cases

- Save sensitive plugin state securely between Neovim sessions
- Store secrets, credentials, or tokens encrypted on disk
- Use as a secure encrypted scratchpad for plugin development
- Maintain encrypted configuration data that persists across sessions
- Store complex nested data structures with preserved empty elements

---

## 🔧 Requirements

- **Neovim 0.7+**
- **Encryption utility**: One of:
  - [`age`](https://github.com/FiloSottile/age) (default, Go implementation)
  - [`rage`](https://github.com/str4d/rage) (Rust implementation, often faster)
  - Any age-compatible encryption tool
- Public and private key(s) generated (see setup section)
- Unix-like environment (for `mktemp` command)

---

## 🚀 Installation

### With LazyVim (Recommended)

```lua
{
  "chrisgve/databox.nvim",
  config = function()
    local success, err = require("databox").setup({
      private_key = "~/.config/age/keys.txt",
      public_key = "age1example...", -- Your public key string
      -- Optional: Use rage for better performance
      -- encryption_cmd = "rage -e -r %s",
      -- decryption_cmd = "rage -d -i %s",
    })
    
    if not success then
      vim.notify("Databox setup failed: " .. err, vim.log.levels.ERROR)
    end
  end,
}
```

### Manual Installation (Non-LazyVim)

Using your preferred plugin manager, then configure in your `init.lua`:

```lua
-- Example with packer.nvim
use {
  'chrisgve/databox.nvim',
  config = function()
    local success, err = require("databox").setup({
      private_key = "~/.config/age/keys.txt",
      public_key = "age1example...",
    })
    
    if not success then
      print("Databox setup failed: " .. err)
    end
  end
}
```

---

## 🔑 Key Generation

Generate your age key pair:

```bash
# Create age directory
mkdir -p ~/.config/age

# Generate key pair (works with both age and rage)
age-keygen -o ~/.config/age/keys.txt

# Your public key will be displayed in the terminal
# Example: age1abc123def456ghi789jkl012mno345pqr678stu901vwx234yz567890ab
```

The public key (starting with `age1...`) is what you'll use in your configuration.

---

## ⚙️ Configuration

### Required Options

- `private_key` (string): Path to your private key file
- `public_key` (string): Your public key string or path to public key file

### Optional Options

- `store_path` (string): Custom storage path (defaults to XDG_DATA_HOME or ~/.local/share/nvim/databox.txt)
- `encryption_cmd` (string): Command template for encryption (default: `"age -e -r %s"`)
- `decryption_cmd` (string): Command template for decryption (default: `"age -d -i %s"`)

### Configuration Examples

#### Standard age setup:
```lua
require("databox").setup({
  private_key = "~/.config/age/keys.txt",
  public_key = "age1abc123def456ghi789jkl012mno345pqr678stu901vwx234yz567890ab",
})
```

#### Using rage for better performance:
```lua
require("databox").setup({
  private_key = "~/.config/age/keys.txt",
  public_key = "age1abc123def456ghi789jkl012mno345pqr678stu901vwx234yz567890ab",
  encryption_cmd = "rage -e -r %s",
  decryption_cmd = "rage -d -i %s",
})
```

#### Custom storage location:
```lua
require("databox").setup({
  private_key = "~/.config/age/keys.txt",
  public_key = "age1abc123def456ghi789jkl012mno345pqr678stu901vwx234yz567890ab",
  store_path = "~/my-project/.secrets.txt",
})
```

#### Advanced custom encryption tool:
```lua
require("databox").setup({
  private_key = "~/.config/mycrypt/key.pem",
  public_key = "~/.config/mycrypt/pub.pem",
  encryption_cmd = "mycrypt encrypt --key %s",
  decryption_cmd = "mycrypt decrypt --key %s",
})
```

---

## 🧪 API Reference

All functions return `(success: boolean, error?: string)` for operations that can fail.

### Core Operations

```lua
local db = require("databox")

-- Check if plugin is working
local success, err = db.setup({ ... })

-- Set a new key (fails if key exists)
local ok, err = db.set("project1", { 
  token = "secret123", 
  config = { lang = "lua", debug = true },
  empty_settings = {},  -- Empty tables are preserved
  disabled_feature = nil, -- nil values are preserved
})

-- Update existing key (fails if key doesn't exist)
local ok, err = db.update("project1", { token = "newsecret456" })

-- Get value (returns value, error)
local value, err = db.get("project1")

-- Check existence
local exists = db.exists("project1") -- true/false

-- Remove key
local ok, err = db.remove("project1")
```

### Batch Operations

```lua
-- Get all keys
local all_keys = db.keys() -- returns string[]

-- Clear all data
local ok, err = db.clear()

-- Manual save/load
local ok, err = db.save()
local ok, err = db.load()
```

### Save Control

Most operations auto-save by default. Use `save = false` to batch operations:

```lua
-- Batch operations without saving each time
db.set("key1", "value1", false)
db.set("key2", "value2", false)
db.set("key3", "value3", false)

-- Save all at once
local ok, err = db.save()
```

---

## 📁 File Location

Encrypted data is stored in:

```
$XDG_DATA_HOME/nvim/databox.txt
```

If `XDG_DATA_HOME` is not set, it defaults to:

```
$HOME/.local/share/nvim/databox.txt
```

---

## 🔐 Security Features

### Deep Encryption with Per-String Security
- **Individual encryption**: Each string is encrypted separately, preventing correlation attacks
- **Secure containers**: Dictionary keys, string values, and nested strings all get individual encryption
- **Data integrity**: Non-string types (numbers, booleans) are preserved as-is
- **Complete preservation**: Empty tables `{}` and `nil` values are maintained exactly

### Secure Temporary Files
- **Cryptographically secure**: Uses `mktemp` for unpredictable temporary file names
- **Automatic cleanup**: Guaranteed cleanup of temporary files, even on failure
- **No predictable paths**: Eliminates risk of temp file prediction attacks

### Input Validation & Error Handling
- **Shell injection prevention**: All arguments are properly escaped
- **Serialization validation**: Checks data types before attempting encryption  
- **Comprehensive errors**: Clear, actionable error messages for all failure modes
- **Graceful degradation**: Partial failures don't corrupt existing data

---

## ⚡ Performance & Efficiency

### Smart Processing Architecture
- **Single-pass encoding**: Special values (nil, empty tables) are encoded during encryption traversal
- **Eliminated redundancy**: No separate filtering passes - everything happens in one efficient traversal
- **Reliable I/O**: Better temporary file handling reduces I/O failure rates

### Security-Performance Balance
The plugin uses **per-string encryption** by design - this isn't inefficient, it's a security feature:
- **Prevents correlation attacks**: Attackers can't correlate similar encrypted values
- **Isolated failures**: Corruption in one value doesn't affect others
- **Individual integrity**: Each string has its own encryption envelope

### Encryption Tool Flexibility
- **age**: Standard Go implementation, widely compatible
- **rage**: Rust implementation, often 2-3x faster than age
- **Custom tools**: Support any age-compatible encryption utility

---

## 🚨 Error Handling

The plugin provides detailed error messages for common issues:

```lua
local ok, err = db.set("existing_key", "value")
if not ok then
  print("Error: " .. err) -- "Key already exists: existing_key"
end

local ok, err = db.update("nonexistent_key", "value")
if not ok then
  print("Error: " .. err) -- "Key does not exist: nonexistent_key"
end

local ok, err = db.set("test", function() end)
if not ok then
  print("Error: " .. err) -- "Cannot serialize function values"
end
```

---

## ⚠️ Limitations

- Only string keys are supported at the top level
- Non-serializable values (functions, userdata, threads) are rejected with clear errors
- Requires Unix-like environment with `mktemp` command
- Assumes chosen encryption utility (age/rage/custom) is available in PATH
- Command templates must use `%s` placeholder for key parameter

---

## 🐛 Troubleshooting

### Common Issues

**"Plugin not initialized"**
- Ensure `setup()` is called before using any other functions
- Check that both `private_key` and `public_key` are provided

**"Command failed" or encryption/decryption errors**
- Verify your encryption utility (age/rage) is installed and in your PATH
- Check that your key files exist and are readable
- Ensure your public key matches your private key
- Test your encryption utility manually: `echo "test" | age -e -r <your_public_key>`

**"Failed to create secure temporary file"**
- Verify `mktemp` command is available
- Check that `/tmp` directory is writable

**Performance issues**
- Consider switching from `age` to `rage` for 2-3x performance improvement
- Use `save = false` for batch operations to reduce I/O

### Debug Mode

Enable verbose error output:

```lua
-- Check setup status
local success, err = require("databox").setup({ ... })
if not success then
  vim.notify("Setup failed: " .. err, vim.log.levels.ERROR)
end

-- Check individual operations
local ok, err = db.set("test", "value")
if not ok then
  vim.notify("Set failed: " .. err, vim.log.levels.ERROR)
end
```

### Performance Testing

Test your encryption utility choice:

```bash
# Test age performance
time echo "test data" | age -e -r <your_public_key> | age -d -i <your_private_key>

# Test rage performance  
time echo "test data" | rage -e -r <your_public_key> | rage -d -i <your_private_key>
```

---

## 📚 Encryption Tool Comparison

| Tool | Language | Performance | Compatibility | Installation |
|------|----------|-------------|---------------|--------------|
| **age** | Go | Standard | Universal | `brew install age` / package managers |
| **rage** | Rust | 2-3x faster | age-compatible | `cargo install rage` / releases |
| **Custom** | Any | Varies | Must be age-compatible | Your choice |

### Recommendations:
- **For maximum compatibility**: Use `age` (default)
- **For best performance**: Use `rage` with custom commands
- **For specialized needs**: Implement age-compatible custom encryption

---

## 📝 License

MIT — © 2025 [@chrisgve](https://github.com/chrisgve)