from pathlib import Path
import struct,json
b=Path(__file__).resolve().parents[1].joinpath('recovered/ios-444.28.0/Payload/OneApp.app/OneApp').read_bytes();o=32;sections=[];symbols=None;indirect=None
for _ in range(struct.unpack_from('<I',b,16)[0]):
 cmd,size=struct.unpack_from('<II',b,o)
 if cmd==2:symoff,nsyms,stroff,strsize=struct.unpack_from('<IIII',b,o+8)
 if cmd==0xb:indoff,nind=struct.unpack_from('<II',b,o+56)
 if cmd==0x19:
  for j in range(struct.unpack_from('<I',b,o+64)[0]):
   p=o+72+j*80;name=b[p:p+16].split(b'\0')[0].decode();addr,sz=struct.unpack_from('<QQ',b,p+32);fo=struct.unpack_from('<I',b,p+48)[0];flags,res1,res2=struct.unpack_from('<III',b,p+64);sections.append((name,addr,sz,fo,flags,res1,res2))
 o+=size
wanted={b'_CFNetworkCopySystemProxySettings',b'_CFNetworkCopyProxiesForURL'};targets={}
for name,addr,sz,fo,flags,res1,res2 in sections:
 if flags&255!=8:continue
 for j in range(sz//res2):
  idx=struct.unpack_from('<I',b,indoff+4*(res1+j))[0]
  if idx>=nsyms:continue
  strx=struct.unpack_from('<I',b,symoff+16*idx)[0];start=stroff+strx;end=b.find(b'\0',start);symbol=b[start:end]
  if symbol in wanted:targets[addr+j*res2]=symbol.decode();print('STUB',hex(addr+j*res2),symbol.decode())
refs=[]
for name,addr,sz,fo,flags,res1,res2 in sections:
 if name!='__text':continue
 for i,w in enumerate(memoryview(b)[fo:fo+sz].cast('I')):
  if w&0xfc000000!=0x94000000:continue
  imm=w&0x3ffffff
  if imm&(1<<25):imm-=1<<26
  pc=addr+i*4;target=pc+(imm<<2)
  if target in targets:
   refs.append({'address':hex(pc),'symbol':targets[target]});print(hex(pc),targets[target])
Path(__file__).with_name('proxy-call-references.json').write_text(json.dumps(refs,indent=2))
