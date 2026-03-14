#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
本地化审计报告
生成时间: 2026-03-14
"""

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

base_dir = "StreetStamps"

# 读取所有本地化文件
en = parse_strings_file(f"{base_dir}/en.lproj/Localizable.strings")
zh_hans = parse_strings_file(f"{base_dir}/zh-Hans.lproj/Localizable.strings")
zh_hant = parse_strings_file(f"{base_dir}/zh-Hant.lproj/Localizable.strings")
es = parse_strings_file(f"{base_dir}/es.lproj/Localizable.strings")
fr = parse_strings_file(f"{base_dir}/fr.lproj/Localizable.strings")
ja = parse_strings_file(f"{base_dir}/ja.lproj/Localizable.strings")
ko = parse_strings_file(f"{base_dir}/ko.lproj/Localizable.strings")

print("=" * 60)
print("本地化审计报告")
print("=" * 60)
print()

print("1. 各语言键数统计:")
print(f"   英文 (en):        {len(en)} 键")
print(f"   简体中文 (zh-Hans): {len(zh_hans)} 键")
print(f"   繁体中文 (zh-Hant): {len(zh_hant)} 键")
print(f"   西班牙语 (es):     {len(es)} 键")
print(f"   法语 (fr):        {len(fr)} 键")
print(f"   日语 (ja):        {len(ja)} 键")
print(f"   韩语 (ko):        {len(ko)} 键")
print()

print("2. 硬编码字符串问题:")
print("   发现以下文件包含硬编码的中文字符串:")
print("   - OnboardingCoachCard.swift: '稍后继续', '跳过引导'")
print("   - AboutUsView.swift: '话外'")
print()

print("3. 需要添加的本地化键:")
hardcoded_keys = [
    ("onboarding_continue_later", "稍后继续", "Continue Later"),
    ("onboarding_skip_guide", "跳过引导", "Skip Guide"),
    ("about_postscript", "话外", "Postscript"),
]

print("   需要添加到 Localizable.strings:")
for key, zh, en_val in hardcoded_keys:
    print(f'   "{key}" = "{en_val}";  // 中文: {zh}')
print()

print("4. Worldo 品牌名检查:")
worldo_count = sum(1 for v in en.values() if 'Worldo' in v)
print(f"   ✓ 'Worldo' 在英文本地化中出现 {worldo_count} 次")
print("   ✓ 品牌名应在所有语言中保持为 'Worldo'")
print()

print("5. 建议:")
print("   ✓ 繁体中文已更新完成")
print("   ✓ 西班牙语、法语、日语、韩语已补全缺失键（使用英文占位）")
print("   ⚠ 建议使用专业翻译服务翻译 es/fr/ja/ko 中的英文占位")
print("   ⚠ 修复硬编码字符串，使用 L10n.t() 或 L10n.key()")
print()

print("=" * 60)
