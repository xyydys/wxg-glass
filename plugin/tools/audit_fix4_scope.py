#!/usr/bin/env python3
"""Release boundary and regression guards; no claim of UIKit/device execution."""
import argparse, hashlib, json, re
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--baseline',required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[1];src=root/'Sources';old=Path(a.baseline)/'Sources'
allowed={'WXGIntegration.h','WXGNative.m','WXGBackdrop.m','WXGGlassView.m','WXGHost.m','WXGNativeInput.m','WXGSettings.m'}
same={};changed={}
for f in sorted(old.iterdir()):
    if not f.is_file():continue
    before=f.read_bytes();after=(src/f.name).read_bytes()
    if before==after:same[f.name]=hashlib.sha256(after).hexdigest()
    else:
        assert f.name in allowed, f.name
        changed[f.name]={'before':hashlib.sha256(before).hexdigest(),'after':hashlib.sha256(after).hexdigest()}
added={f.name for f in src.iterdir() if f.is_file()}-{f.name for f in old.iterdir() if f.is_file()}
assert added=={'WXGDecorations.m','WXGCompactInputGeometry.h'},added
assert {'WXGInput.m','WXGInputPolicy.h','WXGConfig.m','WXGGlass.metal','WXGShaderSource.h','WXGDemoBar.m','WXGSurface.m','WXGNativeIcons.m'}<=same.keys()
def method(text,signature):
    m=list(re.finditer(re.escape(signature)+r'[^;\n]*\{',text));assert m,signature
    rest=text[m[-1].start():];end=re.search(r'\n(?:[-+] \(|@end)',rest)
    return rest[:end.start()] if end else rest.rstrip()
host=(src/'WXGHost.m').read_text();native=(src/'WXGNative.m').read_text()
render=(src/'WXGGlassView.m').read_text();backdrop=(src/'WXGBackdrop.m').read_text()
triple=(src/'WXGNativeInput.m').read_text();decor=(src/'WXGDecorations.m').read_text()
assert 'return NO;' in method(render,'- (BOOL)directDemoCapture')
assert 'WXGRectInSource(glass,source)' in backdrop
assert 'begin+.93/WXGScreenCaptureFPS' in backdrop
assert 'if(cancelled || _route.leaf!=_transitionTo)[self resetRoute]' in method(host,'- (void)finishNativeTransition:')
assert 'if(!home && (bar.hidden || bar.alpha<.01)){[_navStates reapply];return;}' in method(host,'- (void)buildNavigation')
assert 'didMoveToSuperview' in host and 'navigationControlLaidOut:view' in host
assert '[_navStates reapply]' in method(host,'- (void)tick:')
assert 'surface.superview!=native.superview' in method(host,'- (void)followHomeSurfaces')
assert '[protected addObject:_dictation]' in triple
assert 'paint.animationImages.count' in triple and 'paint.layer.animationKeys.count' in triple
assert '[view isKindOfClass:UITextView.class]' in method(triple,'- (void)placeNative:')
assert 'image=nil' not in method(native,'- (void)clearImagePaint:')
for text in (triple,decor):
    for forbidden in ('sendActionsForControlEvents:','addGestureRecognizer:','removeGestureRecognizer:','resignFirstResponder','setText:'):
        assert forbidden not in text,forbidden
assert 'entry.surface.materialOnly=YES' in decor
assert 'body insertSubview:surface atIndex:0' in decor
assert 'clearImagePaint' in decor
assert 'MMMsgCommonTipsView' in decor and 'RightTopMenuItemBtn' in decor and 'MMMenuItemView' in decor
report={'baseline':'0.4.3-test4fix3','release':'0.4.4-test4fix4','exactFileSHA256':same,'changedSourceSHA256':changed,'addedSource':sorted(added),
 'twoSegmentAcceptedFixByteExact':True,'opticsLensAndDockGeometryPreserved':True,
 'intentionalChanges':['navigation temporary visibility/reparent/early suppression','shared dock capture budget and cross-window coordinates',
   'three-segment grow width/control origins and dictation static paint','native pinned/menu material attachments'],
 'deviceTested':False}
(root/'Validation/fix4_scope.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(f'PASS: {len(same)} FIX3 source files exact; accepted two-segment input unchanged; navigation/capture/menu/native-input scope guards passed.')
