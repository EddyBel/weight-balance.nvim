local python = require("weight-balance.core.python-detector")
local node = require("weight-balance.core.node-detector")
local rust = require("weight-balance.core.rust-detector")
local lua = require("weight-balance.core.lua-detector")
local virtual_text = require("weight-balance.utils.virtual-text")

local M = {}

M.buffer_analize = 0

local M = {}

-- Guarda una referencia global de la configuración para usarla en los detectores
M.config = {}

local default_typefiles = {
    "python",
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact",
    "rust",
    "lua"
}

function M.setup(opts)
    opts = opts or {}

    -- Fusionar opciones principales con valores por defecto
    M.config.auto_check = opts.auto_check ~= nil and opts.auto_check or true
    M.config.enabled_typefiles = opts.enabled_typefiles or default_typefiles

    -- Fusionar sub-tabla virtualtext de forma segura
    local user_vt = opts.virtualtext or {}
    local default_vt = {
        normalized = false,
        thresholds = {
            warning = 100 * 1024,
            danger = 1 * 1024 * 1024,
        },
        icons = {
            low = " ",
            warning = " ",
            danger = "󰸕 ",
            not_found = "󰒲 ",
        },
        highlights = {
            low = "DiagnosticOk",
            warning = "DiagnosticWarn",
            danger = "DiagnosticError",
            not_found = "Comment",
        },
    }

    M.config.virtualtext = {
        normalized = user_vt.normalized ~= nil and user_vt.normalized or default_vt.normalized,
        thresholds = vim.tbl_deep_extend("force", default_vt.thresholds, user_vt.thresholds or {}),
        icons = vim.tbl_deep_extend("force", default_vt.icons, user_vt.icons or {}),
        highlights = vim.tbl_deep_extend("force", default_vt.highlights, user_vt.highlights or {}),
    }

    -- Definir el comando de usuario pasándole la configuración procesada
    vim.api.nvim_create_user_command("CheckDeps", function()
        M.detector_and_view_size(M.config.virtualtext)
    end, { desc = "Analizar y ver el tamaño de las dependencias del buffer actual" })

    -- Registrar autocomandos usando M.config.auto_check y M.config.enabled_typefiles
    if M.config.auto_check then
        local augroup = vim.api.nvim_create_augroup("WeightBalanceAuto", { clear = true })

        vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI" }, {
            group = augroup,
            callback = function()
                local ft = vim.bo.filetype
                for _, supported_ft in ipairs(M.config.enabled_typefiles) do
                    if ft == supported_ft then
                        M.detector_and_view_size(M.config.virtualtext)
                        break
                    end
                end
            end,
        })
    end
end

function M.detector_and_view_size(opts)
    local ft = vim.bo[M.buffer_analize].filetype

    if ft == "python" then
        python.check_python_dependencies(function(deps)
            if not deps then return end
            virtual_text.render_dependencies_virt_text(deps, M.buffer_analize, opts)
        end, M.buffer_analize)
    elseif ft == "javascript" or ft == "javascriptreact" or ft == "typescript" or ft == "typescriptreact" then
        node.check_node_dependencies(function(deps)
            if not deps then return end
            virtual_text.render_dependencies_virt_text(deps, M.buffer_analize, opts)
        end, M.buffer_analize)
    elseif ft == "rust" then
        rust.check_rust_dependencies(function(deps)
            if not deps then return end
            virtual_text.render_dependencies_virt_text(deps, M.buffer_analize, opts)
        end, M.buffer_analize)
    elseif ft == "lua" then
        lua.check_lua_dependencies(function(deps)
            if not deps then return end
            virtual_text.render_dependencies_virt_text(deps, M.buffer_analize, opts)
        end, M.buffer_analize)
    end
end

return M
