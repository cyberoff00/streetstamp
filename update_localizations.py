#!/usr/bin/env python3
import re
import os

base_dir = "StreetStamps"

# 读取英文作为基准
def parse_strings_file(path):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    entries = {}
    pattern = r'^"([^"]+)"\s*=\s*"([^"]*(?:\\.[^"]*)*)";'
    for match in re.finditer(pattern, content, re.MULTILINE):
        key, value = match.groups()
        entries[key] = value
    return entries

en = parse_strings_file(f"{base_dir}/en.lproj/Localizable.strings")
zh_hans = parse_strings_file(f"{base_dir}/zh-Hans.lproj/Localizable.strings")

print(f"英文键数: {len(en)}")
print(f"简体中文键数: {len(zh_hans)}")

# 翻译映射 (基于英文->其他语言的机器翻译参考)
translations = {
    'es': {},  # 西班牙语
    'fr': {},  # 法语
    'ja': {},  # 日语
    'ko': {},  # 韩语
    'zh-Hant': {}  # 繁体中文
}

# 读取现有翻译
for lang in translations.keys():
    path = f"{base_dir}/{lang}.lproj/Localizable.strings"
    if os.path.exists(path):
        translations[lang] = parse_strings_file(path)

print("\n缺失的键数:")
for lang, trans in translations.items():
    missing = len(en) - len(trans)
    print(f"{lang}: {missing} 个缺失")
