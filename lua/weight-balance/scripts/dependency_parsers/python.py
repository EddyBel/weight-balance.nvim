import sys
import importlib.util
import pathlib
import re


class PythonParser:
    def __init__(self, code):
        self.code = code
        self.lines = code.splitlines()

        self.stdlib = getattr(
            sys,
            "stdlib_module_names",
            set()
        )

    def _get_path_size(self, target_path):
        if not target_path or not target_path.exists():
            return None

        total_size = 0

        if target_path.is_file():
            return target_path.stat().st_size

        if target_path.is_dir():
            for file in target_path.rglob("*"):
                if file.is_file():
                    total_size += file.stat().st_size

        return total_size

    def _resolve_spec_size(self, path_str):
        try:
            spec = importlib.util.find_spec(path_str)
        except (ModuleNotFoundError, ValueError, ImportError):
            return None

        if spec is None:
            return None

        origin = spec.origin
        submodule_locations = spec.submodule_search_locations

        target_path = None

        if submodule_locations:
            target_path = pathlib.Path(submodule_locations[0])

        elif origin:
            target_path = pathlib.Path(origin)

        return self._get_path_size(target_path)

    def _parse_imports(self):
        imports_map = {}

        for line in self.lines:
            match_import = re.match(
                r"^\s*import\s+([a-zA-Z0-9_\.]+)",
                line
            )

            match_from = re.match(
                r"^\s*from\s+([a-zA-Z0-9_\.]+)\s+import",
                line
            )

            mod_path = None

            if match_import:
                mod_path = match_import.group(1)

            elif match_from:
                mod_path = match_from.group(1)

            if mod_path:
                # Ignorar importaciones relativas del proyecto
                if mod_path.startswith("."):
                    continue

                imports_map[mod_path] = line.strip()

        return imports_map

    def _parse_dependency(self, mod_path, raw_line):
        root_pkg = mod_path.split(".")[0]

        # Ignorar módulos pertenecientes a la librería estándar
        if root_pkg in self.stdlib:
            return None

        sub_size = self._resolve_spec_size(mod_path)

        root_size = None
        dep_type = "package"

        if "." in mod_path:
            root_size = self._resolve_spec_size(root_pkg)
            dep_type = "submodule"
        else:
            root_size = sub_size

        return {
            "name": mod_path,
            "raw": raw_line,
            "size": (
                sub_size
                if sub_size is not None
                else "not found"
            ),
            "root_size": (
                root_size
                if root_size is not None
                else "not found"
            ),
            "type": dep_type
        }

    def run(self):
        imports_map = self._parse_imports()

        results = []

        for mod_path, raw_line in imports_map.items():
            dependency = self._parse_dependency(
                mod_path,
                raw_line
            )

            if dependency is not None:
                results.append(dependency)

        return results
