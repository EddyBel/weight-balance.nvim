local M = {}

-- Namespace único para limpiar las marcas anteriores si se vuelve a ejecutar
local ns_id = vim.api.nvim_create_namespace("WeightBalanceVirtualText")

-- Caché interna para almacenar el estado anterior por buffer y evitar redibujados innecesarios
local cache = {}

--- Renderiza texto virtual al final de las líneas (eol) en el buffer de Neovim
--- de forma optimizada: solo se actualiza si cambian las dependencias o las líneas,
--- y mantiene una prioridad fija para evitar que se desplace con otros mensajes eol.
---
--- @param deps table Lista de tablas con la información de las dependencias analizadas.
--- @param bufnr? number Número opcional del buffer (`0` para el buffer activo actual por defecto).
--- @param opts? table Tabla de configuración opcional para umbrales, iconos, estilos y normalizado.
--- @return nil
function M.render_dependencies_virt_text(deps, bufnr, opts)
    bufnr = bufnr or 0

    if not deps then
        deps = {}
    end

    -- Obtener el contenido actual del buffer para verificar cambios estrictos
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Crear una firma o huella digital rápida del estado actual asegurando manejo de tipos seguros
    local checksum = #deps
    for _, d in ipairs(deps) do
        local val = type(d.size) == "number" and d.size or 0
        checksum = checksum + val
    end
    for idx = 1, math.min(#lines, 5) do
        checksum = checksum + #lines[idx]
    end

    -- Inicializar caché para el buffer si no existe
    cache[bufnr] = cache[bufnr] or { last_checksum = nil }

    -- Si el checksum es idéntico, la información no ha cambiado: salimos para evitar redibujados
    if cache[bufnr].last_checksum == checksum then
        return
    end

    -- Actualizar la caché con el nuevo estado
    cache[bufnr].last_checksum = checksum

    -- Configuración por defecto usando grupos de resaltado estándar de Neovim y umbrales en bytes
    opts = opts or {}
    local normalized = opts.normalized or true

    local thresholds = opts.thresholds or {
        warning = 100 * 1024,     -- 100 KB por defecto
        danger = 1 * 1024 * 1024, -- 1 MB por defecto
    }

    local icons = opts.icons or {
        low = " ", -- Icono de planta/hoja
        warning = " ", -- Icono de advertencia
        danger = " ", -- Icono de peligro
        not_found = "󰿝 ", -- Icono para paquetes no encontrados
    }

    local highlights = opts.highlights or {
        low = "DiagnosticOk",       -- Verde por defecto del tema (LSP Ok)
        warning = "DiagnosticWarn", -- Amarillo/Naranja por defecto del tema (LSP Warn)
        danger = "DiagnosticError", -- Rojo por defecto del tema (LSP Error)
        not_found = "Comment",      -- Gris oscuro estándar de los comentarios en los temas de Neovim
    }

    -- Limpiar marcas anteriores para evitar duplicados al actualizar
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

    -- Si el modo normalizado está activo, calculamos primero la longitud máxima de línea entre las dependencias encontradas
    local max_line_len = 0
    local matched_items = {}

    for _, dep in ipairs(deps) do
        for idx, line_text in ipairs(lines) do
            if line_text:find(dep.raw, 1, true) then
                if normalized then
                    local current_len = vim.fn.strdisplaywidth(line_text)
                    if current_len > max_line_len then
                        max_line_len = current_len
                    end
                end
                table.insert(matched_items, { dep = dep, row = idx - 1, line_text = line_text })
                break
            end
        end
    end

    -- Renderizar cada elemento guardado aplicando el espaciado si está normalizado
    for _, item in ipairs(matched_items) do
        local dep = item.dep
        local row = item.row
        local line_text = item.line_text

        -- Determinar si el paquete no fue encontrado en el sistema
        local is_not_found = (dep.size == "not found" or (dep.type == "submodule" and dep.root_size == "not found" and dep.size == "not found"))

        -- Determinar el texto a mostrar basándose en el tipo de importación
        local display_text = ""
        if dep.type == "submodule" then
            display_text = dep.tamano .. " / " .. dep.root_tamano
        else
            display_text = dep.tamano
        end

        -- Evaluar estado, icono y grupo de resaltado
        local icon = icons.low
        local hl_group = highlights.low

        if is_not_found then
            icon = icons.not_found or "󰿝 "
            hl_group = highlights.not_found or "Comment"
        else
            local current_size_bytes = type(dep.size) == "number" and dep.size or 0

            if current_size_bytes >= thresholds.danger then
                icon = icons.danger
                hl_group = highlights.danger
            elseif current_size_bytes >= thresholds.warning then
                icon = icons.warning
                hl_group = highlights.warning
            end
        end

        -- Calcular padding si el modo normalizado está activado (+ 4 espacios de separación mínima)
        local padding = ""
        if normalized then
            local current_len = vim.fn.strdisplaywidth(line_text)
            local diff = max_line_len - current_len
            padding = string.rep(" ", diff + 4)
        else
            padding = " "
        end

        local virt_text = {
            { padding .. icon .. display_text, hl_group }
        }

        vim.api.nvim_buf_set_extmark(bufnr, ns_id, row, 0, {
            virt_text = virt_text,
            virt_text_pos = "eol",
            hl_mode = "combine",
            priority = 200,
        })
    end
end

-- function M.check_and_show()
--     local python_detector = require("weight-balance.core.python-detector")
--     local deps = python_detector.check_python_dependencies()
--
--     if deps then
--         M.render_dependencies_virt_text(deps, 0)
--     end
-- end

return M
