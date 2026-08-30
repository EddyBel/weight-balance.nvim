local M = {}

--- Obtiene la ruta absoluta del directorio raíz del plugin.
local function get_plugin_root()
    local str = debug.getinfo(1, "S").source:sub(2)
    return vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(str)))
end

--- Busca y retorna la ruta del script o binario parser correspondiente al lenguaje solicitado.
--- @param lang string Nombre del lenguaje (ej. "python", "rust", "node").
--- @return string|nil Ruta absoluta del archivo encontrado o nil si no existe.
function M.get_parser_path(lang)
    local root = get_plugin_root()
    local parsers_dir = vim.fs.joinpath(root, "weight-balance", "scripts", "dependency_parsers")

    -- Extensiones admitidas para buscar el parser correspondiente
    local extensions = { "", ".py", ".rs", ".js", ".lua" }
    local is_windows = vim.uv.os_uname().sysname == "Windows"

    if is_windows then
        table.insert(extensions, ".exe")
    end

    for _, ext in ipairs(extensions) do
        local filename = lang .. ext
        local filepath = vim.fs.joinpath(parsers_dir, filename)

        if vim.uv.fs_stat(filepath) then
            return filepath
        end
    end

    return nil
end

return M
