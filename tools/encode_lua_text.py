"""Escape non-ASCII Lua string literals for PZ's byte-oriented compiler.

The game reads Lua through a Unicode Reader but its lexer stores literal
characters as bytes. ASCII decimal escapes produce valid UTF-8 literals
regardless of the Reader encoding. Comments remain readable.
"""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def encode(source):
    parts=[];i=0
    while i<len(source):
        if source.startswith('--',i):
            end=source.find('\n',i)
            if end<0:end=len(source)
            parts.append(source[i:end]);i=end;continue
        if source[i] not in ('"',"'"):
            parts.append(source[i]);i+=1;continue
        quote=source[i];parts.append(quote);i+=1
        while i<len(source):
            c=source[i]
            if c=='\\':
                parts.append(source[i:i+2]);i+=2;continue
            if c==quote:
                parts.append(c);i+=1;break
            parts.append(''.join('\\%03d'%b for b in c.encode('utf-8')) if ord(c)>127 else c)
            i+=1
    return ''.join(parts)
if __name__=='__main__':
    for path in (ROOT/'KnoxNavigator/42/media/lua').rglob('*.lua'):
        original=path.read_text(encoding='utf-8')
        result=encode(original)
        if result!=original:
            path.write_text(result,encoding='utf-8');print('Encoded strings:',path.name)
