#!/usr/bin/env python3
"""CPU reference checks; this is not Apple's Metal compiler or a CA renderer."""
import json,os,re,subprocess,tempfile
from pathlib import Path
r=Path(__file__).resolve().parents[1]
def embedded(path,name):
 s=path.read_text();s=s[s.index(name+'[] =')+len(name+'[] ='):s.rindex(';')]
 return ''.join(json.loads(x) for x in s.strip().splitlines())
s=embedded(r/'Sources/WXGShaderSource.h','WXGMetalSource')
s+='\nnamespace original {\n'+embedded(r/'Sources/WXGOriginalShaderSource.h','WXGOriginalMetalSource')+'\n}\n'
s+=r'''
#include <cassert>
#include <cstdio>
#include <cstring>
#include <vector>
float wxgSimFwidth=0,wxgSimRecorded=0;int wxgSimRecording=0;
int main() {
 const int W=180,H=120;std::vector<float> glyph(W*H*4,0),page(W*H*4),empty(W*H*4,0);
 for(int y=0;y<H;y++)for(int x=0;x<W;x++) {
  int j=4*(y*W+x);page[j]=.2f+.5f*x/W;page[j+1]=.1f+.7f*y/H;page[j+2]=.4f;page[j+3]=1;
  bool icon=(x>=82&&x<=96&&y>=32&&y<=48&&(x<=85||y<=35||(y>=39&&y<=41)));
  bool text=(x>=69&&x<=110&&y>=77&&y<=86&&((x-69)%7<=1||y<=78));
  if(icon||text){glyph[j]=icon?.8f:.05f;glyph[j+1]=icon?.2f:.05f;glyph[j+2]=icon?.1f:.05f;glyph[j+3]=1;}
 }
 texture2d<float> bg{page.data(),W,H},icons{glyph.data(),W,H},none{empty.data(),W,H};
 WXGUniforms u={};u.viewport=float4(W,H,2,0);u.bar=float4(10,30,160,60);u.lens=float4(40,25,100,70);
 u.material=float4(1,1,.5,3);u.appearance=float4(0,1,0,1);u.optics=float4(1.16,0,.25,10);
 u.lensOptics=float4(26,2.4,18,0);u.motion=float4(1,0,1,90);u.extra.w=WXG_LENS_KYANT;
 u.extra2.w=1;u.extra2.z=1;u.sync=float4(2,.5,2,1);
 // Content is genuinely warped; no clean overlay can pass these comparisons.
 int moved[2]={},colored[2]={},transparent=0;
 for(int y=26;y<95;y++)for(int x=42;x<139;x++) {
  WXGOut in={};in.uv=float2((float)x/W,(float)y/H);
  u.lensOptics.x=0;u.lensOptics.y=0;float4 a=wxgFragment(in,u,bg,none,icons,bg,bg,bg);
  u.lensOptics.x=26;float4 b=wxgFragment(in,u,bg,none,icons,bg,bg,bg);
  u.lensOptics.y=2.4;float4 c=wxgFragment(in,u,bg,none,icons,bg,bg,bg);
  float delta=0,split=0;for(int j=0;j<4;j++){assert(std::isfinite(c[j]));delta+=fabs(a[j]-b[j]);split+=fabs(b[j]-c[j]);}
  int part=y<60?0:1;if(delta>1e-4)++moved[part];if(split>1e-4)++colored[part];
  float4 blank=wxgFragment(in,u,bg,none,none,bg,bg,bg);
  assert(blank.w==0);++transparent;
 }
 assert(moved[0]>0&&moved[1]>0&&colored[0]>0&&colored[1]>0);
 printf("R4 glyph refraction/spectrum: icon %d/%d, text %d/%d; %d empty overlay pixels fully transparent.\n",moved[0],colored[0],moved[1],colored[1],transparent);
 // The bar material contracts on press. Even next to its new edge, this
 // control must not move or cut the selected tab's icon or label.
 WXGUniforms open=u;
 open.optics.x=1.0694f;open.motion.x=1.056f;open.motion.w=84.f;
 open.optics.z=0;open.lensOptics.w=0;
 WXGUniforms pinched=open;
 pinched.optics.z=.2558f;pinched.lensOptics.w=4.f;
 auto draw=[&](int x,int y,const WXGUniforms &cfg,texture2d<float> atlas) {
  WXGOut in={};in.uv=float2((x+.5f)/W,(y+.5f)/H);
  return wxgFragment(in,cfg,bg,none,atlas,bg,bg,bg);
 };
 int visible[2]={},materialChanged=0;
 for(int y=26;y<95;y++)for(int x=42;x<139;x++) {
  float4 a=draw(x,y,open,icons),b=draw(x,y,pinched,icons);
  for(int j=0;j<4;j++)assert(fabs(a[j]-b[j])<1e-6f);
  if(b.w>.1f)++visible[y<60?0:1];
 }
 assert(visible[0]>0&&visible[1]>0);
 open.selectionColor=pinched.selectionColor=float4(.25,.25,.25,.5);
 open.extra2.w=pinched.extra2.w=2;
 for(int y=26;y<95;y++)for(int x=42;x<139;x++)
  if(fabs(draw(x,y,open,none).w-draw(x,y,pinched,none).w)>.01f)++materialChanged;
 assert(materialChanged>0);
 printf("R5 pinch isolation: %d icon and %d text pixels visible, identical RGBA; %d material pixels changed.\n",visible[0],visible[1],materialChanged);
 // A square probe in the nonrefracting center gives a direct measurement
 // of the original tab zoom and bar growth, through the actual fragment.
 std::vector<float> square(W*H*4,0);
 for(int y=53;y<67;y++)for(int x=83;x<97;x++)square[4*(y*W+x)+3]=1;
 texture2d<float> probe{square.data(),W,H};
 pinched.selectionColor=float4(0);pinched.motion.w=90.f;
 pinched.lensOptics.z=8.64f;
 for(float press:{0.f,.5f,1.f}) {
  pinched.material.x=press;
  int width=0,height=0;
  for(int i=-20;i<20;i++) {
   if(draw(90+i,60,pinched,probe).w>.5f)++width;
   if(draw(90,60+i,pinched,probe).w>.5f)++height;
  }
  assert(width==height);
  float expected=14.f*(1.f+press*(pinched.optics.x-1.f))*pinched.motion.x;
  assert(fabs(width-expected)<=1.f);
  printf("R5 central 14px square at press %.1f: %d x %d (expected %.2f).\n",press,width,height,expected);
 }
 // Lens-off and body paths must match the actual original FIX135 shader,
 // not a newly written approximation of it. Test all original backends.
 int parity=0;float worst=0;
 u.tintColor=float4(.8,.8,.8,.585);u.selectionColor=float4(.1,.1,.1,.07);
 u.extra=float4(0);u.lensOptics=float4(4,1,9,0);u.material=float4(.6,1,.5,3);
 for(float backend:{0.f,1.f,2.f})for(float surface:{0.f,1.f}) {
  u.sync.x=backend;u.appearance.w=surface;
  // A stray lens marker must never select the new body algorithm (there isn't one).
  u.extra.w=surface==0?WXG_LENS_KYANT:0;
  original::WXGUniforms v;std::memcpy(&v,&u,sizeof(v));v.extra.w=0;
  for(int y=32;y<88;y+=3)for(int x=16;x<164;x+=3) {
   WXGOut in={};in.uv=float2((float)x/W,(float)y/H);
   original::WXGOut oi;std::memcpy(&oi,&in,sizeof(oi));
   float4 a=wxgFragment(in,u,bg,icons,icons,bg,bg,bg);
   float4 b=original::wxgFragment(oi,v,bg,icons,icons,bg,bg,bg);
   for(int j=0;j<4;j++){assert(std::isfinite(a[j])&&std::isfinite(b[j]));float e=fabs(a[j]-b[j]);worst=fmax(worst,e);assert(e<1e-6f);}++parity;
  }
 }
 printf("R4 original shader parity: %d samples, max error %.9f (body and disabled lens, modes 0/1/2).\n",parity,worst);
 // Release and moving-lens geometry remain finite at center/medial axes.
 for(float pr:{0.f,.25f,.5f,1.f})for(float x:{20.f,40.f,60.f}) {
  u.extra.w=WXG_LENS_KYANT;u.appearance.w=1;u.sync.x=2;u.material.x=pr;
  u.lens=float4(x,25,100,70);u.lensOptics=float4(26*pr,2.4,18*pr,0);
  for(int y=25;y<=95;y+=5)for(int px=int(x);px<=x+100;px+=5) {
   WXGOut in={};in.uv=float2((float)px/W,(float)y/H);float4 c=wxgFragment(in,u,bg,none,icons,bg,bg,bg);
   for(int j=0;j<4;j++)assert(std::isfinite(c[j]));
  }
 }
 puts("R4 moving/releasing lens: 12 states finite, including medial axes.");
}
'''
s=re.sub(r'\b(float[234])\(',r'mk_\1(',s)
with tempfile.TemporaryDirectory() as td:
 p=Path(td)/'test.cpp';p.write_text(s);exe=Path(td)/'test'
 subprocess.run([os.environ.get('CXX','clang++'),'-std=c++14','-O2','-Wno-unknown-attributes','-I',str(r/'tools/shader_sim/stub'),str(p),'-o',str(exe)],check=True)
 subprocess.run([str(exe)],check=True)
