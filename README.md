<h1 align="center">weight-balance.nvim</h1>

<p align="center">An asynchronous dependency analysis plugin for Neovim</p>

<p align="center">
 <img alt="banner_01" src="https://img.shields.io/github/last-commit/EddyBel/weight-balance.nvim?color=%23AED6F1&style=for-the-badge" />
 <img alt="banner_02" src="https://img.shields.io/github/license/EddyBel/weight-balance.nvim?color=%23EAECEE&style=for-the-badge" />
 <img alt="banner_03" src="https://img.shields.io/github/languages/top/EddyBel/weight-balance.nvim?color=%23F9E79F&style=for-the-badge" />
 <img alt="banner_04" src="https://img.shields.io/github/languages/count/EddyBel/weight-balance.nvim?color=%23ABEBC6&style=for-the-badge" />
 <img alt="banner_05" src="https://img.shields.io/github/languages/code-size/EddyBel/weight-balance.nvim?color=%23F1948A&style=for-the-badge" />
</p>

An asynchronous Neovim plugin that calculates and displays the disk size of your dependencies and imports in real time, directly inside the editor using virtual text.

<img src="./docs/assets/preview_1.png" alt="Preview 1" width="100%">
<img src="./docs/assets/preview_2.png" alt="Preview 2" width="100%">
<img src="./docs/assets/preview_3.png" alt="Preview 3" width="100%">
<img src="./docs/assets/preview_4.png" alt="Preview 4" width="100%">
<img src="./docs/assets/preview_5.gif" alt="Preview 5" width="100%">

## Purpose

Modern software development relies heavily on external libraries and packages. **weight-balance.nvim** provides instant visibility into the actual footprint of your dependencies as you write code.

It calculates the disk size of imported dependencies and displays the result directly next to your imports, helping you quickly identify potentially heavy dependencies without leaving your editor.

The plugin is designed to remain lightweight and responsive by performing its analysis asynchronously through Neovim's native APIs.

## Requirements

- **Neovim** >= 0.10.0 (uses `vim.system`)
- **Python** 3.x (used internally for parsing imports and calculating package sizes)

## Features

### Current Features

- [x] **Python support** — Analyzes imported modules and third-party packages.
- [x] **Rust support** — Calculates the disk size of imported crates.
- [x] **JavaScript / TypeScript support** — Calculates the size of Node.js packages.
- [x] **JSX / TSX support** — Fully supports React component files.
- [x] **Lua support** — Analyzes imports from local and external modules.
- [x] **Normalized virtual text** — Automatically aligns virtual text indicators based on the longest import line in the buffer.
- [x] **Smart caching** — Avoids redundant calculations by tracking buffer checksums.

### Roadmap

- [ ] **Expand language support:**

  - **Go** — `import` statements and `go.mod` dependency analysis.
  - **C / C++** — `#include` directives for libraries and local/external headers.
  - **C#** — `using` statements and NuGet references.
  - **Java / Kotlin** — `import` statements and Maven/Gradle dependency management.
  - **PHP** — `require`, `include`, and Composer packages.
  - **Ruby** — `require` and Gemfile dependencies.

- [ ] **Image dependency analysis** — Detect, resolve, and calculate the disk size of image files referenced within projects, with support for formats such as PNG, JPEG, WEBP, SVG, and GIF.

## Installation

### lazy.nvim

```lua
{
    "EddyBel/weight-balance.nvim",
    opts = {},
}
```

### packer.nvim

```lua
use {
    "EddyBel/weight-balance.nvim",
    config = function()
        require("weight-balance").setup()
    end
}
```

### Native Packages (`vim.packadd`)

```lua
-- Install and load the plugin natively with vim.pack
vim.pack.add({ 'https://github.com/EddyBel/weight-balance.nvim', })
```

Then add the following to your `init.lua`:

```lua
require("weight-balance").setup()
```

## Configuration

You can customize thresholds, icons, enabled filetypes, and virtual text behavior through the `setup()` function:

