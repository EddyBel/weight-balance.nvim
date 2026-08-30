local format_size = require("weight-balance.utils.format").format_size
local search_parser = require("weight-balance.utils.search_parsers").get_parser_path

local M = {}

-- Caché por buffer para almacenar la firma de las importaciones de Lua y evitar ejecuciones redundantes
local buffer_cache = {}

--- Ejecuta el análisis de dependencias de Lua de forma asíncrona utilizando el script externo.
--- @param callback function Función que recibe el arreglo de dependencias procesadas de Lua.
--- @param bufnr? number Número opcional del buffer (0 por defecto para el actual).
function M.check_lua_dependencies(callback, bufnr)
    bufnr = bufnr or 0

    local script_path = search_parser("lua")
    if not script_path then
        vim.notify("No se encontró el script parser para Lua en la carpeta de scripts.", vim.log.levels.ERROR,
            { title = "WeightBalance" })
        if callback then callback(nil) end
        return
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    local current_imports = {}
    for _, line in ipairs(lines) do
        if line:match("require") then
            table.insert(current_imports, line)
        end
    end

    local imports_signature = table.concat(current_imports, "\n")
    buffer_cache[bufnr] = buffer_cache[bufnr] or { signature = nil, deps = nil }

    if buffer_cache[bufnr].signature == imports_signature and buffer_cache[bufnr].deps then
        if callback then
            callback(buffer_cache[bufnr].deps)
        end
        return
    end

    local buffer_content = table.concat(lines, "\n")

    vim.system(
        { "python3", script_path },
        { text = true, stdin = buffer_content },
        function(result)
            vim.schedule(function()
                if result.code ~= 0 then
                    vim.notify("Error al ejecutar el analizador de Lua: " .. (result.stderr or ""), vim.log.levels
                        .ERROR,
                        { title = "WeightBalance" })
                    if callback then callback(nil) end
                    return
                end

                local ok, parsed = pcall(vim.fn.json_decode, result.stdout)
                if not ok or not parsed then
                    vim.notify("No se pudieron parsear los resultados de las dependencias de Lua.", vim.log.levels
                        .ERROR,
                        { title = "WeightBalance" })
                    if callback then callback(nil) end
                    return
                end

                local dependencies_info = {}
                for _, item in ipairs(parsed) do
                    local formatted_tamano = "not found"
                    if type(item.size) == "number" then
                        formatted_tamano = format_size(item.size)
                    end

                    local formatted_root_tamano = "not found"
                    if type(item.root_size) == "number" then
                        formatted_root_tamano = format_size(item.root_size)
                    end

                    table.insert(dependencies_info, {
                        name = item.name,
                        raw = item.raw,
                        size = item.size,
                        tamano = formatted_tamano,
                        root_size = item.root_size,
                        root_tamano = formatted_root_tamano,
                        type = item.type,
                    })
                end

                buffer_cache[bufnr].signature = imports_signature
                buffer_cache[bufnr].deps = dependencies_info

                if callback then
                    callback(dependencies_info)
                end
            end)
        end
    )
end

return M
