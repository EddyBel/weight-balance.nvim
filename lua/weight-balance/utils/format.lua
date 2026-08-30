local M = {}

-- Función para formatear bytes a unidades legibles (B, KB, MB, GB, etc.)
function M.format_size(bytes)
    if bytes == 0 then return "0 B" end
    local units = { "B", "KB", "MB", "GB", "TB" }
    local i = 1
    while bytes >= 1024 and i < #units do
        bytes = bytes / 1024
        i = i + 1
    end
    return string.format("%.2f %s", bytes, units[i])
end

return M
