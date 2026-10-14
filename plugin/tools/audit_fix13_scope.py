#!/usr/bin/env python3
"""Check release boundaries; this does not simulate UIKit or measure device FPS."""
from pathlib import Path
import argparse, hashlib, json, re

p = argparse.ArgumentParser()
p.add_argument('--baseline', required=True)
args = p.parse_args()
root = Path(__file__).resolve().parents[1]
src, old = root / 'Sources', Path(args.baseline) / 'Sources'

def method(text, signature):
    matches = list(re.finditer(re.escape(signature) + r'[^;\n]*\{', text))
    assert matches, signature
    body = text[matches[-1].start():]
    end = re.search(r'\n(?:[-+] \(|@end)', body)
    return body[:end.start()] if end else body.rstrip()

mutable = {'WXGHost.m', 'WXGDemoBar.m', 'WXGBackdrop.m', 'WXGBackdropSample.h', 'WXGGlassView.m', 'WXGSettings.m'}
unchanged = {}
for path in sorted(old.iterdir()):
    if not path.is_file() or path.name in mutable:
        continue
    assert (src / path.name).read_bytes() == path.read_bytes(), path.name
    unchanged[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
assert {x.name for x in src.iterdir()} - {x.name for x in old.iterdir()} == {
    'WXGDockInteraction.h', 'WXGDockInteraction.m', 'WXGDockTouchPolicy.h', 'WXGBackdropROI.h'}
assert (src / 'WXGSettings.m').read_text().replace('TEST4 FIX13', 'TEST4 FIX12') == (old / 'WXGSettings.m').read_text()

methods = {}
for name, signatures in {
    'WXGHost.m': ['- (void)schedule', '- (void)tick:', '- (void)layoutInput', '- (void)flushInputRepair',
                 '- (void)changed:', '- (NSDictionary *)inputRepairMetrics', '- (void)dockChanged:',
                 '- (void)buildNavigation', '- (void)observeTransition:', '- (void)finishNativeTransition:',
                 '- (void)homeGestureLaidOut:', '- (void)followHomeSurfaces', '- (void)suppressNativeDockPaint'],
    'WXGDemoBar.m': ['- (void)tick:', '- (void)updateGeometry', '- (void)layoutSubviews', '- (void)applyConfig',
                    '- (void)rebuildIcons', '- (void)syncSelectedIndex:', '- (void)selectIndex:',
                    '- (void)traitCollectionDidChange:', '- (UIView *)hitTest:'],
    'WXGGlassView.m': ['- (void)layoutSubviews', '- (void)drawMetalFrame', '- (BOOL)encodeBlur:',
                      '- (BOOL)encodeBackdropCopy:', '- (void)refreshBodyMask', '- (CGFloat)screenScale',
                      '- (BOOL)darkAppearance'],
}.items():
    for signature in signatures:
        body = method((src / name).read_text(), signature)
        assert body == method((old / name).read_text(), signature), (name, signature)
        methods[name + ': ' + signature] = hashlib.sha256(body.encode()).hexdigest()

host = (src / 'WXGHost.m').read_text()
hooks = host[host.index('static void WXGObserveNavigationPop(void)'):]
assert hooks.count('if(!WXGNavigationCallDepth)[WXGIntegrationHost.shared schedule]') == 3
assert 'if(!WXGNavigationCallDepth)[WXGIntegrationHost.shared refresh]' not in hooks
assert '[self refresh]' not in method(host, '- (void)prepareController:')
assert '[self refresh]' not in method(host, '- (void)controllerLaidOut:')
assert 'earlyBar==_route.nav.navigationBar' in method(host, '- (void)navigationChromeLaidOut:')
assert 'stripChrome:bar preserving:paintHosts' in method(host, '- (void)clearNavigationPaint')
assert 'WXGProtectDockTouches(_dockView,nativeBar)' in method(host, '- (void)buildDock')
assert host.count('WXGRestoreDockTouchDelegates(_suppressedTabBar)') == 3

backdrop = (src / 'WXGBackdrop.m').read_text()
assert 'CGContextClipToRects(ctx,clips,coverage.count)' in backdrop
assert 'sample.coverage=coverage;' in backdrop and 'good && epoch==WXGSceneEpoch' in backdrop
assert 'WXGROICovers(&published,consumer.footprint)' in backdrop
assert 'consumer.transform=WXGPresentedTransform(glass,source)' in backdrop
assert 'currentScale!=consumer.copyScale' in backdrop
assert 'WXGBackdropDue(frameTime,r.captured,fps,covered)' in backdrop
assert 'afterScreenUpdates:YES' not in backdrop
assert 'view.subviews.count==0' in backdrop  # Only leaf-layer fallback retained.
assert 'transitionPaused\":@NO' in backdrop
assert 'WXGBackdropForGlassCopy' in method((src / 'WXGGlassView.m').read_text(), '- (void)capture')

protection = (src / 'WXGDockInteraction.m').read_text()
assert 'recognizer.view==bar' in protection and 'dock.superview==bar' in protection
assert 'target==dock || [target isDescendantOfView:dock]' in protection
assert 'current!=proxy && current!=proxy.original' in protection
assert 'recognizer.delegate==proxy' in protection
assert 'recognizer.enabled=' not in protection
report = {'release': '0.4.13-test4fix13', 'baseline': 'FIX12',
          'unchangedSourceFiles': unchanged, 'unchangedMethods': methods,
          'preservesFix12InputRepair': True, 'preservesOpticsAndDockMotion': True,
          'fullGlassCanvasCoverageChecked': True, 'nativeGestureProtectionScoped': True,
          'deviceTested': False, 'measuredPerformanceImprovement': None}
(root / 'Validation/fix13_scope.json').write_text(json.dumps(report, indent=2) + '\n')
print(f'PASS: {len(unchanged)} source files and {len(methods)} methods unchanged; FIX12 input protection, TEST9 optics, dock motion and native selection dispatch preserved.')
