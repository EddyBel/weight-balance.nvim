local Autocmd = {}

local GROUP_NAME = "WeightBalance"

local group_id = vim.api.nvim_create_augroup(
    GROUP_NAME,
    {
        clear = true,
    }
)

-- Crear los autocommands responsables de ejecutar
-- automáticamente el análisis del buffer.
--
-- Eventos:
--     BufEnter:
--         Ejecuta el análisis al entrar a un buffer.
--
--     TextChanged:
--         Ejecuta el análisis después de modificar el buffer
--         desde el modo normal.
--
--     TextChangedI:
--         Ejecuta el análisis mientras se modifica el buffer
--         desde el modo insert.
--
function Autocmd.create(api)
    vim.api.nvim_create_autocmd(
        {
            "BufEnter",
            "TextChanged",
            "TextChangedI",
        },
        {
            group = group_id,

            callback = function()
                api.run_analysis()
            end,
        }
    )
end

return Autocmd
