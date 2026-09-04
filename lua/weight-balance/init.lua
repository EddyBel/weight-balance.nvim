local API = require("weight-balance.core.api")
local AUTOCMDS = require("weight-balance.core.autocmds")
local COMMANDS = require("weight-balance.core.commands")

local M = {}

local initialized = false

function M.setup(opts)
    if initialized then
        return
    end

    initialized = true

    opts = opts or {}

    local auto_check = opts.auto_check or true

    API.start(
        function(success, error)
            if not success then
                vim.notify(
                    "Weight Balance: " .. tostring(error),
                    vim.log.levels.ERROR
                )
                return
            end

            vim.notify(
                "Weight Balance server started",
                vim.log.levels.INFO
            )
        end,
        {
            server = opts.server,
            virtualtext = opts.virtualtext,
        }
    )

    vim.api.nvim_create_user_command(
        "CheckDeps",
        function()
            API.run_analysis()
        end,
        {
            desc = "Analyze current buffer dependencies",
        }
    )

    COMMANDS.create(API)

    if auto_check then
        AUTOCMDS.create(API)
    end
end

return M
