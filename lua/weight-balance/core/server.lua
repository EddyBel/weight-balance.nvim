local SEARCH_PARSERS = require("weight-balance.utils.search_parsers")

local Server = {}

local DEFAULT_CONFIG = {
    host = "127.0.0.1",
    port = 9090,
    python_command = nil,
}

local config = vim.tbl_deep_extend(
    "force",
    {},
    DEFAULT_CONFIG
)

local PATH_SERVER = SEARCH_PARSERS.get_server_path(
    "weight-server.py"
)

local server_job = nil
local autocmd_registered = false


--- Detect the current operating system.
---
--- @return string OS identifier: "windows", "macos", or "linux".
--- @private
local function get_os()
    local uname = vim.uv.os_uname()

    if uname.sysname == "Windows_NT" then
        return "windows"
    end

    if uname.sysname == "Darwin" then
        return "macos"
    end

    return "linux"
end


--- Resolve the Python executable used to launch the backend.
---
--- If python_command is explicitly configured, it takes priority.
--- Otherwise, a suitable Python command is searched according
--- to the current operating system.
---
--- @return string|nil command Python executable or nil if unavailable.
--- @return string|nil error Error message when no Python executable is found.
--- @private
local function get_python_command()
    if config.python_command
        and config.python_command ~= ""
    then
        if vim.fn.executable(config.python_command) == 1 then
            return config.python_command
        end

        return nil,
            "Python command not found: "
            .. config.python_command
    end

    local os = get_os()

    local candidates

    if os == "windows" then
        candidates = {
            "py",
            "python",
        }
    else
        candidates = {
            "python3",
            "python",
        }
    end

    for _, command in ipairs(candidates) do
        if vim.fn.executable(command) == 1 then
            return command
        end
    end

    return nil,
        "Python executable not found. "
        .. "Install Python or configure "
        .. "`python_command`."
end


--- Register an automatic cleanup autocommand on VimLeavePre.
---
--- Ensures that the background server process is stopped cleanly when Neovim exits.
--- This action is registered only once to avoid duplicate autocmds.
---
--- @return nil
--- @private
local function register_cleanup()
    if autocmd_registered then
        return
    end

    autocmd_registered = true

    vim.api.nvim_create_autocmd(
        "VimLeavePre",
        {
            callback = function()
                Server.stop()
            end,
        }
    )
end


--- Update the internal server configuration options.
---
--- Unspecified options preserve their current or default values.
---
--- @param opts table|nil Configuration table overrides.
--- @return nil
--- @private
local function configure(opts)
    opts = opts or {}

    config = vim.tbl_deep_extend(
        "force",
        config,
        opts
    )
end

local function check_server(callback)
    vim.system(
        {
            "curl",
            "-sS",
            "-X",
            "POST",
            "http://"
            .. config.host
            .. ":"
            .. tostring(config.port)
            .. "/",
        },
        {
            text = true,
        },
        function(result)
            vim.schedule(function()
                if result.code ~= 0 then
                    callback(false)
                    return
                end

                local ok, response =
                    pcall(
                        vim.json.decode,
                        result.stdout
                    )

                if not ok then
                    callback(false)
                    return
                end

                if type(response) ~= "table" then
                    callback(false)
                    return
                end

                local is_weight_balance =
                    response.status == "ok"
                    and response.service == "weight-balance"

                callback(is_weight_balance)
            end)
        end
    )
end

--- Launch the Python backend server.
---
--- @param callback? function Optional completion handler function(success, err_msg).
--- @param opts? table Optional server configuration parameters.
--- @return nil
function Server.start(callback, opts)
    configure(opts)

    if server_job then
        if callback then
            vim.schedule(function()
                callback(true)
            end)
        end

        return
    end

    if not PATH_SERVER then
        if callback then
            vim.schedule(function()
                callback(
                    false,
                    "weight-server.py not found"
                )
            end)
        end

        return
    end

    check_server(function(running)
        if running then
            if callback then
                callback(true)
            end

            return
        end

        local python_command, python_error =
            get_python_command()

        if not python_command then
            if callback then
                callback(
                    false,
                    python_error
                )
            end

            return
        end

        register_cleanup()

        local current_pid =
            tostring(vim.uv.os_getpid())

        server_job = vim.system(
            {
                python_command,
                PATH_SERVER,

                "--parent-pid",
                current_pid,

                "--host",
                config.host,

                "--port",
                tostring(config.port),
            },
            {
                detach = true,
            },
            function(result)
                server_job = nil

                if result.code ~= 0 then
                    check_server(function(running)
                        if running then
                            return
                        end

                        vim.schedule(function()
                            vim.notify(
                                "Weight Balance server stopped unexpectedly",
                                vim.log.levels.ERROR
                            )
                        end)
                    end)
                end
            end
        )

        if callback then
            vim.schedule(function()
                callback(true)
            end)
        end
    end)
end

--- Stop the backend server process manually or automatically.
---
--- Sends SIGTERM (signal 15) to terminate the active job process handle.
---
--- @return nil
function Server.stop()
    if not server_job then
        return
    end

    server_job:kill(15)

    server_job = nil
end

--- Send code and language payload to the backend via an asynchronous HTTP request.
---
--- @param code string The text content/code of the current buffer.
--- @param language string The detected language identifier.
--- @param callback function Completion handler function(result, error).
--- @return nil
function Server.request(
    code,
    language,
    callback
)
    if not code then
        callback(
            nil,
            "Missing buffer code"
        )

        return
    end

    if not language then
        callback(
            nil,
            "Missing language"
        )

        return
    end

    local body = vim.json.encode({
        code = code,
        language = language,
    })

    vim.system(
        {
            "curl",
            "-s",

            "-X",
            "POST",

            "http://"
            .. config.host
            .. ":"
            .. config.port
            .. "/get_dependency_size",

            "-H",
            "Content-Type: application/json",

            "-d",
            body,
        },
        {
            text = true,
        },
        function(result)
            vim.schedule(function()
                if result.code ~= 0 then
                    callback(
                        nil,
                        result.stderr
                    )

                    return
                end

                local ok, output = pcall(
                    vim.json.decode,
                    result.stdout
                )

                if not ok then
                    callback(
                        nil,
                        result.stdout
                    )

                    return
                end

                if output.success == false then
                    callback(
                        nil,
                        output
                    )

                    return
                end

                callback(output)
            end)
        end
    )
end

--- Retrieve a deep copy of the current server configuration settings.
---
--- @return table Configuration table containing host, port and Python command.
function Server.get_config()
    return vim.deepcopy(config)
end

return Server
