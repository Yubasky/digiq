#!/usr/bin/env python3
"""
audit/check_i18n.py
Comprehensive i18n validator for DigiQ (AppLanguage in lib/services/app_language.dart).

Checks:
1. Parity between AppLang.id and AppLang.en keys (id == en).
2. No empty values or values equal to their keys.
3. Matching placeholders ({x}, $x, %s) between ID and EN.
4. All keys used across lib/ (via AppLanguage.t('...')) must exist in dictionary (FAIL if missing).
5. Unused keys reported as information.
6. Returns exit code 0 on success, != 0 on failure.
"""

import os
import re
import sys

def parse_app_language(file_path='lib/services/app_language.dart'):
    if not os.path.exists(file_path):
        print(f"ERROR: Cannot find {file_path}")
        sys.exit(1)

    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Match each dictionary entry block
    # 'key_name': {\n AppLang.id: '...', \n AppLang.en: '...' \n}
    pattern = re.compile(r"'([a-zA-Z0-9_]+)':\s*\{([^}]+)\}", re.DOTALL)
    matches = pattern.findall(content)

    if not matches:
        print("ERROR: Could not locate _localizedValues entries in app_language.dart")
        sys.exit(1)

    dict_entries = {}
    for key, block in matches:
        id_match = re.search(r"AppLang\.id:\s*(?:'([^']*)'|\"([^\"]*)\")", block)
        en_match = re.search(r"AppLang\.en:\s*(?:'([^']*)'|\"([^\"]*)\")", block)

        id_val = None
        if id_match:
            id_val = id_match.group(1) if id_match.group(1) is not None else id_match.group(2)

        en_val = None
        if en_match:
            en_val = en_match.group(1) if en_match.group(1) is not None else en_match.group(2)

        dict_entries[key] = {
            'id': id_val,
            'en': en_val,
        }

    return dict_entries

def find_used_keys(lib_dir='lib'):
    used_keys = set()
    pattern = re.compile(r"AppLanguage\.t\(\s*['\"]([a-zA-Z0-9_]+)['\"]\s*\)")

    for root, _, files in os.walk(lib_dir):
        for f in files:
            if f.endswith('.dart'):
                p = os.path.join(root, f)
                with open(p, 'r', encoding='utf-8', errors='ignore') as fp:
                    code = fp.read()
                    for m in pattern.findall(code):
                        used_keys.add((m, f))
    return used_keys

def extract_placeholders(s):
    if not s:
        return set()
    # Match {placeholder}, %s, %d, or $var
    curly = re.findall(r"\{[a-zA-Z0-9_]+\}", s)
    percent = re.findall(r"%[a-zA-Z0-9]", s)
    dollar = re.findall(r"\$[a-zA-Z0-9_]+", s)
    return set(curly + percent + dollar)

def main():
    print("=" * 70)
    print("                    DIGIQ i18n AUDIT CHECKER")
    print("=" * 70)

    entries = parse_app_language()
    total_keys = len(entries)
    print(f"Total keys defined in AppLanguage: {total_keys}")

    failures = []
    warnings = []

    # 1. Parity & value validations
    missing_id = []
    missing_en = []
    empty_values = []
    val_equals_key = []
    placeholder_mismatches = []

    for key, vals in entries.items():
        id_val = vals.get('id')
        en_val = vals.get('en')

        if id_val is None:
            missing_id.append(key)
        if en_val is None:
            missing_en.append(key)

        if id_val is not None and not id_val.strip():
            empty_values.append(f"{key} (id is empty)")
        if en_val is not None and not en_val.strip():
            empty_values.append(f"{key} (en is empty)")

        if id_val == key:
            val_equals_key.append(f"{key} (id value == key)")
        if en_val == key:
            val_equals_key.append(f"{key} (en value == key)")

        if id_val is not None and en_val is not None:
            ph_id = extract_placeholders(id_val)
            ph_en = extract_placeholders(en_val)
            if ph_id != ph_en:
                placeholder_mismatches.append(f"{key}: id has {ph_id} vs en has {ph_en}")

    if missing_id:
        failures.append(f"Missing AppLang.id in keys: {missing_id}")
    if missing_en:
        failures.append(f"Missing AppLang.en in keys: {missing_en}")
    if empty_values:
        failures.append(f"Empty translation values found in: {empty_values}")
    if val_equals_key:
        failures.append(f"Value equals key found in: {val_equals_key}")
    if placeholder_mismatches:
        failures.append(f"Placeholder mismatch between id and en: {placeholder_mismatches}")

    # 2. Used keys validation
    used_items = find_used_keys('lib')
    used_key_names = {k for k, _ in used_items}
    defined_key_names = set(entries.keys())

    missing_in_dict = []
    for k, filename in sorted(used_items):
        if k not in defined_key_names:
            missing_in_dict.append(f"{k} (used in {filename})")

    if missing_in_dict:
        failures.append(f"Keys used in lib/ but missing in AppLanguage dictionary: {missing_in_dict}")

    unused_keys = sorted(defined_key_names - used_key_names)
    print(f"Total keys used in code: {len(used_key_names)}")
    print(f"Total unused dictionary keys (informational): {len(unused_keys)}")

    print("-" * 70)
    if warnings:
        print("WARNINGS:")
        for w in warnings:
            print(f"  [WARN] {w}")

    if failures:
        print("FAILURES DETECTED:")
        for f in failures:
            print(f"  [FAIL] {f}")
        print("=" * 70)
        sys.exit(1)

    print("PASS: 100% i18n parity, zero empty values, zero missing keys!")
    print("=" * 70)
    sys.exit(0)

if __name__ == '__main__':
    main()
