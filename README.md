# 📦 databox.nvim

**databox.nvim** is a lightweight and secure Neovim plugin that provides encrypted storage for Lua tables (dictionaries), using [`age`](https://age-encryption.org) for cryptographic safety. Data is stored deeply encrypted, meaning every string — including nested keys and values — is protected.

- 🔐 Built on [age](https://github.com/FiloSottile/age) for strong encryption
- 🧐 Supports deeply nested data structures
- 📂 Automatically saves encrypted data to disk
- 🧰 Simple Lua API for manipulating entries

---

## ✨ Use Cases

- Save sensitive plugin state securely between Neovim sessions
- Store secrets, credentials, or tokens encrypted on disk
- Use as a secure encrypted scratchpad for plugin development

---

## 🔧 Requirements

- **Neovim 0.7+**
- [`age`](https://github.com/FiloSottile/age) CLI installed and available in your `PATH`
- Public and private key(s) generated (see below)

---

## 🧑‍🏫 Setup

### 1. Install via LazyVim or `lazy.nvim`

```lua
{
  "chrisgve/databox.nvim",
  config = function()
    require("databox").setup {
      private_key = "~/.config/age/keys.txt",
      public_key = "age1example...", -- or path to a public key file
    }
  end,
}
```

> 🔐 You can generate a key pair with:
>
> ```bash
> age-keygen -o ~/.config/age/keys.txt > ~/.config/age/key.txt
> ```

---

## 🧪 API

```lua
local db = require("databox")

db.set("project1", { token = "1234", config = { lang = "lua" } })
db.update("project1", { token = "5678" })   -- Overwrites value
local exists = db.exists("project1")       -- true
local val = db.get("project1")             -- decrypted table
db.save()                                  -- Manually save to disk
```

All `set()` and `update()` operations save automatically unless `save = false` is passed.

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

## 🔐 Deep Encryption

`databox.nvim` encrypts all strings — including dictionary keys, values, and list elements — recursively using `age`.
Non-string data types (numbers, booleans, etc.) are stored as-is and not encrypted.

---

## ⚠️ Limitations

- Only string keys are supported at the top level.
- Non-serializable values (e.g., functions, userdata) are not supported.
- Assumes a UNIX-like shell environment with access to `age`, `cat`, and `echo`.

---

## 📝 License

MIT — © 2025 [@chrisgve](https://github.com/chrisgve)
