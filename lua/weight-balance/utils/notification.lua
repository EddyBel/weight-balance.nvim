local M = {}

M.noti = function(message, level, title, opts)
    -- =========================================================================
    -- Normalize arguments
    -- =========================================================================

    message = tostring(message or "")
    level = level or "info"

    opts = vim.tbl_extend(
        "force",
        {
            title = title,
            max_width = 50,
            render = "wrapped-compact",
        },
        opts or {}
    )

    -- =========================================================================
    -- 1. Try nvim-notify
    -- =========================================================================

    local ok, notify = pcall(require, "notify")

    if ok and _G.type(notify) == "table" then
        local success, err = pcall(
            notify,
            message,
            level,
            opts
        )

        if success then
            return true
        end

        vim.notify(
            "[Notifications] nvim-notify error: " .. tostring(err),
            vim.log.levels.DEBUG
        )
    end

    -- =========================================================================
    -- 2. Fallback to vim.notify
    -- =========================================================================

    if _G.type(vim.notify) == "function" then
        local vim_level =
            vim.log.levels[level:upper()]
            or vim.log.levels.INFO

        local success = pcall(
            vim.notify,
            message,
            vim_level,
            opts
        )

        if success then
            return true
        end
    end

    -- =========================================================================
    -- 3. Last resort: print
    -- =========================================================================

    return pcall(print, message)
end


return M
