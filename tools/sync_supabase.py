# Copyright (c) 2026 Eirini Konidari. All rights reserved.
"""Mirror db/ and edge/ into the supabase/ layout the Supabase GitHub integration deploys.

db/ and edge/ stay the source of truth (tests and tools read them). Run without
arguments to regenerate supabase/migrations and supabase/functions; run with --check
(CI) to fail when the mirror is stale.

db/005_content_editor_security_fix.sql is not mirrored: 009 creates the table it reads
and redefines public.can_edit_city identically, so 005 is superseded. test_sql.sql is
test data and is never deployed. Explicit begin/commit are stripped because the
Supabase CLI already runs each migration in its own transaction.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MIGRATIONS = [  # (version, source) in apply order; versions must never change once deployed
    ('20261124000001', '001_schema.sql'),
    ('20261124000002', '002_ingest.sql'),
    ('20261124000003', '003_release.sql'),
    ('20261124000004', '004_retention.sql'),
    ('20261124000006', '006_security_rls_and_scoping.sql'),
    ('20261124000007', '007_seed_vocab.sql'),
    ('20261124000008', '008_scoped_insights.sql'),
    ('20261124000009', '009_content_editor.sql'),
    ('20261124000010', '010_function_search_path.sql'),
]
FUNCTIONS = ['ingest', 'stats', 'editor']
TX = re.compile(r'^\s*(begin|commit)\s*;\s*$', re.I | re.M)


def expected() -> dict[Path, str]:
    out = {}
    for version, src in MIGRATIONS:
        name = src.split('_', 1)[1]
        body = TX.sub('', (ROOT / 'db' / src).read_text(encoding='utf-8'))
        out[ROOT / 'supabase' / 'migrations' / f'{version}_{name}'] = (
            f'-- GENERATED from db/{src} by tools/sync_supabase.py. Edit the source, not this file.\n' + body)
    for fn in FUNCTIONS:
        out[ROOT / 'supabase' / 'functions' / fn / 'index.ts'] = (
            (ROOT / 'edge' / fn / 'index.ts').read_text(encoding='utf-8'))
    return out


def managed() -> set[Path]:
    paths = set((ROOT / 'supabase' / 'migrations').glob('*.sql'))
    for fn in FUNCTIONS:
        paths |= set((ROOT / 'supabase' / 'functions' / fn).glob('*'))
    return paths


def main() -> int:
    want = expected()
    stray = managed() - set(want)
    if '--check' in sys.argv:
        bad = [p for p, t in want.items() if not p.exists() or p.read_text(encoding='utf-8') != t]
        bad += sorted(stray)
        for p in bad:
            print(f'stale: {p.relative_to(ROOT)}')
        if bad:
            print('Run: python3 tools/sync_supabase.py')
        return 1 if bad else 0
    for p in stray:
        p.unlink()
    for p, t in want.items():
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(t, encoding='utf-8', newline='\n')
    print(f'synced {len(want)} files')
    return 0


if __name__ == '__main__':
    sys.exit(main())
