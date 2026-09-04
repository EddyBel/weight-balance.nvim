package = "weight-balance"
version = "2.0.0-1"
source = {
    url = "git://github.com/EddyBel/weight-balance.nvim",
    tag = "v2.0.0"
}
description = {
    summary = "Real-time analysis of dependency and import sizes in Neovim",
    detailed =
    "An asynchronous plugin to calculate the weight of Rust crates, Lua packages, Python, and Node modules directly inside the editor.",
    homepage = "https://github.com/EddyBel/weight-balance.nvim",
    license = "MIT"
}
dependencies = {
    "lua >= 5.1"
}
build = {
    type = "builtin",
    modules = {
        ["weight-balance"] = "lua/weight-balance/init.lua",
    }
}
