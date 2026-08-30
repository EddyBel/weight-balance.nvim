local python = require("weight-balance.core.python-detector")
local node = require("weight-balance.core.node-detector")
local rust = require("weight-balance.core.rust-detector")
local lua = require("weight-balance.core.lua-detector")
local virtual_text = require("weight-balance.utils.virtual-text")

local M = {}

M.buffer_analize = 0

--- Ejecuta el análisis de dependencias según el tipo de archivo actual (Python o JavaScript/TypeScript)
--- y renderiza el texto virtual con los pesos y estilos configurados.
---
--- @param opts? table Tabla de opciones opcionales que se pasará a `render_dependencies_virt_text`
---                  (permite configurar `thresholds`, `icons` y `highlights`).
function M.detector_and_view_size(opts)
    local ft = vim.bo[M.buffer_analize].filetype

    if ft == "python" then
        python.check_python_dependencies(function(deps)
            if not deps then
                return
            end
            virtual_text.render_dependencies_virt_text(deps, M.buffer_analize, opts)
        end, M.buffer_analize)
    elseif ft == "javascript" or ft == "javascriptreact" or ft == "typescript" or ft == "typescriptreact" then
        node.check_node_dependencies(function(deps)
            if not deps then
                return
            end

            virtual_text.render_dependencies_virt_text(deps, M.buffer_analize, opts)
        end, M.buffer_analize)
    elseif ft == "rust" then
        rust.check_rust_dependencies(function(deps)
            if not deps then
                return
            end

            virtual_text.render_dependencies_virt_text(deps, M.buffer_analize, opts)
        end, M.buffer_analize)
    elseif ft == "lua" then
        lua.check_lua_dependencies(function(deps)
            if not deps then
                return
            end

            virtual_text.render_dependencies_virt_text(deps, M.buffer_analize, opts)
        end, M.buffer_analize)
    else
        -- vim.notify("El buffer actual no es un archivo compatible (Python o JS/TS).", vim.log.levels.WARN,
        -- { title = "WeightBalance" })
    end
end

return M
