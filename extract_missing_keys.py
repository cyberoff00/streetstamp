#!/usr/bin/env python3
import re

def parse_strings_file(path):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    entries = {}
    pattern = r'^"([^"]+)"\s*=\s*"([^"]*(?:\\.[^"]*)*)";'
    for match in re.finditer(pattern, content, re.MULTILINE):
        key, value = match.groups()
        entries[key] = value
    return entries

base_dir = "StreetStamps"
en = parse_strings_file(f"{base_dir}/en.lproj/Localizable.strings")
es = parse_strings_file(f"{base_dir}/es.lproj/Localizable.strings")

# 找出缺失的键
missing_keys = set(en.keys()) - set(es.keys())

print(f"缺失的键数量: {len(missing_keys)}")
print("\n需要翻译的内容（英文 -> 目标语言）:\n")

# 输出前50个缺失的键供参考
for i, key in enumerate(sorted(missing_keys)[:50]):
    print(f'"{key}" = "{en[key]}";')

# 保存完整列表到文件
with open('missing_keys_to_translate.txt', 'w', encoding='utf-8') as f:
    f.write("# 以下是需要翻译的所有键（英文原文）\n")
    f.write("# 请将右侧的英文翻译成目标语言，保持格式不变\n")
    f.write("# 注意：Worldo 是品牌名，不要翻译\n\n")
    for key in sorted(missing_keys):
        f.write(f'"{key}" = "{en[key]}";\n')

print(f"\n完整列表已保存到 missing_keys_to_translate.txt")
