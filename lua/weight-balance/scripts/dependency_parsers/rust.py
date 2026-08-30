import sys
import os
import pathlib
import re
import json

code = sys.stdin.read()
lines = code.splitlines()

def find_cargo_toml():
    current_dir = pathlib.Path.cwd()
    while True:
        cargo_path = current_dir / 'Cargo.toml'
        if cargo_path.exists() and cargo_path.is_file():
            return cargo_path
        parent_dir = current_dir.parent
        if parent_dir == current_dir:
            break
        current_dir = parent_dir
    return None

def parse_cargo_dependencies(cargo_path):
    external_deps = set()
    if not cargo_path:
        return external_deps

    try:
        content = cargo_path.read_text(encoding='utf-8')
        in_dependencies = False
        for line in content.splitlines():
            line_stripped = line.strip()
            if not line_stripped or line_stripped.startswith('#'):
                continue
            if line_stripped.startswith('['):
                if line_stripped.startswith('[dependencies]') or line_stripped.endswith('.dependencies]'):
                    in_dependencies = True
                else:
                    in_dependencies = False
                continue

            if in_dependencies:
                match = re.match(r'^([\w\d_-]+)\s*=', line_stripped)
                if match:
                    external_deps.add(match.group(1))
    except Exception:
        pass
    return external_deps

cargo_file = find_cargo_toml()
allowed_deps = parse_cargo_dependencies(cargo_file)

import_items = []

for line in lines:
    match = re.match(r'^\s*(?:pub\s+)?(?:use|extern\s+crate)\s+([\w\d_]+)(?:::\s*([\w\d_{},\s\*]+))?', line)
    if match:
        crate_name = match.group(1)
        imported_items_str = match.group(2)

        if crate_name in {'self', 'super', 'crate'} or crate_name == 'std':
            continue

        if allowed_deps and crate_name not in allowed_deps:
            continue

        sub_modules = set()
        if imported_items_str:
            clean_str = imported_items_str.strip()
            if clean_str.startswith('{') and clean_str.endswith('}'):
                clean_str = clean_str[1:-1]
                for s in clean_str.split(','):
                    item = s.strip().split(' as ')[0]
                    if item:
                        sub_modules.add(item)
            elif clean_str:
                sub_modules.add(clean_str.strip().split(' as ')[0])

        import_items.append({
            'name': crate_name,
            'raw': line.strip(),
            'sub_modules': sub_modules,
            'has_sub': bool(imported_items_str)
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

def find_cargo_registry_src(crate_name):
    cargo_home = os.environ.get('CARGO_HOME', pathlib.Path.home() / '.cargo')
    registry_src = pathlib.Path(cargo_home) / 'registry' / 'src'
    if not registry_src.exists():
        return None

    try:
        for idx_dir in registry_src.iterdir():
            if not idx_dir.is_dir():
                continue
            for entry in idx_dir.iterdir():
                if entry.name.lower().startswith(crate_name.lower() + '-'):
                    if entry.exists():
                        return entry
    except (PermissionError, OSError):
        pass
    return None

def find_target_crate_dir(crate_name):
    current_dir = pathlib.Path.cwd()
    while True:
        target_dir = current_dir / 'target'
        if target_dir.exists():
            for profile in ['debug', 'release']:
                deps_dir = target_dir / profile / 'deps'
                if deps_dir.exists():
                    try:
                        for file in deps_dir.iterdir():
                            fname = file.name.lower()
                            if fname.startswith(f"lib{crate_name.lower()}-") or fname.startswith(f"{crate_name.lower()}-"):
                                return file
                    except (PermissionError, OSError):
                        pass
        parent_dir = current_dir.parent
        if parent_dir == current_dir:
            break
        current_dir = parent_dir
    return None

results = []

for item in import_items:
    crate_name = item['name']
    registry_path = find_cargo_registry_src(crate_name)
    target_path = find_target_crate_dir(crate_name)

    reg_size = get_path_size(registry_path) if registry_path else None
    target_size = get_path_size(target_path) if target_path else None

    # El tamaño total (root_size) debe ser el binario compilado si existe, o el registro
    root_size = target_size if target_size is not None else reg_size

    # El tamaño del submódulo (sub_size) debe calcularse en base a los archivos específicos importados
    sub_size = None
    if registry_path and len(item['sub_modules']) > 0:
        accumulated_sub_size = 0
        found_any = False

        for sub in item['sub_modules']:
            reg_p = pathlib.Path(registry_path)
            candidate_path = reg_p / 'src' / sub
            current_sub_size = None

            if candidate_path.exists():
                current_sub_size = get_path_size(candidate_path)
            elif pathlib.Path(str(candidate_path) + '.rs').exists():
                current_sub_size = get_path_size(str(candidate_path) + '.rs')
            else:
                matched_file = None
                for f in reg_p.rglob('*'):
                    if f.is_file():
                        fname_lower = f.name.lower()
                        sub_lower = sub.lower()
                        if fname_lower == sub_lower + '.rs' or fname_lower.startswith(sub_lower + '.'):
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
            sub_size = round(reg_size / max(len(item['sub_modules']) * 2, 5)) if reg_size else None
    elif reg_size is not None:
        sub_size = reg_size
    else:
        sub_size = root_size

    results.append({
        "name": crate_name,
        "raw": item['raw'],
        "size": sub_size if sub_size is not None else "not found",
        "root_size": root_size if root_size is not None else "not found",
        "type": "submodule" if len(item['sub_modules']) > 0 else "package"
    })

print(json.dumps(results))
