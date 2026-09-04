import os
import pathlib
import re


class RustParser:

    def __init__(self, code):
        self.code = code
        self.lines = code.splitlines()

    def _find_cargo_toml(self):
        current_dir = pathlib.Path.cwd()

        while True:
            cargo_path = current_dir / "Cargo.toml"

            if cargo_path.exists() and cargo_path.is_file():
                return cargo_path

            parent_dir = current_dir.parent

            if parent_dir == current_dir:
                break

            current_dir = parent_dir

        return None

    def _parse_cargo_dependencies(self, cargo_path):
        external_deps = set()

        if not cargo_path:
            return external_deps

        try:
            content = cargo_path.read_text(
                encoding="utf-8"
            )

            in_dependencies = False

            for line in content.splitlines():
                line_stripped = line.strip()

                if (
                    not line_stripped
                    or line_stripped.startswith("#")
                ):
                    continue

                if line_stripped.startswith("["):
                    if (
                        line_stripped.startswith("[dependencies]")
                        or line_stripped.endswith(".dependencies]")
                    ):
                        in_dependencies = True
                    else:
                        in_dependencies = False

                    continue

                if in_dependencies:
                    match = re.match(
                        r"^([\w\d_-]+)\s*=",
                        line_stripped
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
            match = re.match(
                r"^\s*(?:pub\s+)?(?:use|extern\s+crate)\s+"
                r"([\w\d_]+)(?:::\s*([\w\d_{},\s\*]+))?",
                line
            )

            if not match:
                continue

            crate_name = match.group(1)
            imported_items_str = match.group(2)

            # Ignorar módulos internos de Rust
            if crate_name in {
                "self",
                "super",
                "crate",
                "std",
            }:
                continue

            # Si existe Cargo.toml y hay dependencias declaradas,
            # solamente considerar dependencias externas.
            if (
                allowed_deps
                and crate_name not in allowed_deps
            ):
                continue

            sub_modules = set()

            if imported_items_str:
                clean_str = imported_items_str.strip()

                if (
                    clean_str.startswith("{")
                    and clean_str.endswith("}")
                ):
                    clean_str = clean_str[1:-1]

                    for item in clean_str.split(","):
                        item = (
                            item
                            .strip()
                            .split(" as ")[0]
                        )

                        if item:
                            sub_modules.add(item)

                elif clean_str:
                    sub_modules.add(
                        clean_str
                        .strip()
                        .split(" as ")[0]
                    )

            import_items.append({
                "name": crate_name,
                "raw": line.strip(),
                "sub_modules": sub_modules,
                "has_sub": bool(imported_items_str),
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

    def _find_cargo_registry_src(self, crate_name):
        cargo_home = os.environ.get(
            "CARGO_HOME",
            pathlib.Path.home() / ".cargo"
        )

        registry_src = (
            pathlib.Path(cargo_home)
            / "registry"
            / "src"
        )

        if not registry_src.exists():
            return None

        try:
            for index_dir in registry_src.iterdir():

                if not index_dir.is_dir():
                    continue

                for entry in index_dir.iterdir():

                    if entry.name.lower().startswith(
                        crate_name.lower() + "-"
                    ):
                        if entry.exists():
                            return entry

        except (PermissionError, OSError):
            pass

        return None

    def _find_target_crate_dir(self, crate_name):
        current_dir = pathlib.Path.cwd()

        while True:
            target_dir = current_dir / "target"

            if target_dir.exists():

                for profile in [
                    "debug",
                    "release",
                ]:
                    deps_dir = (
                        target_dir
                        / profile
                        / "deps"
                    )

                    if not deps_dir.exists():
                        continue

                    try:
                        for file in deps_dir.iterdir():
                            filename = file.name.lower()
                            crate = crate_name.lower()

                            if (
                                filename.startswith(
                                    f"lib{crate}-"
                                )
                                or filename.startswith(
                                    f"{crate}-"
                                )
                            ):
                                return file

                    except (PermissionError, OSError):
                        pass

            parent_dir = current_dir.parent

            if parent_dir == current_dir:
                break

            current_dir = parent_dir

        return None

    def _find_submodule_size(
        self,
        registry_path,
        sub_modules
    ):
        if not registry_path:
            return None

        accumulated_size = 0
        found_any = False

        registry_path = pathlib.Path(
            registry_path
        )

        for sub in sub_modules:
            candidate_path = (
                registry_path
                / "src"
                / sub
            )

            current_sub_size = None

            if candidate_path.exists():
                current_sub_size = self._get_path_size(
                    candidate_path
                )

            elif pathlib.Path(
                str(candidate_path) + ".rs"
            ).exists():
                current_sub_size = self._get_path_size(
                    str(candidate_path) + ".rs"
                )

            else:
                matched_file = None

                for file in registry_path.rglob("*"):
                    if not file.is_file():
                        continue

                    filename = file.name.lower()
                    sub_lower = sub.lower()

                    if (
                        filename == sub_lower + ".rs"
                        or filename.startswith(
                            sub_lower + "."
                        )
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
        crate_name = item["name"]

        registry_path = (
            self._find_cargo_registry_src(
                crate_name
            )
        )

        target_path = (
            self._find_target_crate_dir(
                crate_name
            )
        )

        reg_size = (
            self._get_path_size(registry_path)
            if registry_path
            else None
        )

        target_size = (
            self._get_path_size(target_path)
            if target_path
            else None
        )

        # El tamaño total del paquete será el binario
        # compilado si existe; de lo contrario, el registro.
        root_size = (
            target_size
            if target_size is not None
            else reg_size
        )

        sub_size = None

        if (
            registry_path
            and len(item["sub_modules"]) > 0
        ):
            sub_size = self._find_submodule_size(
                registry_path,
                item["sub_modules"]
            )

            # Fallback del parser original
            if sub_size is None and reg_size:
                sub_size = round(
                    reg_size
                    / max(
                        len(item["sub_modules"]) * 2,
                        5
                    )
                )

        elif reg_size is not None:
            sub_size = reg_size

        else:
            sub_size = root_size

        return {
            "name": crate_name,
            "raw": item["raw"],
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
            "type": (
                "submodule"
                if len(item["sub_modules"]) > 0
                else "package"
            ),
        }

    def run(self):
        cargo_file = self._find_cargo_toml()

        allowed_deps = (
            self._parse_cargo_dependencies(
                cargo_file
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
