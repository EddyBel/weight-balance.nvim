local Commands = {}

-- Define los comandos de usuario del plugin.
--
-- La instancia de API se recibe como dependencia para evitar
-- que este módulo tenga que conocer o importar directamente
-- la implementación de la API.
--
function Commands.create(api)
    -- Ejecutar análisis manualmente.
    vim.api.nvim_create_user_command(
        "WeightBalanceCheckDeps",
        function()
            api.run_analysis()
        end,
        {
            desc = "Analyze current buffer dependencies",
        }
    )

    -- Activar el modo de texto normalizado.
    vim.api.nvim_create_user_command(
        "WeightBalanceAlignedText",
        function()
            api.set_aligned(true)
        end,
        {
            desc = "Enable normalized dependency sizes",
        }
    )

    -- Activar el modo de texto convencional.
    vim.api.nvim_create_user_command(
        "WeightBalanceNormalText",
        function()
            api.set_aligned(false)
        end,
        {
            desc = "Disable normalized dependency sizes",
        }
    )

    -- -- Activar Weight Balance.
    -- vim.api.nvim_create_user_command(
    --     "WeightBalanceEnable",
    --     function()
    --         api.enable()
    --     end,
    --     {
    --         desc = "Enable Weight Balance",
    --     }
    -- )
    --
    -- -- Desactivar Weight Balance.
    -- vim.api.nvim_create_user_command(
    --     "WeightBalanceDisable",
    --     function()
    --         api.disable()
    --     end,
    --     {
    --         desc = "Disable Weight Balance",
    --     }
    -- )
    --
    -- -- Alternar entre habilitado y deshabilitado.
    -- vim.api.nvim_create_user_command(
    --     "WeightBalanceToggle",
    --     function()
    --         api.toggle()
    --     end,
    --     {
    --         desc = "Toggle Weight Balance",
    --     }
    -- )
end

return Commands
