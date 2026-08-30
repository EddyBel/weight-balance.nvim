import sys
import importlib.util
import pathlib
import re
import json

code = sys.stdin.read()
lines = code.splitlines()

imports_map = {}
for line in lines:
    match_imp = re.match(r'^\s*import\s+([a-zA-Z0-9_\.]+)', line)
    match_from = re.match(r'^\s*from\s+([a-zA-Z0-9_\.]+)\s+import', line)

    mod_path = None
    if match_imp:
        mod_path = match_imp.group(1)
    elif match_from:
        mod_path = match_from.group(1)

    if mod_path:
        # Omitir módulos que comiencen con punto (importaciones relativas locales del proyecto)
        if mod_path.startswith('.'):
            continue
        imports_map[mod_path] = line.strip()

stdlib = getattr(sys, 'stdlib_module_names', set())

def get_path_size(target_path):
    if not target_path or not target_path.exists():
        return None
    total_size = 0
    if target_path.is_file():
        total_size = target_path.stat().st_size
    elif target_path.is_dir():
        for f in target_path.rglob('*'):
            if f.is_file():
                total_size += f.stat().st_size
    return total_size

def resolve_spec_size(path_str):
    try:
        spec = importlib.util.find_spec(path_str)
    except (ModuleNotFoundError, ValueError, ImportError):
        return None

    if spec is None:
        return None

    origin = spec.origin
    sub_locs = spec.submodule_search_locations

    target_path = None
    if sub_locs:
        target_path = pathlib.Path(sub_locs[0])
    elif origin:
        target_path = pathlib.Path(origin)

    return get_path_size(target_path)

results = []
for mod_path, raw_line in imports_map.items():
    root_pkg = mod_path.split('.')[0]
    if root_pkg in stdlib:
        continue

    sub_size = resolve_spec_size(mod_path)

    root_size = None
    dep_type = "package"
    if '.' in mod_path:
        root_size = resolve_spec_size(root_pkg)
        dep_type = "submodule"
    else:
        root_size = sub_size

    results.append({
        "name": mod_path,
        "raw": raw_line,
        "size": sub_size if sub_size is not None else "not found",
        "root_size": root_size if root_size is not None else "not found",
        "type": dep_type
    })

print(json.dumps(results))

