from pathlib import Path
import struct
b=Path(__file__).resolve().parents[1].joinpath('recovered/ios-444.28.0/Payload/OneApp.app/OneApp').read_bytes()
target=0x108bb7216
start=0x8000
words=memoryview(b)[start:start+0x8308660].cast('I')
for i,w in enumerate(words):
 if w & 0x9f000000 != 0x90000000:continue
 imm=((w>>5)&0x7ffff)*4+((w>>29)&3)
 if imm & (1<<20):imm-=1<<21
 pc=0x100000000+start+i*4
 page=(pc&~0xfff)+(imm<<12)
 if page != target&~0xfff:continue
 rd=w&31
 for j in range(i+1,min(i+9,len(words))):
  a=words[j]
  if a & 0xff000000 == 0x91000000 and (a>>5)&31==rd:
   off=(a>>10)&0xfff
   if a & (1<<22):off<<=12
   if abs(page+off-target)<64:print(hex(pc),hex(0x100000000+start+j*4),hex(page+off))
