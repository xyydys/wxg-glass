#!/usr/bin/env python3
"""-Werror,-Wunused-function guard: every file-scope static function or
variable in Sources/*.m must be referenced at least once besides its
definition. Exit 1 and list offenders otherwise."""
import re,glob,sys,os
root=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','Sources')
bad=[]
for f in sorted(glob.glob(os.path.join(root,'*.m'))):
    s=open(f,encoding='utf-8').read()
    for m in re.finditer(r'^static\s+(?:inline\s+)?[A-Za-z_][\w\s\*<>,]*?\b([A-Za-z_]\w*)\s*\([^;{]*\)\s*(?:CF_RETURNS_RETAINED\s*)?\{',s,re.M):
        if len(re.findall(r'\b'+re.escape(m.group(1))+r'\b',s))<2:bad.append((os.path.basename(f),m.group(1),'function'))
    for m in re.finditer(r'^static\s+(?!inline)[A-Za-z_][\w\s\*<>]*?\b([A-Za-z_]\w*)\s*(?:=[^;]*)?;',s,re.M):
        if len(re.findall(r'\b'+re.escape(m.group(1))+r'\b',s))<2:bad.append((os.path.basename(f),m.group(1),'variable'))
for b in bad:print('unused static %s: %s in %s'%(b[2],b[1],b[0]))
print('unused statics: %d'%len(bad));sys.exit(1 if bad else 0)
