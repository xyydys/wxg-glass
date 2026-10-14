#!/usr/bin/env python3
"""Recovery-release guards: source invariants, not device visual certification."""
import argparse,hashlib,json,re
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--baseline',required=True);args=p.parse_args()
root=Path(__file__).resolve().parents[1];src=root/'Sources';old=Path(args.baseline)/'Sources'
def method(text,signature):
 found=list(re.finditer(re.escape(signature)+r'[^;\n]*\{',text));assert found,signature
 body=text[found[-1].start():];end=re.search(r'\n(?:[-+] \(|@end)',body)
 return body[:end.start()] if end else body.rstrip()
protected=['WXGOptics.h','WXGLensOptics.h','WXGMotion.h','WXGElasticMotion.h','WXGDistanceField.h',
 'WXGGeometry.h','WXGCompactInputGeometry.h','WXGNativeInputGeometry.h','WXGInputSettledGeometry.h',
 'WXGInputWidthPolicy.h','WXGInputPolicy.h','WXGPresentationMath.h','WXGNativeIcons.h','WXGNativeIcons.m',
 'WXGDecorations.m']
exact={}
for name in protected:
 assert (src/name).read_bytes()==(old/name).read_bytes(),name
 exact[name]=hashlib.sha256((src/name).read_bytes()).hexdigest()
native_input=(src/'WXGNativeInput.m').read_text()
addition='''- (void)reapplyPaint {
    if(_installed && _tool.window)[_states reapply];
}
'''
assert native_input.replace(addition,'')==(old/'WXGNativeInput.m').read_text()
methods={}
for name,sigs in {
 'WXGHost.m':['- (void)dockChanged:','- (NSString *)backCount:','- (NSString *)fullTitleFromView:','- (BOOL)isBack:'],
 'WXGSurface.m':['- (void)rememberNativeReference','- (void)beginNativeDeparture','- (void)activateOriginal'],
 'WXGInput.m':['- (void)clearPaint','- (void)bindOptionalActions'],
}.items():
 for sig in sigs:
  body=method((src/name).read_text(),sig);assert body==method((old/name).read_text(),sig),(name,sig)
  methods[name+': '+sig]=hashlib.sha256(body.encode()).hexdigest()
backdrop=(src/'WXGBackdrop.m').read_text();host=(src/'WXGHost.m').read_text()
surface=(src/'WXGSurface.m').read_text();renderer=(src/'WXGGlassView.m').read_text();bar=(src/'WXGDemoBar.m').read_text()
# Native affine/alpha calculation exact; only the model writes receive an
# extra no-UIView-animation scope. No gesture or native animation is replaced.
follow=method(surface,'- (void)followNativePresentation')
original=method((old/'WXGSurface.m').read_text(),'- (void)followNativePresentation')
assert follow[:follow.index('    [UIView performWithoutAnimation:^{')]==original[:original.index('    [UIView performWithoutAnimation:^{')]
bind=method(surface,'- (void)bindMotionHost:')
assert bind.index('self.transform=CGAffineTransformIdentity;')<bind.index('self.restingFrame=self.frame;')
assert 'performWithoutAnimation' in bind
assert 'drawViewHierarchyInRect' not in backdrop and '[source layoutIfNeeded]' not in backdrop
assert '[source.layer renderInContext:' not in backdrop
assert 'WXGBackdropFrameHasSlot(frameTime,WXGLastAttemptFrame)' in backdrop
assert 'layer.hidden=YES' not in backdrop
assert 'budget.exceeded' in backdrop
assert 'if(!transitionBusy)WXGBeginBackdropFrame(glass,moving,link.timestamp)' in host
assert 'WXGBeginBackdropFrame' not in method(host,'- (void)primeNewSurfaces')
assert 'dockPageOverlay' not in host and 'afterScreenUpdates:' not in backdrop
assert 'tapElapsed' not in bar and 'WXGTabTap' not in bar
assert '[self sendActionsForControlEvents:UIControlEventValueChanged]' in method(bar,'- (void)endTrackingWithTouch:')
assert '_fingerDown?620:340,_fingerDown?39:29' in bar
assert 'CGRect bounds=surface?self.bounds:' in renderer
assert 'WXGSourceInverse(' in renderer
assert '(!_buttonPressEffect && _pressAmount>.005)' in renderer
assert '_glass.lensRect=CGRectZero' in method(surface,'- (void)tick:')
assert '_glass.buttonPressEffect=YES' in surface
for name in ['WXGInput.m','WXGNativeInput.m']:
 text=(src/name).read_text()
 assert not re.search(r'\b_?editor\.(?:frame|bounds|transform|contentInset|textContainerInset)\s*=',text)
 assert 'layoutIfNeeded' not in re.sub(r'//[^\n]*','',method(text,'- (void)layout'))
for forbidden in ['class_replaceMethod(UIView.class,','class_replaceMethod(CALayer.class,','interactivePopGestureRecognizer.enabled=','setDelegate:','removeAllAnimations']:
 assert forbidden not in host+(src/'WXGNative.m').read_text()+surface,forbidden
capture=backdrop[backdrop.index('static void WXGCaptureRegion('):backdrop.index('void WXGBeginBackdropFrame')]
assert '[source.layer renderInContext' not in capture
assert 'layer.hidden=' not in capture and 'layoutIfNeeded' not in capture
assert 'dispatch_async(WXGSnapshotQueue()' in capture and '[paint renderInContext:' in capture
assert 'WXGSnapshotBusy=YES' in capture and 'epoch==WXGSceneEpoch' in capture
assert 'MIN((NSUInteger)2,due.count)' in host and 'lastBackdropCopyTime' in host
assert '[self recordPaint:_route.tabs.tabBar bag:_dockStates hidden:YES]' not in host
assert '[_dockStates conceal:_route.tabs.tabBar]' in host
observe=method(host,'- (void)observeTransition:')
assert '_nativeDockReference=' not in observe
assert 'controller==host.transitionFrom];' not in host
assert '++WXGNavigationCallDepth' in host and '@finally {--WXGNavigationCallDepth;' in host
assert 'WXGSetBackdropTransitionPaused(transitionBusy)' in host
assert 'preservingColors:[NSStringFromClass(_route.leaf.class) hasPrefix:@"WCFinder"]' in host
report={'release':'0.4.10-test4fix10','baseline':'FIX9','unchangedFiles':exact,'unchangedNativeMethods':methods,
 'nativePresentationMathUnchanged':True,'threeSegmentUnchangedExceptPaintReapply':True,'detachedWorkerSnapshot':True,'synchronousHierarchySnapshotRemoved':True,
 'oneCPUReadbackPerDisplayCallback':True,'immediateNativeTabChoiceRestored':True,'deviceTested':False,
 'limitations':'Source invariants and numerical regressions only; not a UIKit, Metal pixel or FPS verification.'}
(root/'Validation/fix10_scope.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(f'PASS: {len(exact)} exact FIX9 files, {len(methods)} native action/title methods; native presentation math, bounded detached sampling, immediate tabs, stable three-segment layout and single-body press scope.')
