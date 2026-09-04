local BUFFER = require("weight-balance.core.buffer")
local SERVER = require("weight-balance.core.server")
local RENDER = require("weight-balance.core.render")
local FORMAT = require("weight-balance.utils.format")
local NOTIFICATION = require("weight-balance.utils.notification")
local AUTOCMDS = require("weight-balance.core.autocmds")

local API = {}

-- ============================================================================
-- State
-- ============================================================================

local state = {
    enabled = false,
}

-- ============================================================================
-- Configuration
-- ============================================================================

-- Default configuration for the API.
--
-- Module-specific configuration is grouped by responsibility:
--
--   buffer      -> supported filetypes and buffer parsing rules
--   server      -> Python backend configuration
--   virtualtext -> renderer configuration
--
-- Global options remain directly inside this table.
local config = {
    buffer = {},
    server = {},
    virtualtext = {},

    notification = false,

    -- Time in milliseconds to wait after the last change
    -- before sending a request to the backend.
    debounce = 200,
}

-- Cache for results fetched from the backend.
--
-- The key is the buffer number (integer).
local results_cache = {}

-- Stores the current request token for each buffer.
--
-- Each request receives a unique table as its token.
-- This prevents an old asynchronous response from modifying
-- the buffer after a newer request has already been created.
local request_tokens = {}

-- Stores the debounce timer for each buffer.
--
-- The key is the buffer number.
local debounce_timers = {}

-- ============================================================================
-- Notification
-- ============================================================================

--- Send a plugin notification if notifications are enabled.
---
--- All Weight Balance notifications pass through this helper.
--- The notification utility handles nvim-notify, vim.notify,
--- and print as fallback.
---
--- @param message string Notification message.
--- @param level string Notification level.
--- @param title string|nil Optional notification title.
--- @param opts table|nil Optional notification options.
--- @return boolean|nil
local function notify(message, level, title, opts)
    if not config.notification then
        return
    end

    return NOTIFICATION.noti(
        "Weight Balance: " .. tostring(message),
        level,
        title,
        opts
    )
end

--------------------------------------------------
-- Request synchronization
--------------------------------------------------

local function create_request_token(bufnr)
    local token = {}

    request_tokens[bufnr] = token

    return token
end

local function is_current_request(bufnr, token)
    return request_tokens[bufnr] == token
end

local function invalidate_request(bufnr)
    request_tokens[bufnr] = nil
end

local function invalidate_all_requests()
    request_tokens = {}
end

-- ============================================================================
-- Debounce
-- ============================================================================

--- Cancel a pending debounce timer for a buffer.
---
--- @param bufnr number Buffer handle number.
--- @return nil
local function cancel_debounce(bufnr)
    local timer = debounce_timers[bufnr]

    if not timer then
        return
    end

    debounce_timers[bufnr] = nil

    timer:stop()
    timer:close()
end

--- Cancel every pending debounce timer.
---
--- @return nil
local function cancel_all_debounce()
    for bufnr in pairs(debounce_timers) do
        cancel_debounce(bufnr)
    end

    debounce_timers = {}
end

--- Execute a callback after the configured debounce delay.
---
--- If the same buffer changes again before the delay expires,
--- the previous timer is cancelled and a new one is created.
---
--- @param bufnr number Buffer handle number.
--- @param callback function Function to execute after the delay.
--- @return nil
local function debounce(bufnr, callback)
    -- Cancel the previous timer for this buffer.
    cancel_debounce(bufnr)

    -- Debounce disabled.
    if config.debounce <= 0 then
        callback()
        return
    end

    local timer = vim.uv.new_timer()

    debounce_timers[bufnr] = timer

    timer:start(
        config.debounce,
        0,

        vim.schedule_wrap(function()
            -- Only remove this timer if it is still the
            -- current timer for this buffer.
            if debounce_timers[bufnr] == timer then
                debounce_timers[bufnr] = nil
            end

            timer:stop()
            timer:close()

            callback()
        end)
    )
end


-- ============================================================================
-- Configuration
-- ============================================================================