```lua
require("weight-balance").setup({

        -- Enable automatic dependency analysis.
        --
        -- When enabled, Weight Balance automatically analyzes the current
        -- buffer when relevant buffer events occur.
        --
        -- Set to false to perform dependency analysis manually.
        auto_check = true,


        -- Enable or disable plugin notifications.
        --
        -- When enabled, Weight Balance can display notifications for
        -- errors, warnings, server events and other relevant states.
        notification = true,


        -- Delay in milliseconds before running an analysis after a buffer
        -- change.
        --
        -- This prevents the plugin from sending a request to the backend
        -- for every single keystroke when the user is actively typing.
        --
        -- Set to 0 to disable debouncing.
        debounce = 200,


        -- Buffer and language configuration.
        --
        -- Defines which filetypes Weight Balance supports and how their
        -- dependencies/imports should be detected.
        buffer = {

            -- Language-specific configuration.
            --
            -- The key is the Neovim filetype.
            languages = {

                -- Python files.
                python = {
                    -- Language identifier sent to the Python backend.
                    parser = "python",

                    -- Patterns used to detect dependencies/imports.
                    imports = {
                        "import%s+",
                        "from%s+",
                    },
                },


                -- JavaScript files.
                javascript = {
                    parser = "node",

                    imports = {
                        "import%s+",
                        "require%s*%(",
                        "from%s+",
                    },
                },


                -- JavaScript React files.
                javascriptreact = {
                    parser = "node",

                    imports = {
                        "import%s+",
                        "require%s*%(",
                        "from%s+",
                    },
                },


                -- TypeScript files.
                typescript = {
                    parser = "node",

                    imports = {
                        "import%s+",
                        "require%s*%(",
                        "from%s+",
                    },
                },


                -- TypeScript React files.
                typescriptreact = {
                    parser = "node",

                    imports = {
                        "import%s+",
                        "require%s*%(",
                        "from%s+",
                    },
                },


                -- Rust files.
                rust = {
                    parser = "rust",

                    imports = {
                        "use%s+",
                        "extern%s+crate%s+",
                    },
                },


                -- Lua files.
                lua = {
                    parser = "lua",

                    imports = {
                        "require%s*%(",
                    },
                },
            },
        },


        -- Python backend server configuration.
        server = {

            -- Host where the backend server is running.
            --
            -- 127.0.0.1 restricts the server to the local machine.
            host = "127.0.0.1",

            -- TCP port used by the Weight Balance backend.
            port = 9090,

            -- Optional Python executable used to start the backend.
            --
            -- When nil, Weight Balance automatically searches for:
            --
            -- Linux/macOS:
            --   python3
            --   python
            --
            -- Windows:
            --   py
            --   python
            --
            -- Example:
            -- python_command = "/usr/bin/python3"
            python_command = nil,
        },


        -- Virtual text configuration.
        virtualtext = {

            -- Align virtual text by using the width required by the
            -- longest dependency information.
            --
            -- When enabled, all virtual text starts at the same column,
            -- creating a consistent visual alignment.
            aligned = false,

            -- Size thresholds used to determine dependency severity.
            thresholds = {

                -- Dependencies below this value are considered low impact.
                --
                -- Default: 100 KB
                warning = 100 * 1024,

                -- Dependencies at or above this value are considered
                -- dangerous.
                --
                -- Default: 1 MB
                danger = 1 * 1024 * 1024,
            },


            -- Icons displayed according to dependency severity.
            --
            -- These defaults use standard Unicode characters and do not
            -- require Nerd Fonts.
            icons = {

                -- Dependency below the warning threshold.
                low = " ",

                -- Dependency at or above the warning threshold.
                warning = " ",

                -- Dependency at or above the danger threshold.
                danger = " ",

                -- Dependency could not be found or its size could not
                -- be determined.
                not_found = "󰒲 ",
            },


            -- Highlight groups used for each dependency state.
            --
            -- These use Neovim's built-in diagnostic highlight groups.
            highlights = {

                -- Low-impact dependency.
                low = "DiagnosticOk",

                -- Warning-level dependency.
                warning = "DiagnosticWarn",

                -- Dangerous dependency.
                danger = "DiagnosticError",

                -- Dependency not found.
                not_found = "Comment",
            },
        },
})
```

### Configuration Options

| Option                                | Type          | Default           | Description                                                                             |
| ------------------------------------- | ------------- | ----------------- | --------------------------------------------------------------------------------------- |
| `auto_check`                          | `boolean`     | `true`            | Enables automatic dependency analysis on buffer changes.                                |
| `notification`                        | `boolean`     | `true`            | Enables or disables plugin notifications.                                               |
| `debounce`                            | `number`      | `200`             | Delay in milliseconds before analyzing a changed buffer.                                |
| `buffer.languages`                    | `table`       | See defaults      | Defines the supported filetypes and their dependency detection configuration.           |
| `buffer.languages.<filetype>.parser`  | `string`      | —                 | Parser identifier used by the Python backend for the specified filetype.                |
| `buffer.languages.<filetype>.imports` | `table`       | —                 | Lua patterns used to detect dependencies/import statements.                             |
| `server.host`                         | `string`      | `"127.0.0.1"`     | Host where the Weight Balance backend runs.                                             |
| `server.port`                         | `number`      | `9090`            | TCP port used by the Weight Balance backend.                                            |
| `server.python_command`               | `string\|nil` | `nil`             | Python executable used to start the backend. When `nil`, it is detected automatically.  |
| `virtualtext.aligned`                 | `boolean`     | `false`           | Aligns all virtual text indicators using the longest import line when enabled.          |
| `virtualtext.thresholds.warning`      | `number`      | `100 * 1024`      | Byte size at which a dependency enters the warning state.                               |
| `virtualtext.thresholds.danger`       | `number`      | `1 * 1024 * 1024` | Byte size at which a dependency enters the danger state.                                |
| `virtualtext.icons`                   | `table`       | See defaults      | Icons displayed for each dependency state: `low`, `warning`, `danger`, and `not_found`. |
| `virtualtext.highlights`              | `table`       | See defaults      | Neovim highlight groups used for each dependency state.                                 |

## Commands

| Command                     | Description                                                                               |
| --------------------------- | ----------------------------------------------------------------------------------------- |
| `:WeightBalanceCheckDeps`   | Manually analyzes the dependencies of the current buffer.                                 |
| `:WeightBalanceAlignedText` | Aligns all virtual text indicators to the same column.                                    |
| `:WeightBalanceNormalText`  | Disables virtual text alignment and displays each indicator immediately after its import. |

## Contributing

Contributions, bug reports, feature requests, and pull requests are welcome!

If you find a bug or have an idea for improving the plugin, feel free to open an issue or submit a pull request on GitHub.

## License

This project is open-source software licensed under the [MIT](https://www.google.com/search?q=LICENSE) license.

---

<p align="center">
  <a href="https://github.com/EddyBel" target="_blank">
    <img alt="Github" src="https://img.shields.io/badge/GitHub-%2312100E.svg?&style=for-the-badge&logo=Github&logoColor=white" />
  </a>
  <a href="https://www.linkedin.com/in/eduardo-rangel-eddybel/" target="_blank">
    <img alt="LinkedIn" src="https://img.shields.io/badge/linkedin-%230077B5.svg?&style=for-the-badge&logo=linkedin&logoColor=white" />
  </a>
</p>
