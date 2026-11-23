#!/usr/bin/env python3
# Copyright (c) 2026 Eirini Konidari. All rights reserved.
"""Render TERMS_AND_PRIVACY.md into the <script id="legal"> JSON embedded in netherlanded-app.html.

Usage: python3 tools/sync_legal.py          # write
       python3 tools/sync_legal.py --check  # exit 1 if the app copy is out of date
Requires: pip install markdown
"""
import json
import os
import sys

import markdown

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PRE, POST = '<script id="legal" type="application/json">', '</script>'


def render():
    with open(os.path.join(ROOT, 'TERMS_AND_PRIVACY.md'), encoding='utf-8') as f:
        md = f.read()
    html = markdown.markdown(md, extensions=['tables'])
    return html.replace('<table>', '<div class="tbl"><table>').replace('</table>', '</table></div>')


def main():
    path = os.path.join(ROOT, 'netherlanded-app.html')
    with open(path, encoding='utf-8') as f:
        lines = f.read().split('\n')
    idx = [i for i, l in enumerate(lines) if l.startswith(PRE)]
    if len(idx) != 1:
        sys.exit('expected exactly one embedded legal JSON tag')
    obj = json.loads(lines[idx[0]][len(PRE):-len(POST)])
    fresh = render()
    if '--check' in sys.argv:
        ok = obj.get('html') == fresh
        print('legal text in sync' if ok else 'legal text OUT OF SYNC: run tools/sync_legal.py')
        sys.exit(0 if ok else 1)
    obj['html'] = fresh
    enc = json.dumps(obj, ensure_ascii=False, separators=(',', ':'))
    lines[idx[0]] = PRE + enc.replace('<', '\\u003c').replace('>', '\\u003e') + POST
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
    print('netherlanded-app.html legal text synced from TERMS_AND_PRIVACY.md')


if __name__ == '__main__':
    main()