--- Configure the API and its dependent modules.
---
--- Module-specific options are forwarded to the corresponding module.
---
--- @param opts table|nil Configuration options.
---   - buffer: table Buffer configuration.
---   - server: table Backend server configuration.
---   - virtualtext: table Renderer configuration.
---   - notification: boolean Enable or disable notifications.
--- @return nil
--- @usage
---   require("weight-balance").configure({
---       notification = false,
---
---       buffer = {
---           languages = {
---               python = {
---                   parser = "python",
---                   imports = {
---                       "import%s+",
---                       "from%s+",
---                   },
---               },
---           },
---       },
---
---       virtualtext = {
---           normalized = true,
---       },
---   })
function API.configure(opts)
    opts = opts or {}

    config = vim.tbl_deep_extend(
        "force",
        config,
        opts
    )

    -- Forward buffer-specific configuration.
    if opts.buffer then
        BUFFER.configure(
            config.buffer
        )
    end
end

-- ============================================================================
-- Result preparation
-- ============================================================================

--- Prepare and format backend data for the renderer.
---
--- It does not modify original size/root_size values.
--- It only injects display properties for UI presentation.
---
--- @param result table The raw result object returned from the server.
--- @param source string Origin identifier ("server" or "cache").
--- @return table|nil Modified result table containing formatted display sizes.
local function prepare_result(result, source)
    if not result or not result.data then
        return result
    end

    for _, dep in ipairs(result.data) do
        -- Format main dependency size.
        if type(dep.size) == "number" then
            dep.display_size = FORMAT.format_size(
                dep.size
            )
        else
            dep.display_size = tostring(
                dep.size or "not found"
            )
        end

        -- Format total dependency root size.
        if type(dep.root_size) == "number" then
            dep.display_root_size = FORMAT.format_size(
                dep.root_size
            )
        else
            dep.display_root_size = tostring(
                dep.root_size or "not found"
            )
        end
    end

    -- Metadata tag useful for debugging and internal flows.
    result.source = source

    return result
end

-- ============================================================================
-- Rendering
-- ============================================================================

--- Render dependency data inside a specified buffer.
---
--- @param result table The formatted analysis result object.
--- @param bufnr number Target buffer handle number.
--- @return nil
local function render(result, bufnr)
    RENDER.render_dependencies_virt_text(
        result.data or {},
        bufnr,
        config.virtualtext
    )
end

--- Clear virtual text decorations from a specific buffer.
---
--- @param bufnr number Target buffer handle number.
--- @return nil
local function clear_render(bufnr)
    RENDER.render_dependencies_virt_text(
        {},
        bufnr,
        config.virtualtext
    )
end

-- ============================================================================
-- Analysis cleanup
-- ============================================================================

--- Clear analysis data, cache, and UI decorations for a specific buffer.
---
--- @param bufnr number Target buffer handle number.
--- @return nil
local function clear_analysis(bufnr)
    BUFFER.clear(bufnr)

    results_cache[bufnr] = nil

    clear_render(bufnr)
end

-- ============================================================================
-- Analysis
-- ============================================================================

