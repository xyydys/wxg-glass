#!/usr/bin/env python3
"""FIX14 source boundaries; not a substitute for native transition/GPU tests."""
from pathlib import Path
import argparse, hashlib, json, re
p=argparse.ArgumentParser();p.add_argument('--baseline',required=True);args=p.parse_args()
root=Path(__file__).resolve().parents[1];src=root/'Sources';old=Path(args.baseline)/'Sources'
def method(text,signature):
    matches=list(re.finditer(re.escape(signature)+r'[^;\n]*\{',text));assert matches,signature
    body=text[matches[-1].start():];end=re.search(r'\n(?:[-+] \(|@end)',body)
    return body[:end.start()] if end else body.rstrip()
mutable={'WXGHost.m','WXGSettings.m','WXGOpticalSettings.m','WXGDemoBar.m','WXGLensOptics.h',
         'WXGGlass.metal','WXGShaderSource.h','WXGBackdrop.m','WXGBackdropSample.h','WXGBackdropROI.h','WXGGlassView.m'}
unchanged={}
for path in sorted(old.iterdir()):
    if not path.is_file() or path.name in mutable:continue
    assert (src/path.name).read_bytes()==path.read_bytes(),path.name
    unchanged[path.name]=hashlib.sha256(path.read_bytes()).hexdigest()
assert (src/'WXGSettings.m').read_text().replace('TEST4 FIX14','TEST4 FIX13')==(old/'WXGSettings.m').read_text()
assert (src/'WXGOpticalSettings.m').read_text()==(old/'WXGOpticalSettings.m').read_text().replace('WXGSlider(@"按压底色不透明度",@"pressedOpacity",0,.4),','')
methods={}
for name,signatures in {
    'WXGHost.m':['- (void)tick:','- (void)layoutInput','- (void)flushInputRepair','- (NSDictionary *)inputRepairMetrics',
                '- (void)buildNavigation','- (void)homeGestureLaidOut:','- (void)followHomeSurfaces',
                '- (void)prepareController:','- (void)nativeNavigationLaidOut','- (void)navigationChromeLaidOut:'],
    'WXGDemoBar.m':['- (void)tick:','- (void)layoutSubviews','- (void)rebuildIcons','- (void)selectIndex:',
                   '- (void)beginTrackingWithTouch:', '- (void)endTrackingWithTouch:'],
    'WXGGlassView.m':['- (void)drawMetalFrame','- (BOOL)encodeBlur:','- (BOOL)encodeBackdropCopy:','- (CGFloat)screenScale'],
}.items():
    for signature in signatures:
        # beginTracking returns BOOL, and remains part of the touch contract.
        if signature=='- (void)beginTrackingWithTouch:':signature='- (BOOL)beginTrackingWithTouch:'
        body=method((src/name).read_text(),signature)
        assert body==method((old/name).read_text(),signature),(name,signature)
        methods[name+': '+signature]=hashlib.sha256(body.encode()).hexdigest()
bar=(src/'WXGDemoBar.m').read_text()
assert method(bar,'- (void)updateGeometry').replace('*WXGRestingSelectionWeight(press)','')==method((old/'WXGDemoBar.m').read_text(),'- (void)updateGeometry')
host=(src/'WXGHost.m').read_text()
assert 'WXGDockPresentationAfterTransition(dockAvailable,_dockTransitionFromRoot,_dockTransitionToRoot,cancelled)' in host
presentation=method(host,'- (void)applyDockPresentation:')
assert '_dockView.userInteractionEnabled=presentation==WXGDockSettled' in presentation
assert '_dockView.glass.sourceView=_window.rootViewController.view' in presentation
assert '[_overlay addSubview:_dockView]' in presentation
assert '[_dockStates conceal:bar]' in method(host,'- (void)suppressNativeDockPaint')
dispatch=method(host,'- (void)dockChanged:');original=method((old/'WXGHost.m').read_text(),'- (void)dockChanged:')
assert dispatch[dispatch.index('    UITabBarController *tabs='):]==original[original.index('    UITabBarController *tabs='):]
assert '_dockPresentation!=WXGDockSettled' in dispatch
assert 'WXGProtectDockTouches(_dockView,nativeBar)' not in host
assert 'tabBarController.delegate=' not in host and 'interactivePopGestureRecognizer.delegate=' not in host
assert 'WXGRestingSelectionWeight(press)' in (src/'WXGGlass.metal').read_text()
report={'release':'0.4.14-test4fix14','baseline':'FIX13','unchangedSourceFiles':unchanged,'unchangedMethods':methods,
        'fix12InputProtectionPreserved':True,'lensGeometryAndMotionPreserved':True,
        'raisedSelectionTintWithdrawn':True,'nativeSelectionDispatchPreserved':True,
        'dockReturnPolicy':'foreground; no interaction until completion; cancellation restored',
        'deviceTested':False,'verifiedDeviceFPS':None}
(root/'Validation/fix14_scope.json').write_text(json.dumps(report,indent=2)+'\n')
print(f'PASS: {len(unchanged)} source files and {len(methods)} methods unchanged; input protection, native dispatch, geometry/motion, dock cancellation and selection isolation boundaries checked.')
