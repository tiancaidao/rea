"""Print CIL for each method of a .NET assembly with resolved strings and members.

Usage: python3 cil_dump.py Assembly.dll [TypeOrMethodFilter]
"""
import sys, dnfile
from dncil.cil.body import CilMethodBody
from dncil.cil.body.reader import CilMethodBodyReaderBase
from dncil.clr.token import Token, StringToken, InvalidToken
from dncil.cil.error import MethodBodyFormatError

class Reader(CilMethodBodyReaderBase):
    def __init__(self, pe, row):
        self.pe=pe; self.offset=pe.get_offset_from_rva(row.Rva)
    def read(self, n):
        d=self.pe.get_data(self.pe.get_rva_from_offset(self.offset), n); self.offset+=n; return d
    def tell(self): return self.offset
    def seek(self, o): self.offset=o; return o

def resolve(pe, tok):
    try:
        if isinstance(tok, StringToken):
            return repr(pe.net.user_strings.get(tok.rid).value)
        t=tok.table; r=tok.rid
        tbl={0x06:'MethodDef',0x0A:'MemberRef',0x04:'Field',0x01:'TypeRef',0x02:'TypeDef',0x2B:'MethodSpec',0x1B:'TypeSpec'}.get(t)
        if tbl is None: return str(tok)
        row=getattr(pe.net.mdtables,tbl).rows[r-1]
        if tbl=='MemberRef':
            p=row.Class.row
            pn=getattr(p,'TypeName',None) or getattr(p,'Name','?')
            ns=getattr(p,'TypeNamespace','')
            return f"{ns}.{pn}::{row.Name}"
        if tbl=='MethodSpec':
            m=row.Method.row; return f"{getattr(m,'Name','?')}<>"
        if tbl in('TypeRef','TypeDef'): return f"{row.TypeNamespace}.{row.TypeName}"
        if tbl=='TypeSpec': return 'typespec'
        return str(row.Name)
    except Exception as e:
        return f"{tok}"

pe=dnfile.dnPE(sys.argv[1])
filt=sys.argv[2] if len(sys.argv)>2 else ''
# map method -> type
owner={}
for td in pe.net.mdtables.TypeDef.rows:
    for m in td.MethodList: owner[m.row_index]=f"{td.TypeNamespace}.{td.TypeName}"
for i,row in enumerate(pe.net.mdtables.MethodDef.rows,1):
    name=f"{owner.get(i,'?')}::{row.Name}"
    if filt and filt not in name: continue
    if not row.ImplFlags.miIL or row.Flags.mdAbstract or not row.Rva: continue
    try: body=CilMethodBody(Reader(pe,row))
    except MethodBodyFormatError as e: print(name,'ERR',e); continue
    print(f"\n== {name}")
    for ins in body.instructions:
        op=ins.operand
        s = resolve(pe,op) if isinstance(op,(Token,StringToken)) else ('' if op is None else str(op))
        print(f"  {ins.offset:04x} {ins.opcode.name} {s}")
