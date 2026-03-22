#!/usr/bin/env python3
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
    lines = []
    for key in sorted(entries.keys()):
        value = entries[key].replace('"', '\\"')
        lines.append(f'"{key}" = "{value}";\n')

    with open(path, 'w', encoding='utf-8') as f:
        f.writelines(lines)

base_dir = "StreetStamps"
en = parse_strings_file(f"{base_dir}/en.lproj/Localizable.strings")

# 处理每种语言
languages = {
    'es': '西班牙语',
    'fr': '法语',
    'ja': '日语',
    'ko': '韩语'
}

for lang_code, lang_name in languages.items():
    existing = parse_strings_file(f"{base_dir}/{lang_code}.lproj/Localizable.strings")

    # 合并：保留现有翻译，新键使用英文占位
    merged = {}
    for key in en.keys():
        if key in existing:
            merged[key] = existing[key]
        else:
            merged[key] = f"[TODO] {en[key]}"  # 标记待翻译

    write_strings_file(f"{base_dir}/{lang_code}.lproj/Localizable.strings", merged)

    missing_count = sum(1 for v in merged.values() if v.startswith('[TODO]'))
    print(f"✓ {lang_name} ({lang_code}): {len(merged)} 个键, {missing_count} 个待翻译")

print("\n完成！所有语言文件已更新。")
print("标记为 [TODO] 的条目需要专业翻译。")
