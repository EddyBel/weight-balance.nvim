local BaseDetector = require("weight-balance.core.base-detector")

local M = BaseDetector.new({
    language = "python",
    match_fn = function(line)
        return line:match("^%s*import%s+") or line:match("^%s*from%s+")
    end
})

function M.check_dependencies(callback, bufnr)
    M:check(callback, bufnr)
end

return M
