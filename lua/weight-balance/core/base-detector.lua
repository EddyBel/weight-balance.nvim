--- BaseDetector Module: Provides an object-oriented class to manage
--- asynchronous dependency analysis, per-buffer caching, and data transformation
--- for various programming languages in Neovim.

local format_size = require("weight-balance.utils.format").format_size
local search_parser = require("weight-balance.utils.search_parsers").get_parser_path

--- Class definition for BaseDetector
local BaseDetector = {}
BaseDetector.__index = BaseDetector

--- Constructor for the BaseDetector class.
--- @param opts table Configuration options (language: string, match_fn: function)
--- @return table Configured instance of BaseDetector
function BaseDetector.new(opts)
    local self = setmetatable({}, BaseDetector)
    self.language = opts.language --- Language identifier (e.g., "python", "node")
    self.match_fn = opts.match_fn --- Matching function (regex/pattern) to filter imports
    self.buffer_cache = {}        --- Buffer-level cache storage indexed by buffer number (`bufnr`)
    return self
end

--- Retrieves all text lines from the specified buffer.
--- @param bufnr number Buffer number (0 represents the currently active buffer)
--- @return table Array of strings containing the text for each line of the buffer
function BaseDetector:get_buffer_lines(bufnr)
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

--- Filters buffer lines using the language-specific syntactic rule.
--- @param lines table Array of text lines retrieved from the buffer
--- @return string A concatenated string of matching imports representing the buffer signature
function BaseDetector:extract_imports(lines)
    local current_imports = {}
    for _, line in ipairs(lines) do
        -- Evaluates each line against the language-specific matching function
        if self.match_fn(line) then
            table.insert(current_imports, line)
        end
    end
    return table.concat(current_imports, "\n")
end

--- Transforms and formats raw data returned by the external parser script.
--- @param parsed table Array of decoded JSON objects containing dependency details
--- @return table Structured array with formatted sizes ready for the UI layer
function BaseDetector:format_dependencies(parsed)
    local dependencies_info = {}
    for _, item in ipairs(parsed) do
        -- Format individual size if it's a valid numeric value
        local formatted_tamano = "not found"
        if type(item.size) == "number" then
            formatted_tamano = format_size(item.size)
        end

        -- Format root size if it's a valid numeric value
        local formatted_root_tamano = "not found"
        if type(item.root_size) == "number" then
            formatted_root_tamano = format_size(item.root_size)
        end

        -- Insert the processed and enriched data structure
        table.insert(dependencies_info, {
            name = item.name,
            raw = item.raw,
            size = item.size,
            tamano = formatted_tamano,
            root_size = item.root_size,
            root_tamano = formatted_root_tamano,
            type = item.type,
        })
    end
    return dependencies_info
end

--- Asynchronously executes the external parser script using `vim.system`.
--- @param script_path string Absolute path to the language analyzer script
--- @param buffer_content string Full content of the buffer passed via standard input (stdin)
--- @param callback function Function to invoke upon process completion with the processed dependencies
function BaseDetector:run_parser(script_path, buffer_content, callback)
    vim.system(
        { "python3", script_path },
        { text = true, stdin = buffer_content },
        function(result)
            -- Return to Neovim's main event loop thread to safely interact with APIs
            vim.schedule(function()
                -- Check if the external process terminated with an error code
                if result.code ~= 0 then
                    vim.notify("Error executing " .. self.language .. " analyzer: " .. (result.stderr or ""),
                        vim.log.levels.ERROR, { title = "WeightBalance" })
                    if callback then callback(nil) end
                    return
                end

                -- Safely decode the JSON standard output from the parser
                local ok, parsed = pcall(vim.fn.json_decode, result.stdout)
                if not ok or not parsed then
                    vim.notify("Failed to parse results from the " .. self.language .. " analyzer.",
                        vim.log.levels.ERROR, { title = "WeightBalance" })
                    if callback then callback(nil) end
                    return
                end

                -- Transform the retrieved data structure
                local dependencies_info = self:format_dependencies(parsed)
                if callback then callback(dependencies_info) end
            end)
        end
    )
end

--- Main workflow method coordinating reading, cache verification, and execution.
--- @param callback function Callback function receiving the processed dependencies
--- @param bufnr? number Optional buffer number (defaults to 0 for the current buffer)
function BaseDetector:check(callback, bufnr)
    bufnr = bufnr or 0

    -- Look up the analyzer script path corresponding to the configured language
    local script_path = search_parser(self.language)
    if not script_path then
        vim.notify("Parser script for " .. self.language .. " not found in the scripts directory.",
            vim.log.levels.ERROR, { title = "WeightBalance" })
        if callback then callback(nil) end
        return
    end

    -- Get buffer content and generate a signature strictly based on its imports
    local lines = self:get_buffer_lines(bufnr)
    local imports_signature = self:extract_imports(lines)

    -- Initialize the cache entry for the buffer if it does not yet exist
    self.buffer_cache[bufnr] = self.buffer_cache[bufnr] or { signature = nil, deps = nil }

    -- If the import signature hasn't changed, return cached dependencies (optimization)
    if self.buffer_cache[bufnr].signature == imports_signature and self.buffer_cache[bufnr].deps then
        if callback then callback(self.buffer_cache[bufnr].deps) end
        return
    end

    -- Prepare the total buffer content to send to the parser
    local buffer_content = table.concat(lines, "\n")

    -- Execute external analysis and update cache with newly acquired results
    self:run_parser(script_path, buffer_content, function(deps)
        if deps then
            self.buffer_cache[bufnr].signature = imports_signature
            self.buffer_cache[bufnr].deps = deps
        end
        if callback then callback(deps) end
    end)
end

return BaseDetector
