local M = {}

-- Namespace utilizado exclusivamente para las marcas visuales
-- generadas por Weight Balance.
local ns_id = vim.api.nvim_create_namespace(
    "WeightBalanceVirtualText"
)


--- Renderiza las dependencias analizadas como texto virtual
--- al final de las líneas del buffer.
---
--- Este módulo no mantiene caché ni determina si los datos
--- cambiaron. Su única responsabilidad es representar
--- visualmente la información recibida.
---
--- @param deps table Lista de dependencias analizadas.
--- @param bufnr? number Número del buffer. `0` para el actual.
--- @param opts? table Opciones de renderizado.
--- @return nil
function M.render_dependencies_virt_text(deps, bufnr, opts)
    bufnr = bufnr or 0
    deps = deps or {}
    opts = opts or {}


    -- Configuración de renderizado.
    local aligned = opts.aligned or false

    local thresholds = opts.thresholds or {
        warning = 100 * 1024,
        danger = 1 * 1024 * 1024,
    }

    local icons = opts.icons or {
        low = "* ",
        warning = "! ",
        danger = "X ",
        not_found = "? ",
    }

    local highlights = opts.highlights or {
        low = "DiagnosticOk",
        warning = "DiagnosticWarn",
        danger = "DiagnosticError",
        not_found = "Comment",
    }


    -- Siempre limpiar el renderizado anterior.
    --
    -- El renderer no decide si es necesario actualizar:
    -- simplemente representa el estado que recibe.
    vim.api.nvim_buf_clear_namespace(
        bufnr,
        ns_id,
        0,
        -1
    )


    -- Si no existen dependencias, no hay nada que renderizar.
    if #deps == 0 then
        return
    end


    -- Obtener las líneas actuales del buffer.
    local lines = vim.api.nvim_buf_get_lines(
        bufnr,
        0,
        -1,
        false
    )


    -- Cuando el modo normalizado está activo necesitamos
    -- conocer la línea más larga que contiene una dependencia.
    local max_line_len = 0

    -- Guardar las dependencias que pudieron relacionarse
    -- con una línea del buffer.
    local matched_items = {}


    for _, dep in ipairs(deps) do
        if dep.raw then
            for idx, line_text in ipairs(lines) do
                if line_text:find(
                        dep.raw,
                        1,
                        true
                    ) then
                    if aligned then
                        local current_len =
                            vim.fn.strdisplaywidth(
                                line_text
                            )

                        if current_len > max_line_len then
                            max_line_len = current_len
                        end
                    end


                    table.insert(
                        matched_items,
                        {
                            dep = dep,
                            row = idx - 1,
                            line_text = line_text,
                        }
                    )

                    break
                end
            end
        end
    end


    -- Renderizar cada dependencia encontrada.
    for _, item in ipairs(matched_items) do
        local dep = item.dep
        local row = item.row
        local line_text = item.line_text


        -- Determinar si la dependencia no fue encontrada.
        local is_not_found =
            dep.size == "not found"
            or (
                dep.type == "submodule"
                and dep.root_size == "not found"
                and dep.size == "not found"
            )


        -- Determinar el tamaño que se mostrará.
        local display_text

        if dep.type == "submodule" then
            display_text =
                dep.display_size
                .. " / "
                .. dep.display_root_size
        else
            display_text = dep.display_size
        end

        -- Estado visual por defecto.
        local icon = icons.low
        local hl_group = highlights.low


        if is_not_found then
            icon = icons.not_found
                or "󰿝 "

            hl_group = highlights.not_found
                or "Comment"
        else
            local current_size_bytes =
                type(dep.size) == "number"
                and dep.size
                or 0


            if current_size_bytes >= thresholds.danger then
                icon = icons.danger
                hl_group = highlights.danger
            elseif current_size_bytes >= thresholds.warning then
                icon = icons.warning
                hl_group = highlights.warning
            end
        end


        -- Calcular separación entre el código y
        -- el texto virtual.
        local padding

        if aligned then
            local current_len =
                vim.fn.strdisplaywidth(
                    line_text
                )

            local diff =
                max_line_len - current_len

            padding =
                string.rep(
                    " ",
                    diff + 4
                )
        else
            padding = " "
        end


        local virt_text = {
            {
                padding
                .. icon
                .. display_text,
                hl_group,
            },
        }


        vim.api.nvim_buf_set_extmark(
            bufnr,
            ns_id,
            row,
            0,
            {
                virt_text = virt_text,
                virt_text_pos = "eol",
                hl_mode = "combine",
                priority = 200,
            }
        )
    end
end

function M.clear(bufnr)
    bufnr = bufnr or 0

    vim.api.nvim_buf_clear_namespace(
        bufnr,
        ns_id,
        0,
        -1
    )
end

function M.clear_all()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(bufnr) then
            M.clear(bufnr)
        end
    end
end

return M
