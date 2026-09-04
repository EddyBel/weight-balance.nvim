import os
import pathlib
import re


class LuaParser:

    def __init__(self, code):
        self.code = code
        self.lines = code.splitlines()

        self.stdlib = {
            "coroutine",
            "table",
            "io",
            "os",
            "string",
            "utf8",
            "math",
            "debug",
            "vim",
        }

    def _find_rockspec(self):
        current_dir = pathlib.Path.cwd()

        while True:
            for file in current_dir.glob("*.rockspec"):
                if file.is_file():
                    return file

            parent_dir = current_dir.parent

            if parent_dir == current_dir:
                break

            current_dir = parent_dir

        return None

    def _parse_rockspec_dependencies(self, rockspec_path):
        external_deps = set()

        if not rockspec_path:
            return external_deps

        try:
            content = rockspec_path.read_text(
                encoding="utf-8"
            )

            in_dependencies = False

            for line in content.splitlines():

                if (
                    "dependencies" in line
                    and "=" in line
                ):
                    in_dependencies = True
                    continue

                if in_dependencies:

                    if "}" in line:
                        in_dependencies = False

                    match = re.search(
                        r"""["']([\w\d_-]+)["']""",
                        line
                    )

                    if match:
                        external_deps.add(
                            match.group(1)
                        )

        except Exception:
            pass

        return external_deps

    def _parse_imports(self, allowed_deps):
        import_items = []

        for line in self.lines:

            matches = re.findall(
                r"""require\s*\(?\s*["']([\w\d_.-]+)["']\s*\)?""",
                line
            )

            for mod_name in matches:
                base_name = mod_name.split(".")[0]

                # Ignorar módulos estándar y vim
                if base_name in self.stdlib:
                    continue

                # Si existe un rockspec con dependencias,
                # limitar los resultados a esas dependencias.
                if (
                    allowed_deps
                    and base_name not in allowed_deps
                ):
                    continue

                sub_modules = set(
                    mod_name.split(".")[1:]
                )

                import_items.append({
                    "name": base_name,
                    "raw": line.strip(),
                    "sub_modules": sub_modules,
                    "has_sub": bool(sub_modules),
                })

        return import_items

    def _get_path_size(self, target_path):
        path = pathlib.Path(target_path)

        if not path.exists():
            return None

        total_size = 0

        try:
            if path.is_file():
                return path.stat().st_size

            if path.is_dir():
                for entry in path.rglob("*"):
                    if entry.is_file():
                        try:
                            total_size += entry.stat().st_size
                        except (PermissionError, OSError):
                            pass

        except (PermissionError, OSError):
            pass

        return total_size

    def _find_luarocks_package(self, pkg_name):
        luarocks_home = os.environ.get(
            "LUAROCKS_HOME",
            pathlib.Path.home() / ".luarocks"
        )

        search_dirs = [
            pathlib.Path(luarocks_home) / "share" / "lua",
            pathlib.Path("/usr/local/share/lua"),
            pathlib.Path("/usr/share/lua"),
        ]

        for base_dir in search_dirs:

            if not base_dir.exists():
                continue

            try:
                for version_dir in base_dir.iterdir():

                    if not version_dir.is_dir():
                        continue

                    pkg_path = (
                        version_dir / pkg_name
                    )

                    if pkg_path.exists():
                        return pkg_path

                    lua_file = pathlib.Path(
                        str(pkg_path) + ".lua"
                    )

                    if lua_file.exists():
                        return lua_file

            except (PermissionError, OSError):
                pass

        return None

    def _find_submodule_size(
        self,
        pkg_path,
        sub_modules
    ):
        if not pkg_path:
            return None

        package_path = pathlib.Path(pkg_path)

        if not package_path.is_dir():
            return None

        accumulated_size = 0
        found_any = False

        for sub in sub_modules:
            candidate_path = (
                package_path / sub
            )

            current_sub_size = None

            if candidate_path.exists():
                current_sub_size = self._get_path_size(
                    candidate_path
                )

            elif pathlib.Path(
                str(candidate_path) + ".lua"
            ).exists():
                current_sub_size = self._get_path_size(
                    str(candidate_path) + ".lua"
                )

            else:
                matched_file = None

                for file in package_path.rglob("*"):
                    if not file.is_file():
                        continue

                    if (
                        file.name.lower()
                        == sub.lower() + ".lua"
                    ):
                        matched_file = file
                        break

                if matched_file:
                    current_sub_size = (
                        self._get_path_size(
                            matched_file
                        )
                    )

            if current_sub_size is not None:
                accumulated_size += current_sub_size
                found_any = True

        if found_any:
            return accumulated_size

        return None

    def _parse_dependency(self, item):
        pkg_name = item["name"]

        pkg_path = self._find_luarocks_package(
            pkg_name
        )

        root_size = (
            self._get_path_size(pkg_path)
            if pkg_path
            else None
        )

        sub_size = None

        if (
            pkg_path
            and len(item["sub_modules"]) > 0
        ):
            sub_size = self._find_submodule_size(
                pkg_path,
                item["sub_modules"]
            )

            # Fallback del parser original
            if sub_size is None and root_size:
                sub_size = round(
                    root_size
                    / max(
                        len(item["sub_modules"]) * 2,
                        5
                    )
                )

        elif root_size is not None:
            sub_size = root_size

        else:
            sub_size = "not found"

        return {
            "name": pkg_name,
            "raw": item["raw"],
            "size": sub_size,
            "root_size": (
                root_size
                if root_size is not None
                else "not found"
            ),
            "type": (
                "submodule"
                if len(item["sub_modules"]) > 0
                else "package"
            ),
        }

    def run(self):
        rockspec_file = self._find_rockspec()

        allowed_deps = (
            self._parse_rockspec_dependencies(
                rockspec_file
            )
        )

        import_items = self._parse_imports(
            allowed_deps
        )

        results = []

        for item in import_items:
            dependency = self._parse_dependency(
                item
            )

            results.append(dependency)

        return results
