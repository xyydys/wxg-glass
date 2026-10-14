#!/usr/bin/env python3
"""Preserve FIX6's validated optics, layout, native actions and departure math."""
import argparse, hashlib, json, re
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--baseline',required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[1];src=root/'Sources';old=Path(a.baseline)/'Sources'
allowed={'WXGIntegration.h','WXGNative.m','WXGInput.m','WXGNativeInput.m','WXGHost.m',
         'WXGBackdrop.m','WXGRenderPolicy.h','WXGInputWidthPolicy.h','WXGSettings.m'}
same={};changed={}
for f in sorted(old.iterdir()):
    if not f.is_file():continue
    before=f.read_bytes();after=(src/f.name).read_bytes()
    if before==after:same[f.name]=hashlib.sha256(after).hexdigest()
    else:
        assert f.name in allowed,f.name
        changed[f.name]={'before':hashlib.sha256(before).hexdigest(),'after':hashlib.sha256(after).hexdigest()}
added={f.name for f in src.iterdir() if f.is_file()}-{f.name for f in old.iterdir() if f.is_file()}
assert added=={'WXGInputSettledGeometry.h'},added
preserved={'WXGConfig.m','WXGOptics.h','WXGLensOptics.h','WXGGlass.metal','WXGShaderSource.h',
           'WXGOpticalSettings.m','WXGGlassView.m','WXGDemoBar.m','WXGGeometry.h',
           'WXGSurface.m','WXGPresentationMath.h','WXGCompactInputGeometry.h','WXGNativeIcons.m',
           'WXGInputPolicy.h','WXGDecorations.m','WXGMotion.h','WXGElasticMotion.h'}
assert preserved<=same.keys(),preserved-same.keys()
def method(text,signature):
    found=list(re.finditer(re.escape(signature)+r'[^;\n]*\{',text));assert found,signature
    rest=text[found[-1].start():];end=re.search(r'\n(?:[-+] \(|@end)',rest)
    return rest[:end.start()] if end else rest.rstrip()
exact={}
for name,signatures in {
    'WXGHost.m':['- (void)observeTransition:','- (void)finishNativeTransition:',
        '- (void)buildDock','- (void)dockChanged:','- (NSArray<UIControl *> *)navigationControls',
        '- (NSString *)backCount:','- (NSString *)fullTitleFromView:','- (void)presentSettings'],
    'WXGInput.m':['- (void)clearPaint','- (void)bindOptionalActions'],
    'WXGNativeInput.m':['- (void)clearPaint','- (void)bindOptionalActions'],
}.items():
    for signature in signatures:
        body=method((src/name).read_text(),signature)
        assert body==method((old/name).read_text(),signature),(name,signature)
        exact[name+': '+signature]=hashlib.sha256(body.encode()).hexdigest()
host=(src/'WXGHost.m').read_text();native=(src/'WXGNative.m').read_text();backdrop=(src/'WXGBackdrop.m').read_text()
# No navigation geometry changes: only record the resulting binding identity.
nav=method(host,'- (void)buildNavigation').replace('    _navigationBindingKey=[self currentNavigationBindingKey];\n','')
assert nav==method((old/'WXGHost.m').read_text(),'- (void)buildNavigation')
assert 'WXGBeginBackdropFrame' not in method(host,'- (void)primeNewSurfaces')
assert 'if(!interactive)WXGBeginBackdropFrame' in method(host,'- (void)tick:')
assert 'WXGBackdropCaptureInProgress()' in method(host,'- (void)refresh')
assert 'WXGBackdropCaptureInProgress()' in method(host,'- (void)layoutInput')
assert 'WXGBeginNativeInputLayout();' in host and '@finally {WXGEndNativeInputLayout();}' in host
assert 'if(!WXGNativeInputLayoutInProgress())' in host
assert 'navigationBindingPending=YES' in method(host,'- (void)navigationControlLaidOut:')
assert 'WXGPreparingCapture=NO' in backdrop and '--WXGCaptureDepth' in backdrop
assert backdrop.index('[source layoutIfNeeded]')<backdrop.index('++WXGCaptureDepth')
assert 'Class cls=NSClassFromString(@"MMGrowTextView")' in native and '@selector(setCenter:)' in native
for file in ['WXGInput.m','WXGNativeInput.m']:
    text=(src/file).read_text()
    assert 'WXGBackdropCaptureInProgress() || WXGNativeInputLayoutInProgress()' in text
    assert not re.search(r'\b_?editor\.(?:frame|bounds|transform|contentInset|textContainerInset)\s*=',text)
    assert 'layoutIfNeeded' not in re.sub(r'//[^\n]*','',method(text,'- (void)layout'))
for forbidden in ['class_replaceMethod(UIView.class,','class_replaceMethod(CALayer.class,',
                  'class_addMethod(UIView.class,','class_addMethod(CALayer.class,',
                  'interactivePopGestureRecognizer.enabled=','setDelegate:']:
    assert forbidden not in native+host,forbidden
report={'baseline':'0.4.6-test4fix6','release':'0.4.7-test4fix7','exactFileSHA256':same,
    'exactMethodSHA256':exact,'changedSourceSHA256':changed,'addedSource':sorted(added),
    'opticsAndLensUnchanged':True,'nativeDepartureMathUnchanged':True,'nativeActionsUnchanged':True,
    'deviceTested':False,'scope':'source preservation and regression guards; no UIKit/Metal or performance certification'}
(root/'Validation/fix7_scope.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(f'PASS: {len(same)} FIX6 source files and {len(exact)} critical methods exact; navigation geometry unchanged; scoped capture/input guards.')
