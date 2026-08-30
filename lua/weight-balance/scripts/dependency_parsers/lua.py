import sys
import os
import pathlib
import re
import json

code = sys.stdin.read()
lines = code.splitlines()

def find_rockspec():
    current_dir = pathlib.Path.cwd()
    while True:
        for f in current_dir.glob('*.rockspec'):
            if f.is_file():
                return f
        parent_dir = current_dir.parent
        if parent_dir == current_dir:
            break
        current_dir = parent_dir
    return None

def parse_rockspec_dependencies(rockspec_path):
    external_deps = set()
    if not rockspec_path:
        return external_deps
    try:
        content = rockspec_path.read_text(encoding='utf-8')
        in_deps = False
        for line in content.splitlines():
            if 'dependencies' in line and '=' in line:
                in_deps = True
                continue
            if in_deps:
                if '}' in line:
                    in_deps = False
                match = re.search(r'["\']([\w\d_-]+)["\']', line)
                if match:
                    external_deps.add(match.group(1))
    except Exception:
        pass
    return external_deps

rockspec_file = find_rockspec()
allowed_deps = parse_rockspec_dependencies(rockspec_file)

import_items = []

for line in lines:
    matches = re.findall(r'require\s*\(?\s*["\']([\w\d_.-]+)["\']\s*\)?', line)
    for mod_name in matches:
        base_name = mod_name.split('.')[0]

        if base_name in {'coroutine', 'table', 'io', 'os', 'string', 'utf8', 'math', 'debug', 'vim'}:
            continue

        if allowed_deps and base_name not in allowed_deps:
            continue

        sub_modules = set(mod_name.split('.')[1:]) if '.' in mod_name else set()

        import_items.append({
            'name': base_name,
            'raw': line.strip(),
            'sub_modules': sub_modules,
            'has_sub': bool(sub_modules)
        })

def get_path_size(target_path):
    p = pathlib.Path(target_path)
    if not p.exists():
        return None
    total_size = 0
    try:
        if p.is_file():
            return p.stat().st_size
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

def find_luarocks_package(pkg_name):
    luarocks_home = os.environ.get('LUAROCKS_HOME', pathlib.Path.home() / '.luarocks')
    search_dirs = [
        pathlib.Path(luarocks_home) / 'share' / 'lua',
        pathlib.Path('/usr/local/share/lua'),
        pathlib.Path('/usr/share/lua'),
    ]
    for base_dir in search_dirs:
        if base_dir.exists():
            for ver_dir in base_dir.iterdir():
                if ver_dir.is_dir():
                    pkg_path = ver_dir / pkg_name
                    if pkg_path.exists():
                        return pkg_path
                    lua_file = pathlib.Path(str(pkg_path) + '.lua')
                    if lua_file.exists():
                        return lua_file
    return None

results = []

for item in import_items:
    pkg_name = item['name']
    pkg_path = find_luarocks_package(pkg_name)

    root_size = get_path_size(pkg_path) if pkg_path else None
    sub_size = None

    if pkg_path and len(item['sub_modules']) > 0:
        accumulated_sub_size = 0
        found_any = False
        p_obj = pathlib.Path(pkg_path)

        for sub in item['sub_modules']:
            candidate_path = p_obj / sub
            current_sub_size = None

            if candidate_path.exists():
                current_sub_size = get_path_size(candidate_path)
            elif pathlib.Path(str(candidate_path) + '.lua').exists():
                current_sub_size = get_path_size(str(candidate_path) + '.lua')
            else:
                matched_file = None
                if p_obj.is_dir():
                    for f in p_obj.rglob('*'):
                        if f.is_file():
                            if f.name.lower() == sub.lower() + '.lua':
                                matched_file = f
                                break
                if matched_file:
                    current_sub_size = get_path_size(matched_file)

            if current_sub_size is not None:
                accumulated_sub_size += current_sub_size
                found_any = True

        if found_any:
            sub_size = accumulated_sub_size
        else:
            sub_size = round(root_size / max(len(item['sub_modules']) * 2, 5)) if root_size else None
    elif root_size is not None:
        sub_size = root_size
    else:
        sub_size = "not found"

    results.append({
        "name": pkg_name,
        "raw": item['raw'],
        "size": sub_size,
        "root_size": root_size if root_size is not None else "not found",
        "type": "submodule" if len(item['sub_modules']) > 0 else "package"
    })

print(json.dumps(results))
