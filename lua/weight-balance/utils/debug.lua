local M = {}

--- Imprime de forma legible una tabla de dependencias en una ventana flotante o mediante vim.notify
--- @param deps table Arreglo de dependencias devuelto por los analizadores
function M.print_dependencies(deps)
    if not deps or type(deps) ~= "table" or #deps == 0 then
        vim.notify("No hay dependencias para mostrar.", vim.log.levels.WARN, { title = "WeightBalance" })
        return
    end

    local lines = { "=== REPORTE DE DEPENDENCIAS ===" }
    for _, dep in ipairs(deps) do
        local line = string.format(
            "• [%s] %s -> Tamaño: %s (Raíz: %s) | Línea: %s",
            dep.type or "package",
            dep.name,
            dep.tamano or "not found",
            dep.root_tamano or "not found",
            dep.raw
        )
        table.insert(lines, line)
    end

    -- Crear un búfer flotante para mostrar el reporte ordenadamente
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    local width = 80
    local height = math.min(#lines + 2, 20)
    local opts = {
        style = "minimal",
        relative = "editor",
        width = width,
        height = height,
        row = math.floor((vim.o.lines - height) / 2),
        col = math.floor((vim.o.columns - width) / 2),
        border = "rounded",
    }

    vim.api.nvim_open_win(buf, true, opts)
    vim.bo[buf].modifiable = false
    vim.bo[buf].filetype = "weight-balance-report"

    -- Cerrar la ventana flotante fácilmente con 'q' o <Esc>
    vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf, silent = true })
    vim.keymap.set("n", "<Esc>", "<cmd>close<CR>", { buffer = buf, silent = true })
end

return M
