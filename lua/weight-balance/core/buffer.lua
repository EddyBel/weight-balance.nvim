local Buffer = {}

-- ============================================================================
-- Configuration
-- ============================================================================

local DEFAULT_LANGUAGES = {
    python = {
        parser = "python",

        imports = {
            "import%s+",
            "from%s+",
        },
    },

    javascript = {
        parser = "node",

        imports = {
            "import%s+",
            "require%s*%(",
            "from%s+",
        },
    },

    typescript = {
        parser = "node",

        imports = {
            "import%s+",
            "require%s*%(",
            "from%s+",
        },
    },

    javascriptreact = {
        parser = "node",

        imports = {
            "import%s+",
            "require%s*%(",
            "from%s+",
        },
    },

    typescriptreact = {
        parser = "node",

        imports = {
            "import%s+",
            "require%s*%(",
            "from%s+",
        },
    },

    jsx = {
        parser = "node",

        imports = {
            "import%s+",
            "require%s*%(",
            "from%s+",
        },
    },

    tsx = {
        parser = "node",

        imports = {
            "import%s+",
            "require%s*%(",
            "from%s+",
        },
    },

    rust = {
        parser = "rust",

        imports = {
            "use%s+",
            "extern%s+crate%s+",
        },
    },

    lua = {
        parser = "lua",

        imports = {
            "require%s*%(",
        },
    },
}

local languages = vim.deepcopy(DEFAULT_LANGUAGES)

-- Cache indexed by buffer number.
local cache = {}

-- ============================================================================
-- Configuration
-- ============================================================================

--- Configure buffer language definitions.
---
--- @param opts table|nil
--- @return nil
function Buffer.configure(opts)
    opts = opts or {}

    if opts.languages then
        languages = vim.tbl_deep_extend(
            "force",
            languages,
            opts.languages
        )
    end
end

--- Retrieve the current language configuration.
---
--- @return table
function Buffer.get_languages()
    return vim.deepcopy(languages)
end

-- ============================================================================
-- Language
-- ============================================================================

--- Get the language configuration associated with a buffer.
---
--- @param bufnr number|nil
--- @return table|nil
function Buffer.get_language_config(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    local filetype = vim.bo[bufnr].filetype

    return languages[filetype]
end

--- Get the backend parser associated with a buffer.
---
--- @param bufnr number|nil
--- @return string|nil
function Buffer.get_language(bufnr)
    local language = Buffer.get_language_config(bufnr)

    if not language then
        return nil
    end

    return language.parser
end

--- Check whether the buffer filetype is supported.
---
--- @param bufnr number|nil
--- @return boolean
function Buffer.is_supported(bufnr)
    return Buffer.get_language_config(bufnr) ~= nil
end

-- ============================================================================
-- Buffer content
-- ============================================================================

--- Get the complete content of a buffer.
---
--- @param bufnr number|nil
--- @return string
function Buffer.get_content(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    local lines = vim.api.nvim_buf_get_lines(
        bufnr,
        0,
        -1,
        false
    )

    return table.concat(lines, "\n")
end

--- Get all lines from a buffer.
---
--- @param bufnr number
--- @return table
local function get_lines(bufnr)
    return vim.api.nvim_buf_get_lines(
        bufnr,
        0,
        -1,
        false
    )
end

-- ============================================================================
-- Imports
-- ============================================================================

--- Get the import map from a buffer.
---
--- @param bufnr number
--- @param language table Language configuration.
--- @return table
local function get_imports(bufnr, language)
    local patterns = language.imports

    if not patterns then
        return {}
    end

    local imports = {}
    local lines = get_lines(bufnr)

    for line_number, line in ipairs(lines) do
        for _, pattern in ipairs(patterns) do
            if line:match(pattern) then
                imports[tostring(line_number)] = line
                break
            end
        end
    end

    return imports
end

-- ============================================================================
-- Cache
-- ============================================================================

--- Compare two import maps.
---
--- @param previous table|nil
--- @param current table
--- @return boolean
local function imports_changed(previous, current)
    if not previous then
        return true
    end

    local previous_count = 0
    local current_count = 0

    for _ in pairs(previous) do
        previous_count = previous_count + 1
    end

    for _ in pairs(current) do
        current_count = current_count + 1
    end

    if previous_count ~= current_count then
        return true
    end

    for line, content in pairs(current) do
        if previous[line] ~= content then
            return true
        end
    end

    return false
end

-- ============================================================================
-- Analysis
-- ============================================================================

--- Analyze the buffer and update its import cache.
---
--- @param bufnr number|nil
--- @param on_changed function|nil
--- @param on_unchanged function|nil
--- @return nil
function Buffer.check(bufnr, on_changed, on_unchanged)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    local language = Buffer.get_language_config(bufnr)

    -- Unsupported buffers are ignored completely.
    if not language then
        return
    end

    local current_imports = get_imports(
        bufnr,
        language
    )

    local previous_imports = cache[bufnr]

    local changed = imports_changed(
        previous_imports,
        current_imports
    )

    cache[bufnr] = current_imports

    if changed then
        if on_changed then
            on_changed(current_imports)
        end
    else
        if on_unchanged then
            on_unchanged(current_imports)
        end
    end
end

-- ============================================================================
-- Cache API
-- ============================================================================

--- Retrieve the current cache of a buffer.
---
--- @param bufnr number|nil
--- @return table|nil
function Buffer.get_cache(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    return cache[bufnr]
end

--- Clear the cache of a buffer.
---
--- @param bufnr number|nil
--- @return nil
function Buffer.clear(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    cache[bufnr] = nil
end

--- Clear the entire buffer cache.
---
--- @return nil
function Buffer.clear_all()
    cache = {}
end

return Buffer
