#!/usr/bin/env python3
"""Recount unified-diff hunk headers after hand edits.

  python3 tools/recount_patch.py FILE.patch [...]

Reads every `@@ -a,b +c,d @@` header and recomputes b/d from the body.  The
start lines and the section heading are preserved.  Existing counts must
already cover the body (i.e. only line *contents* changed), which is what our
TIFFANY edits do.
"""
import re, sys

HUNK = re.compile(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)$')

for path in sys.argv[1:]:
    lines = open(path, encoding='utf-8').read().splitlines(keepends=True)
    out, i = [], 0
    while i < len(lines):
        m = HUNK.match(lines[i].rstrip('\n'))
        if not m:
            out.append(lines[i]); i += 1; continue
        old_start, _, new_start, _, tail = m.groups()
        out.append(None)  # filled below
        hunk_index = len(out) - 1
        old_n = new_n = 0
        i += 1
        while i < len(lines) and not lines[i].startswith(('diff --git ', '@@ ')):
            if lines[i].rstrip('\n') == '-- ':
                # git format-patch signature: never part of the hunk
                break
            body = lines[i]
            out.append(body)
            if body.startswith('\\'):
                pass
            elif body.startswith('+'):
                new_n += 1
            elif body.startswith('-'):
                old_n += 1
            else:
                old_n += 1; new_n += 1
            i += 1
        out[hunk_index] = f'@@ -{old_start},{old_n} +{new_start},{new_n} @@{tail}\n'
    open(path, 'w', encoding='utf-8').writelines(out)
    print(f'recounted {path}')
