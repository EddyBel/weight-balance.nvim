local BaseDetector = require("weight-balance.core.base-detector")

local M = BaseDetector.new({
    language = "lua",
    match_fn = function(line)
        return line:match("require")
    end
})

--- Ejecuta el análisis de dependencias de Lua de forma asíncrona utilizando el script externo.
--- @param callback function Función que recibe el arreglo de dependencias procesadas de Lua.
--- @param bufnr? number Número opcional del buffer (0 por defecto para el actual).
function M.check_dependencies(callback, bufnr)
    M:check(callback, bufnr)
end

return M
