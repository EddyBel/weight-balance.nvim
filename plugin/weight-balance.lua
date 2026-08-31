--plugin/weight-balance.lua
-- lazy.nvim se encarga de llamar a require("weight-balance").setup() mediante opts,
-- pero esto sirve como respaldo si se carga sin lazy.
pcall(function()
    require("weight-balance").setup()
end)
