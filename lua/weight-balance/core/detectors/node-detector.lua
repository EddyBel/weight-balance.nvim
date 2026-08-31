local BaseDetector = require("weight-balance.core.base-detector")

local M = BaseDetector.new({
    language = "node",
    match_fn = function(line)
        return line:match("import%s+") or line:match("require%s*%(")
    end
})

--- Ejecuta el análisis de dependencias de Node de forma asíncrona utilizando el script externo.
--- @param callback function Función que recibe el arreglo de dependencias procesadas de Node.
--- @param bufnr? number Número opcional del buffer (0 por defecto para el actual).
function M.check_dependencies(callback, bufnr)
    M:check(callback, bufnr)
end

return M
