#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import re
import os

def parse_strings_file(path):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    entries = {}
    pattern = r'^"([^"]+)"\s*=\s*"([^"]*(?:\\.[^"]*)*)";'
    for match in re.finditer(pattern, content, re.MULTILINE):
        key, value = match.groups()
        entries[key] = value
    return entries

def write_strings_file(path, entries):
    with open(path, 'w', encoding='utf-8') as f:
        for key in sorted(entries.keys()):
            value = entries[key]
            f.write(f'"{key}" = "{value}";\n')

base_dir = "StreetStamps"
en = parse_strings_file(f"{base_dir}/en.lproj/Localizable.strings")

# 对于缺失的翻译，暂时使用英文
# 这样至少应用不会崩溃，后续可以逐步完善翻译
languages = ['es', 'fr', 'ja', 'ko']

for lang in languages:
    existing = parse_strings_file(f"{base_dir}/{lang}.lproj/Localizable.strings")

    # 合并：保留现有翻译，新键使用英文
    merged = {}
    for key in en.keys():
        if key in existing:
            merged[key] = existing[key]
        else:
            merged[key] = en[key]  # 使用英文作为后备

    write_strings_file(f"{base_dir}/{lang}.lproj/Localizable.strings", merged)

    new_count = len(merged) - len(existing)
    print(f"✓ {lang}: {len(merged)} 键 (新增 {new_count} 个英文后备)")

print("\n✓ 所有语言文件已更新完成")
print("注意：新增的键暂时使用英文，建议后续使用专业翻译服务进行本地化")
