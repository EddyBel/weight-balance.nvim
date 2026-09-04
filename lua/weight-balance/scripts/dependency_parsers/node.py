import json
import pathlib
import re


class NodeParser:

    def __init__(self, code):
        self.code = code
        self.lines = code.splitlines()

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

    def _resolve_pkg_path(self, pkg_str):
        current_dir = pathlib.Path.cwd()

        while True:
            node_modules = current_dir / "node_modules"

            if node_modules.exists() and node_modules.is_dir():
                candidate = node_modules / pkg_str

                if candidate.exists():

                    if candidate.is_file():
                        return str(candidate)

                    # Intentar resolver mediante package.json
                    pkg_json = candidate / "package.json"

                    if pkg_json.exists():
                        try:
                            with open(
                                pkg_json,
                                "r",
                                encoding="utf-8"
                            ) as file:
                                data = json.load(file)

                                main = data.get(
                                    "main",
                                    "index.js"
                                )

                                main_path = candidate / main

                                if main_path.exists():
                                    return str(main_path)

                        except Exception:
                            pass

                    # Intentar extensiones conocidas
                    for ext in [
                        ".js",
                        ".json",
                        ".node",
                        ".ts",
                        ".tsx"
                    ]:
                        path = candidate.with_suffix(ext)

                        if path.exists():
                            return str(path)

                    # Último intento: index.js
                    index_file = candidate / "index.js"

                    if index_file.exists():
                        return str(index_file)

                    return str(candidate)

            parent_dir = current_dir.parent

            if parent_dir == current_dir:
                break

            current_dir = parent_dir

        return None

    def _parse_imports(self):
        imports_map = {}

        for line in self.lines:

            match = re.match(
                r'^\s*import\s+(?:([\w\s{},*]+)\s+from\s+)?([\'"])([^\'"]+)\2',
                line
            )

            pkg_name = None
            imported_items_str = None
            is_default_import = False

            if match:
                imported_items_str = match.group(1)
                pkg_name = match.group(3)

                if imported_items_str:
                    trimmed = imported_items_str.strip()

                    if (
                        not trimmed.startswith("{")
                        and not trimmed.startswith("*")
                    ):
                        is_default_import = True

                else:
                    is_default_import = True

            else:
                match = re.match(
                    r'^\s*(?:const|let|var)?\s*(?:([\w\s{},*]+)\s*=\s*)?require\s*\(\s*([\'"])([^\'"]+)\2\s*\)',
                    line
                )

                if match:
                    imported_items_str = match.group(1)
                    pkg_name = match.group(3)

                    if imported_items_str:
                        trimmed = imported_items_str.strip()

                        if not trimmed.startswith("{"):
                            is_default_import = True

                    else:
                        is_default_import = True

            if not pkg_name:
                continue

            # Ignorar imports locales
            if (
                pkg_name.startswith(".")
                or pkg_name.startswith("/")
            ):
                continue

            sub_modules = []

            if imported_items_str:
                clean_str = imported_items_str.strip()

                if (
                    clean_str.startswith("{")
                    and clean_str.endswith("}")
                ):
                    clean_str = clean_str[1:-1]

                    sub_modules = [
                        s.strip().split(" as ")[0]
                        for s in clean_str.split(",")
                        if s.strip()
                    ]

            if pkg_name not in imports_map:
                imports_map[pkg_name] = {
                    "raw": line.strip(),
                    "sub_modules": set(),
                    "is_default": is_default_import,
                }

            if not is_default_import:
                imports_map[pkg_name]["is_default"] = False

            for sub in sub_modules:
                imports_map[pkg_name]["sub_modules"].add(sub)

        return imports_map

    def _get_root_package(self, pkg_name):
        parts = pkg_name.split("/")

        if pkg_name.startswith("@"):
            if len(parts) >= 2:
                return "/".join(parts[:2])

        elif len(parts) >= 1:
            return parts[0]

        return pkg_name

    def _get_root_size(self, resolved_root_path, root_pkg):
        if not resolved_root_path:
            return None

        root_dir = pathlib.Path(
            resolved_root_path
        ).parent

        while (
            root_dir
            and root_dir.name != root_pkg
            and root_dir.parent != root_dir
        ):
            if (root_dir / "package.json").exists():
                break

            root_dir = root_dir.parent

        return self._get_path_size(root_dir)

    def _get_submodules_size(
        self,
        resolved_root_path,
        sub_modules
    ):
        if not resolved_root_path:
            return None

        root_dir = pathlib.Path(
            resolved_root_path
        ).parent

        accumulated_size = 0
        found_any = False

        for sub in sub_modules:
            candidate_path = root_dir / sub
            current_sub_size = None

            if candidate_path.exists():
                current_sub_size = self._get_path_size(
                    candidate_path
                )

            else:
                for ext in [
                    ".js",
                    ".jsx",
                    ".ts",
                    ".tsx"
                ]:
                    ext_path = pathlib.Path(
                        str(candidate_path) + ext
                    )

                    if ext_path.exists():
                        current_sub_size = self._get_path_size(
                            ext_path
                        )
                        break

            if current_sub_size is not None:
                accumulated_size += current_sub_size
                found_any = True

        if found_any:
            return accumulated_size

        return None

    def _parse_dependency(self, pkg_name, data):
        root_pkg = self._get_root_package(pkg_name)

        resolved_sub_path = self._resolve_pkg_path(
            pkg_name
        )

        resolved_root_path = self._resolve_pkg_path(
            root_pkg
        )

        sub_size = None

        if resolved_sub_path:
            sub_size = self._get_path_size(
                resolved_sub_path
            )

        root_size = self._get_root_size(
            resolved_root_path,
            root_pkg
        )

        # Si no pudimos resolver directamente el submódulo,
        # intentar calcular su tamaño mediante los elementos importados.
        if (
            sub_size is None
            and root_size is not None
            and len(data["sub_modules"]) > 0
        ):
            sub_size = self._get_submodules_size(
                resolved_root_path,
                data["sub_modules"]
            )

        # Si no se encontró el submódulo,
        # utilizar el tamaño del paquete raíz.
        if sub_size is None:
            sub_size = root_size

        dep_type = "package"

        if (
            pkg_name != root_pkg
            or len(data["sub_modules"]) > 0
        ):
            dep_type = "submodule"

        else:
            root_size = sub_size

        return {
            "name": pkg_name,
            "raw": data["raw"],
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
            "type": dep_type,
        }

    def run(self):
        imports_map = self._parse_imports()

        results = []

        for pkg_name, data in imports_map.items():
            dependency = self._parse_dependency(
                pkg_name,
                data
            )

            results.append(dependency)

        return results
