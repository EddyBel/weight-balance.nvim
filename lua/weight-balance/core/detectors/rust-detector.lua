local BaseDetector = require("weight-balance.core.base-detector")

local M = BaseDetector.new({
    language = "rust",
    match_fn = function(line)
        return line:match("use%s+") or line:match("extern%s+crate")
    end
})

--- Ejecuta el análisis de dependencias de Rust de forma asíncrona utilizando el script externo.
--- @param callback function Función que recibe el arreglo de dependencias procesadas de Rust.
--- @param bufnr? number Número opcional del buffer (0 por defecto para el actual).
function M.check_dependencies(callback, bufnr)
    M:check(callback, bufnr)
end

return M
