local M = {}

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

    local ok, dep_detector = pcall(require, "weight-balance")
    if not ok then
        vim.notify("No se pudo cargar weight-balance", vim.log.levels.ERROR, { title = "WeightBalance" })
        return
    end

    -- Definir el comando de usuario para ejecutar el análisis manualmente
    vim.api.nvim_create_user_command("CheckDeps", function()
        local dependencis = dep_detector.detector_and_view_size(vt_opts)
        if dependencis then
            print(vim.inspect(dependencis))
        end
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
                        dep_detector.detector_and_view_size(vt_opts)
                        break
                    end
                end
            end,
        })
    end
end

return M
