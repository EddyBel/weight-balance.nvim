local python = require("weight-balance.core.python-detector")
local node = require("weight-balance.core.node-detector")
local rust = require("weight-balance.core.rust-detector")
local lua = require("weight-balance.core.lua-detector")
local virtual_text = require("weight-balance.utils.virtual-text")

local M = {}

M.buffer_analize = 0

local default_typefiles = {
    "python",
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact",
    "rust",
    "lua"
}

--- Configura el plugin, define el comando de usuario y registra los autocomandos
--- para actualizar el análisis y renderizado de dependencias automáticamente según las opciones.
---
--- @param opts? table Tabla de opciones de configuración (auto_check, enabled_typefiles, virtualtext).
function M.setup(opts)
    opts = opts or {}
    local auto_check = opts.auto_check ~= nil and opts.auto_check or true
    local enabled_typefiles = opts.enabled_typefiles or default_typefiles
    local vt_opts = opts.virtualtext or {}

    -- Definir el comando de usuario para ejecutar el análisis manualmente
    vim.api.nvim_create_user_command("CheckDeps", function()
        M.detector_and_view_size(vt_opts)
    end, { desc = "Analizar y ver el tamaño de las dependencias del buffer actual" })

    -- Registrar autocomandos solo si auto_check está habilitado
    if auto_check then
        local augroup = vim.api.nvim_create_augroup("WeightBalanceAuto", { clear = true })

        vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI" }, {
            group = augroup,
            callback = function()
                local ft = vim.bo.filetype
                for _, supported_ft in ipairs(enabled_typefiles) do
                    if ft == supported_ft then
                        M.detector_and_view_size(vt_opts)
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
