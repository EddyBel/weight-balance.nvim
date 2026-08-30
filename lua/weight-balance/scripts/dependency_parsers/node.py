import sys
import os
import pathlib
import re
import json

code = sys.stdin.read()
lines = code.splitlines()

imports_map = {}

for line in lines:
    match = re.match(r'^\s*import\s+(?:([\w\s{},*]+)\s+from\s+)?([\'"])([^\'"]+)\2', line)
    pkg_name = None
    imported_items_str = None
    is_default_import = False

    if match:
        imported_items_str = match.group(1)
        pkg_name = match.group(3)
        if imported_items_str:
            trimmed = imported_items_str.strip()
            if not trimmed.startswith('{') and not trimmed.startswith('*'):
                is_default_import = True
        else:
            is_default_import = True
    else:
        match = re.match(r'^\s*(?:const|let|var)?\s*(?:([\w\s{},*]+)\s*=\s*)?require\s*\(\s*([\'"])([^\'"]+)\2\s*\)', line)
        if match:
            imported_items_str = match.group(1)
            pkg_name = match.group(3)
            if imported_items_str:
                trimmed = imported_items_str.strip()
                if not trimmed.startswith('{'):
                    is_default_import = True
            else:
                is_default_import = True

    if pkg_name:
        if pkg_name.startswith('.') or pkg_name.startswith('/'):
            continue

        sub_modules = []
        if imported_items_str:
            clean_str = imported_items_str.strip()
            if clean_str.startswith('{') and clean_str.endswith('}'):
                clean_str = clean_str[1:-1]
                sub_modules = [s.strip().split(' as ')[0] for s in clean_str.split(',') if s.strip()]

        if pkg_name not in imports_map:
            imports_map[pkg_name] = {'raw': line.strip(), 'sub_modules': set(), 'is_default': is_default_import}

        if not is_default_import:
            imports_map[pkg_name]['is_default'] = False

        for sub in sub_modules:
            imports_map[pkg_name]['sub_modules'].add(sub)

def get_path_size(target_path):
    p = pathlib.Path(target_path)
    if not p.exists():
        return None
    total_size = 0
    try:
        if p.is_file():
            total_size = p.stat().st_size
        elif p.is_dir():
            for entry in p.rglob('*'):
                if entry.is_file():
                    try:
                        total_size += entry.stat().st_size
                    except (PermissionError, OSError):
                        pass
    except (PermissionError, OSError):
        pass
    return total_size

def resolve_pkg_path(pkg_str):
    current_dir = pathlib.Path.cwd()
    while True:
        node_modules = current_dir / 'node_modules'
        if node_modules.exists() and node_modules.is_dir():
            candidate = node_modules / pkg_str
            if candidate.exists():
                if candidate.is_file():
                    return str(candidate)
                pkg_json = candidate / 'package.json'
                if pkg_json.exists():
                    try:
                        with open(pkg_json, 'r', encoding='utf-8') as f:
                            data = json.load(f)
                            main = data.get('main', 'index.js')
                            main_path = candidate / main
                            if main_path.exists():
                                return str(main_path)
                    except Exception:
                        pass
                for ext in ['.js', '.json', '.node', '.ts', '.tsx']:
                    if (candidate.with_suffix(ext)).exists():
                        return str(candidate.with_suffix(ext))
                index_file = candidate / 'index.js'
                if index_file.exists():
                    return str(index_file)
                return str(candidate)
        parent_dir = current_dir.parent
        if parent_dir == current_dir:
            break
        current_dir = parent_dir
    return None

results = []

for pkg_name, data in imports_map.items():
    root_pkg = pkg_name
    parts = pkg_name.split('/')
    if pkg_name.startswith('@'):
        if len(parts) >= 2:
            root_pkg = '/'.join(parts[:2])
    else:
        if len(parts) >= 1:
            root_pkg = parts[0]

    resolved_sub_path = resolve_pkg_path(pkg_name)
    resolved_root_path = resolve_pkg_path(root_pkg)

    sub_size = None
    if resolved_sub_path:
        sub_size = get_path_size(resolved_sub_path)

    root_size = None
    if resolved_root_path:
        root_dir = pathlib.Path(resolved_root_path).parent
        while root_dir and root_dir.name != root_pkg and root_dir.parent != root_dir:
            if (root_dir / 'package.json').exists():
                break
            root_dir = root_dir.parent
        root_size = get_path_size(root_dir)

    if sub_size is None and root_size is not None and len(data['sub_modules']) > 0:
        accumulated_sub_size = 0
        found_any = False
        root_dir = pathlib.Path(resolved_root_path).parent if resolved_root_path else pathlib.Path.cwd()

        for sub in data['sub_modules']:
            candidate_path = root_dir / sub
            current_sub_size = None

            if candidate_path.exists():
                current_sub_size = get_path_size(candidate_path)
            else:
                for ext in ['.js', '.jsx', '.ts', '.tsx']:
                    ext_path = pathlib.Path(str(candidate_path) + ext)
                    if ext_path.exists():
                        current_sub_size = get_path_size(ext_path)
                        break

            if current_sub_size is not None:
                accumulated_sub_size += current_sub_size
                found_any = True

        if found_any:
            sub_size = accumulated_sub_size

    if sub_size is None:
        sub_size = root_size

    dep_type = "package"
    if pkg_name != root_pkg or len(data['sub_modules']) > 0:
        dep_type = "submodule"
    else:
        root_size = sub_size

    results.append({
        "name": pkg_name,
        "raw": data['raw'],
        "size": sub_size if sub_size is not None else "not found",
        "root_size": root_size if root_size is not None else "not found",
        "type": dep_type
    })

print(json.dumps(results))