--- Execute dependency analysis for the current buffer.
---
--- Unsupported buffers are ignored before attempting to contact the backend.
---
--- If imports changed, a new backend request is performed.
--- If imports remain unchanged, the cached response is reused.
---
--- @param callback function|nil Optional completion handler.
--- @return nil
function API.run_analysis(callback)
    local bufnr =
        vim.api.nvim_get_current_buf()

    --------------------------------------------------
    -- Buffer validation
    --------------------------------------------------

    if not BUFFER.is_supported(bufnr) then
        cancel_debounce(bufnr)
        invalidate_request(bufnr)
        clear_render(bufnr)

        notify(
            "Filetype not supported",
            "warn"
        )

        if callback then
            callback(
                nil,
                "Filetype not supported"
            )
        end

        return
    end

    local language =
        BUFFER.get_language(bufnr)

    if not language then
        cancel_debounce(bufnr)
        invalidate_request(bufnr)
        clear_render(bufnr)

        notify(
            "Unable to determine language",
            "warn"
        )

        if callback then
            callback(
                nil,
                "Unable to determine language"
            )
        end

        return
    end

    --------------------------------------------------
    -- Check imports
    --------------------------------------------------

    BUFFER.check(
        bufnr,

        --------------------------------------------------
        -- Imports changed
        --------------------------------------------------

        function()
            --------------------------------------------------
            -- Debounce analysis.
            --
            -- If TextChanged fires repeatedly, this callback
            -- will only execute after the user stops changing
            -- the buffer for config.debounce milliseconds.
            --------------------------------------------------

            debounce(bufnr, function()
                --------------------------------------------------
                -- Make sure the buffer still exists.
                --------------------------------------------------

                if not vim.api.nvim_buf_is_valid(bufnr) then
                    return
                end

                --------------------------------------------------
                -- Capture the latest buffer contents.
                --
                -- This is intentionally done AFTER the debounce.
                -- Therefore we analyze the latest version of
                -- the buffer rather than the version that caused
                -- the first TextChanged event.
                --------------------------------------------------

                local code =
                    BUFFER.get_content(bufnr)

                --------------------------------------------------
                -- Create a new request token.
                --
                -- This invalidates every previous request for
                -- this buffer.
                --------------------------------------------------

                local token =
                    create_request_token(bufnr)

                --------------------------------------------------
                -- Send asynchronous request.
                --------------------------------------------------

                SERVER.request(
                    code,
                    language,

                    --------------------------------------------------
                    -- Async response
                    --------------------------------------------------

                    function(result, error)
                        --------------------------------------------------
                        -- Ignore stale responses.
                        --
                        -- This MUST happen before modifying:
                        -- cache
                        -- rendering
                        -- notifications
                        -- callbacks
                        --------------------------------------------------

                        if not is_current_request(
                                bufnr,
                                token
                            ) then
                            return
                        end

                        --------------------------------------------------
                        -- Server error
                        --------------------------------------------------

                        if error then
                            invalidate_request(bufnr)

                            API.clear(
                                bufnr
                            )

                            local message

                            if type(error) == "table" then
                                message =
                                    error.error
                                    or error.exception
                                    or error.details
                                    or "Unknown server error"
                            else
                                message =
                                    tostring(error)
                            end

                            notify(
                                message,
                                "error"
                            )

                            if callback then
                                callback(
                                    nil,
                                    error
                                )
                            end

                            return
                        end

                        --------------------------------------------------
                        -- Empty result
                        --------------------------------------------------

                        if not result then
                            invalidate_request(bufnr)

                            API.clear(
                                bufnr
                            )

                            notify(
                                "Server returned an empty result",
                                "error"
                            )

                            if callback then
                                callback(
                                    nil,
                                    "Empty server result"
                                )
                            end

                            return
                        end

                        --------------------------------------------------
                        -- Prepare result
                        --------------------------------------------------

                        result =
                            prepare_result(
                                result,
                                "server"
                            )

                        --------------------------------------------------
                        -- Cache result
                        --------------------------------------------------

                        results_cache[bufnr] =
                            result

                        --------------------------------------------------
                        -- Render result
                        --------------------------------------------------

                        render(
                            result,
                            bufnr
                        )

                        --------------------------------------------------
                        -- Callback
                        --------------------------------------------------

                        if callback then
                            callback(
                                result
                            )
                        end
                    end
                )
            end)
        end,

        --------------------------------------------------
        -- Imports unchanged
        --------------------------------------------------

        function()
            local result =
                results_cache[bufnr]

            --------------------------------------------------
            -- No cached result
            --------------------------------------------------

            if not result then
                notify(
                    "No cached analysis available",
                    "warn"
                )

                if callback then
                    callback(
                        nil,
                        "No cached analysis available"
                    )
                end

                return
            end

            --------------------------------------------------
            -- Use cached result
            --------------------------------------------------

            result.source = "cache"

            render(
                result,
                bufnr
            )

            if callback then
                callback(
                    result
                )
            end
        end
    )
end

