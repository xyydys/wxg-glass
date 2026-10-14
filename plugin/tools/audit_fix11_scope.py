#!/usr/bin/env python3
"""Source boundaries and ownership rules; not an on-device performance test."""
from pathlib import Path
import argparse,hashlib,json,re
p=argparse.ArgumentParser();p.add_argument('--baseline',required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[1];src=root/'Sources';old=Path(a.baseline)/'Sources'
def method(text,signature):
 found=list(re.finditer(re.escape(signature)+r'[^;\n]*\{',text));assert found,signature
 body=text[found[-1].start():];end=re.search(r'\n(?:[-+] \(|@end)',body)
 return body[:end.start()] if end else body.rstrip()
protected=['WXGOptics.h','WXGLensOptics.h','WXGMotion.h','WXGElasticMotion.h','WXGDistanceField.h',
 'WXGGeometry.h','WXGCompactInputGeometry.h','WXGNativeInputGeometry.h','WXGInputSettledGeometry.h',
 'WXGInputWidthPolicy.h','WXGInputPolicy.h','WXGPresentationMath.h','WXGNativeIcons.h','WXGNativeIcons.m',
 'WXGGlass.metal','WXGShaderSource.h','WXGDemoBar.m','WXGButtonPress.h','WXGConfig.m']
exact={}
for name in protected:
 assert (src/name).read_bytes()==(old/name).read_bytes(),name
 exact[name]=hashlib.sha256((src/name).read_bytes()).hexdigest()
for name,before,after in [('WXGInput.m','s.glass.sourceView=w.rootViewController.view;','s.glass.sourceView=vc.view;'),
 ('WXGNativeInput.m','surface.glass.sourceView=window.rootViewController.view;','surface.glass.sourceView=vc.view;')]:
 assert (src/name).read_text().replace(after,before)==(old/name).read_text(),name
methods={}
for name,sigs in {
 'WXGHost.m':['- (void)dockChanged:','- (NSString *)backCount:','- (NSString *)fullTitleFromView:','- (BOOL)isBack:'],
 'WXGSurface.m':['- (void)rememberNativeReference','- (void)beginNativeDeparture','- (void)activateOriginal'],
 'WXGInput.m':['- (void)clearPaint','- (void)bindOptionalActions','- (void)layout'],
 'WXGNativeInput.m':['- (void)layout'],
}.items():
 for sig in sigs:
  body=method((src/name).read_text(),sig);assert body==method((old/name).read_text(),sig),(name,sig)
  methods[name+': '+sig]=hashlib.sha256(body.encode()).hexdigest()
host=(src/'WXGHost.m').read_text();back=(src/'WXGBackdrop.m').read_text();glass=(src/'WXGGlassView.m').read_text()
native=(src/'WXGNative.m').read_text();surface=(src/'WXGSurface.m').read_text()
assert 'WXGSetBackdropTransitionPaused' not in host+back
assert 'WXGSnapshot' not in back and not (src/'WXGSnapshot.h').exists()
assert 'WXGBackdropDue(frameTime' in back and 'WXGSelectBackdrop' not in back
assert 'WXGCaptureCooldown' not in back
assert 'MIN((NSUInteger)2,due.count)' not in host
assert 'WXGBeginBackdropFrame(glass,moving,link.timestamp);' in method(host,'- (void)tick:')
assert 'updateDockExposure' not in host and 'WXGDockExposure' not in host
assert '[_dockStates conceal:_route.tabs.tabBar]' not in host
assert '[nativeBar addSubview:_dockView]' in host and '_dockView.glass.sourceView=_dockPrimaryOwner.view' in host
assert '_nativeDockReference' not in host
assert 'view.window &&' in native and 'WXGNativeIconKey' in native
assert 'UIImageView.class' in native and 'binding.state=state;' in native
assert 'inParent:host]' in method(host,'- (WXGSurface *)bindHomeGesture:')
assert '[NSStringFromClass(chrome.class) isEqual:@"FakeNavigationBar"]' in host
assert '[source.layer renderInContext:' not in back and '[source layoutIfNeeded]' not in back
assert not re.search(r'\.(hidden|alpha|mask|frame)\s*=',back), 'Sampler must not alter native hierarchy'
assert 'drawViewHierarchyInRect:shown.bounds afterScreenUpdates:NO' in back
assert 'BOOL divided=[split containsObject:view] || outside' in back
assert 'setWithObject:r.source' in back # root is always split, never root readback
assert 'owner.window.rootViewController.view' in back and 'r.source!=glass.sourceView.window.rootViewController.view' in back
assert 'WXGPresentedTransform(self,sample.coordinateView)' in glass
assert 'CGBitmapContextCreate' not in glass and 'UIImage *image=WXGBackdrop' not in glass
assert 'if(s.leases==0 && s!=r.sample)' in back and 'r.pool.count<3' in back
assert '[sample acquireLease];f.pendingSample=sample;' in glass
assert 'dispatch_async(dispatch_get_main_queue(),^{[sample releaseLease];});' in glass
assert 'addPresentedHandler:' in glass and 'presentedBackdropUpdates' in glass
assert 'CGRect bounds=surface?self.bounds:' in glass
for forbidden in ['class_replaceMethod(UIView.class,','class_replaceMethod(CALayer.class,','interactivePopGestureRecognizer.enabled=','removeAllAnimations']:
 assert forbidden not in host+native+surface,forbidden
report={'release':'0.4.11-test4fix11','baseline':'FIX10','unchangedFiles':exact,'unchangedMethods':methods,
 'inputChanges':'owning page sampling source only; both layout/action implementations unchanged',
 'rendering':'current visible scene clean-branch compositor -> shared Metal buffer -> GPU affine crop -> unchanged TEST9 Gaussian/optical shader',
 'temporalPausesRemoved':True,'rootRasterAndDetachedCloneRemoved':True,'nativeTabBarChild':True,
 'realPresentedFrameDiagnostics':True,'deviceTested':False,'metalRuntimeTested':False,
 'limits':'Source ownership/rules and numerical tests do not certify UIKit animation, video pixels, actual FPS or absence of low-device hangs.'}
(root/'Validation/fix11_scope.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(f'PASS: {len(exact)} exact FIX10 files, {len(methods)} action/title/input methods; page ownership, continuous sampling, GPU copy/leases, native tab child and real presentation diagnostics source checks.')
