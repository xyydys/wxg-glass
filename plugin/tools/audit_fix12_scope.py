#!/usr/bin/env python3
"""Bound the watchdog fix to input repair; this is not a UIKit runtime test."""
from pathlib import Path
import argparse,hashlib,json,re

p=argparse.ArgumentParser();p.add_argument('--baseline',required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[1];src=root/'Sources';old=Path(a.baseline)/'Sources'
def method(text,signature):
    found=list(re.finditer(re.escape(signature)+r'[^;\n]*\{',text));assert found,signature
    body=text[found[-1].start():];end=re.search(r'\n(?:[-+] \(|@end)',body)
    return body[:end.start()] if end else body.rstrip()

mutable={'WXGHost.m','WXGInput.m','WXGNative.m','WXGSettings.m'}
unchanged={}
for path in sorted(old.iterdir()):
    if not path.is_file() or path.name in mutable:continue
    assert (src/path.name).read_bytes()==path.read_bytes(),path.name
    unchanged[path.name]=hashlib.sha256(path.read_bytes()).hexdigest()
assert {x.name for x in src.iterdir()}-{x.name for x in old.iterdir()}=={'WXGInputRepairPolicy.h'}
settings=(src/'WXGSettings.m').read_text().replace('TEST4 FIX12','TEST4 FIX11')
assert settings==(old/'WXGSettings.m').read_text()

host=(src/'WXGHost.m').read_text();native=(src/'WXGNative.m').read_text();inp=(src/'WXGInput.m').read_text()
methods={}
for name,sigs in {
    'WXGHost.m':['- (void)dockChanged:','- (void)buildDock','- (void)buildNavigation',
                 '- (void)observeTransition:','- (void)finishNativeTransition:','- (void)homeGestureLaidOut:'],
    'WXGInput.m':['- (void)clearPaint','- (void)bindOptionalActions','- (BOOL)installInController:',
                  '- (void)setSuspended:','- (void)restore'],
    'WXGNative.m':['- (BOOL)centerNativeImage:','- (void)stripChrome:','- (void)clear:',
                   '- (void)clearImagePaint:','- (void)hide:'],
}.items():
    for sig in sigs:
        body=method((src/name).read_text(),sig)
        assert body==method((old/name).read_text(),sig),(name,sig)
        methods[name+': '+sig]=hashlib.sha256(body.encode()).hexdigest()

old_layout=method((old/'WXGInput.m').read_text(),'- (void)layout')
expected=old_layout.replace('        if(_panel.subviews.lastObject!=mic)[_panel bringSubviewToFront:mic];\n','')
expected=expected.replace('[_states conceal:_emojiButton];[_panel bringSubviewToFront:emoji];','[_states conceal:_emojiButton];')
expected=expected.replace('        }else [_states restoreView:_emojiButton];','        }else [_states restoreView:_emojiButton];\n        WXGSetInputForeground(_panel,mic,hasEmoji?emoji:nil);')
assert method(inp,'- (void)layout')==expected,'Only sibling ordering may change inside two-end layout'
assert 'if(WXGInputSuffixMatches(actual,available,desired,count))return;' in inp
assert 'if(!v.accessibilityElementsHidden)v.accessibilityElementsHidden=YES;' in native
assert 'if(_reapplying)return;_reapplying=YES;' in method(native,'- (void)reapply')
assert '@finally {_reapplying=NO;}' in method(native,'- (void)reapply')

for sig in ['- (void)refresh','- (void)tick:','- (void)layoutInput','- (void)flushInputRepair']:
    body=method(host,sig)
    assert '_inputRepairsSuspended' in body and 'UIApplicationStateActive' in body,sig
tick=method(host,'- (void)tick:');flush=method(host,'- (void)flushInputRepair')
assert tick.index('WXGInputRepairNextFrame')<tick.index('[self flushInputRepair]')<tick.index('WXGBeginBackdropFrame')
assert host.count('WXGInputRepairNextFrame(')==1
assert flush.index('WXGInputRepairTryBegin')<flush.index('[_departingInput reapplyPaint]')
assert '@finally' in flush and 'WXGInputRepairEnd' in flush
assert 'dispatch_async' not in flush and 'while(' not in flush and 'while (' not in flush
assert 'inputRepair' in method(host,'- (NSDictionary *)runtimeMetrics')
assert '[_inputAdapter installInController:r.leaf window:w];[self layoutInput];' in host

report={'release':'0.4.12-test4fix12','baseline':'FIX11','unchangedSourceFiles':unchanged,
        'unchangedMethods':methods,'twoEndLayoutDelta':'final foreground sibling order only',
        'samplerShaderMotionThreeEndUnchanged':True,'repairBudgetPerDisplayCallback':4,
        'pendingDrainBeforeCapture':True,'inactiveRepairStopped':True,
        'deviceTested':False,'watchdogReproducedInUIKit':False}
(root/'Validation/fix12_scope.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
print(f'PASS: {len(unchanged)} source files and {len(methods)} methods unchanged; only foreground order in two-end layout; guarded/bounded input repair, lifecycle protection and pre-capture drain.')
