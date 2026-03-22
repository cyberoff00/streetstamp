#!/usr/bin/env python3
# -*- coding: utf-8 -*-
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

def write_strings_file(path, entries):
    with open(path, 'w', encoding='utf-8') as f:
        for key in sorted(entries.keys()):
            value = entries[key]
            f.write(f'"{key}" = "{value}";\n')

base_dir = "StreetStamps"

# 新增的键
new_keys = {
    "onboarding_continue_later": {
        "en": "Continue Later",
        "zh-Hans": "稍后继续",
        "zh-Hant": "稍後繼續",
        "es": "Continuar Más Tarde",
        "fr": "Continuer Plus Tard",
        "ja": "後で続ける",
        "ko": "나중에 계속"
    },
    "onboarding_skip_guide": {
        "en": "Skip Guide",
        "zh-Hans": "跳过引导",
        "zh-Hant": "跳過引導",
        "es": "Omitir Guía",
        "fr": "Ignorer le Guide",
        "ja": "ガイドをスキップ",
        "ko": "가이드 건너뛰기"
    },
    "about_postscript": {
        "en": "Postscript",
        "zh-Hans": "话外",
        "zh-Hant": "話外",
        "es": "Posdata",
        "fr": "Post-scriptum",
        "ja": "追記",
        "ko": "추신"
    }
}

# 更新所有语言
for lang in ["zh-Hant", "es", "fr", "ja", "ko"]:
    existing = parse_strings_file(f"{base_dir}/{lang}.lproj/Localizable.strings")

    # 添加新键
    for key, translations in new_keys.items():
        if key not in existing:
            existing[key] = translations[lang]

    write_strings_file(f"{base_dir}/{lang}.lproj/Localizable.strings", existing)
    print(f"✓ {lang}: 已添加 {len(new_keys)} 个新键")

print("\n✓ 所有语言文件已更新完成")