-- ============================================================================
-- Server lifecycle
-- ============================================================================

--- Start the backend server process.
---
--- @param callback function|nil Optional initialization callback.
--- @param opts table|nil Server configuration overrides.
--- @return nil
function API.start(callback, opts)
    API.configure(opts)

    SERVER.start(
        callback,
        config.server
    )
end

--- Stop the backend server process.
---
--- @return nil
function API.stop()
    SERVER.stop()
end

-- ============================================================================
-- Results
-- ============================================================================

--- Retrieve the latest analysis result cached for a buffer.
---
--- @param bufnr number|nil Buffer handle number.
--- @return table|nil
function API.get_result(bufnr)
    bufnr = bufnr
        or vim.api.nvim_get_current_buf()

    return results_cache[bufnr]
end

--- Retrieve a deep copy of the current global configuration.
---
--- @return table
function API.get_config()
    return vim.deepcopy(config)
end

-- ============================================================================
-- Clear
-- ============================================================================

--- Clear stored analysis results and UI state for a specific buffer.
---
--- @param bufnr number|nil Buffer handle number.
--- @return nil
function API.clear(bufnr)
    bufnr = bufnr
        or vim.api.nvim_get_current_buf()

    results_cache[bufnr] = nil

    BUFFER.clear(bufnr)

    clear_render(bufnr)
end

--- Clear all cached results and buffer states globally.
---
--- @return nil
function API.clear_all()
    cancel_all_debounce()
    invalidate_all_requests()

    results_cache = {}


    BUFFER.clear_all()

    RENDER.clear_all()
end

-- ============================================================================
-- Plugin lifecycle
-- ============================================================================

--- Enable the plugin features and activate the backend.
---
--- If the plugin is already enabled, this function does nothing.
---
--- @return nil
function API.enable()
    if state.enabled then
        return
    end

    state.enabled = true

    SERVER.start(
        nil,
        config.server
    )

    AUTOCMDS.enable(API)

    API.run_analysis()

    notify(
        "Enabled",
        "info"
    )
end

--- Disable the plugin, backend, autocmds, cache,
--- and virtual text decorations.
---
--- If the plugin is already disabled, this function does nothing.
---
--- @return nil
function API.disable()
    if not state.enabled then
        return
    end

    state.enabled = false

    cancel_all_debounce()

    invalidate_all_requests()

    AUTOCMDS.disable()

    SERVER.stop()

    BUFFER.clear_all()

    results_cache = {}

    RENDER.clear_all()

    notify(
        "Disabled",
        "info"
    )
end

--- Toggle the plugin between enabled and disabled states.
---
--- @return nil
function API.toggle()
    if state.enabled then
        API.disable()
    else
        API.enable()
    end
end

-- ============================================================================
-- Virtual text configuration
-- ============================================================================

--- Toggle or set aligned size display.
---
--- The cached analysis is reused, so changing this option does not
--- trigger a new backend request.
---
--- @param value boolean
--- @return nil
function API.set_aligned(value)
    if config.virtualtext.aligned == value then
        return
    end

    config.virtualtext.aligned = value

    local bufnr = vim.api.nvim_get_current_buf()
    local result = results_cache[bufnr]

    if not result then
        return
    end

    clear_render(bufnr)

    render(
        result,
        bufnr
    )
end

return API

--
-- TextChanged
--      │
--      ▼
-- BUFFER.check()
--      │
--      ├── imports iguales ─────────► CACHE
--      │
--      └── imports cambiaron
--               │
--               ▼
--         debounce 200 ms
--               │
--        ┌──────┴──────┐
--        │             │
--     escribe       deja de
--     otra vez       escribir
--        │             │
--        └── reinicia ─┘
--                      │
--                      ▼
--               get_content()
--                      │
--                      ▼
--              nuevo request token
--                      │
--                      ▼
--               SERVER.request()
--                      │
--                      ▼
--                respuesta
--                      │
--               ¿token actual?
--                 /       \
--               NO         SÍ
--               │           │
--            descartar      ▼
--                        cache
--                          │
--                          ▼
--                        render
