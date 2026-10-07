#!/usr/bin/env python3
"""pwsh 없이 쓰는 간이 구문 검사: 주석·문자열·here-string 을 건너뛰고 {} () [] 짝을 센다.
사용: python3 scripts-lint.py *.ps1   (진짜 검사는 현장 PC 의 Parser::ParseFile)"""
import sys

def check(src):
    stack, i, n, line = [], 0, len(src), 1
    pairs = {')': '(', ']': '[', '}': '{'}
    errs = []
    def skip_dq(i, line):          # 큰따옴표 문자열 (내부 $( ... ) 는 코드로 재귀)
        i += 1
        while i < n:
            c = src[i]
            if c == '`': i += 2; continue
            if c == '\n': line += 1
            if c == '"': return i + 1, line
            if c == '$' and i + 1 < n and src[i+1] == '(':
                i, line = code(i + 2, line, ')')
                continue
            i += 1
        errs.append(f'L{line}: 닫히지 않은 큰따옴표'); return i, line
    def code(i, line, closer=None):
        depth = 0
        while i < n:
            c = src[i]
            if c == '\n': line += 1; i += 1; continue
            if c == '#': 
                while i < n and src[i] != '\n': i += 1
                continue
            if c == '<' and src.startswith('<#', i):
                j = src.index('#>', i); line += src.count('\n', i, j); i = j + 2; continue
            if c == '@' and i + 1 < n and src[i+1] in '\'"' and src[i+2:i+3] in ('\n', '\r'):
                q = src[i+1]; end = src.index('\n' + q + '@', i); line += src.count('\n', i, end + 1); i = end + 3; continue
            if c == '`': i += 2; continue
            if c == "'":
                i += 1
                while i < n:
                    if src[i] == "'":
                        if i + 1 < n and src[i+1] == "'": i += 2; continue
                        break
                    if src[i] == '\n': line += 1
                    i += 1
                i += 1; continue
            if c == '"': i, line = skip_dq(i, line); continue
            if c in '{([': stack.append((c, line)); depth += 1
            elif c in '})]':
                if closer and c == closer and depth == 0: return i + 1, line
                if not stack or stack[-1][0] != pairs[c]: errs.append(f'L{line}: 짝이 맞지 않는 {c}')
                else: stack.pop(); depth -= 1
            i += 1
        return i, line
    code(0, 1)
    for c, l in stack: errs.append(f'L{l}: 닫히지 않은 {c}')
    return errs

bad = 0
for f in sys.argv[1:]:
    e = check(open(f, encoding='utf-8-sig').read())
    print(f'{f}: 오류 {len(e)}개 ' + ' / '.join(e)); bad += len(e)
sys.exit(1 if bad else 0)
