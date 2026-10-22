"""Select expected product labels while keeping PTY behavioral checks shared."""
import json
import os
import re
from pathlib import Path

LANGUAGE = os.environ.get('TAWL_LANG', 'en')
if LANGUAGE not in ('en', 'tr'):
    raise ValueError('TAWL_LANG must be en or tr for interaction tests')
ROOT = Path(__file__).resolve().parents[2]
CATALOG = {}
for name in ('LocalizationsCLI.swift', 'LocalizationsCore.swift', 'LocalizationsTerminal.swift', 'LocalizationsUpdates.swift'):
    path = ROOT / 'Sources' / 'TawlCore' / name
    if not path.exists():
        continue
    for line in path.read_text().splitlines():
        match = re.match(r'\s*("(?:[^"\\]|\\.)*"):\s*("(?:[^"\\]|\\.)*"),?$', line)
        if match:
            CATALOG.setdefault(json.loads(match[1]), json.loads(match[2]))

def label(english):
    if LANGUAGE == 'en':
        return english
    if english not in CATALOG:
        raise KeyError(f'Missing Turkish test label: {english}')
    return CATALOG[english]
