#!/usr/bin/env python3
"""Check the rollback boundary against an untouched TEST4 source directory.

This is a source preservation audit, not a UIKit/Metal/device test.
"""
import argparse
import hashlib
import json
import pathlib
import re

p = argparse.ArgumentParser()
p.add_argument('--baseline', required=True)
a = p.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
base = pathlib.Path(a.baseline)
src = root / 'Sources'
old = base / 'Sources'

def method(text, signature):
    matches = list(re.finditer(re.escape(signature) + r'[^;\n]*\{', text))
    assert matches, signature
    start = matches[-1].start()
    rest = text[start:]
    end = re.search(r'\n(?:[-+] \(|@end)', rest)
    return rest[:end.start()] if end else rest.rstrip()

unchanged = {}
for name in ['WXGConfig.m', 'WXGOpticalSettings.m', 'WXGGlass.metal',
             'WXGShaderSource.h', 'WXGOptics.h', 'WXGLensOptics.h',
             'WXGElasticMotion.h', 'WXGMotion.h', 'WXGDistanceField.h',
             'WXGGeometry.h', 'WXGIconAlignment.h', 'WXGRenderPolicy.h']:
    current = (src / name).read_bytes()
    assert current == (old / name).read_bytes(), name
    unchanged[name] = hashlib.sha256(current).hexdigest()

preserved_methods = {}
for name, signatures in {
    'WXGHost.m': ['- (void)buildDock',
                  '- (void)dockChanged:', '- (NSString *)backCount:',
                  '- (NSString *)titleForControl:'],
    'WXGSurface.m': ['- (void)layoutSubviews'],
    'WXGGlassView.m': ['- (void)layoutSubviews', '- (void)drawMetalFrame', '- (void)capture',
                      '- (BOOL)encodeBlur:'],
    'WXGDemoBar.m': ['- (void)layoutSubviews', '- (void)updateGeometry'],
}.items():
    before, after = (old / name).read_text(), (src / name).read_text()
    for signature in signatures:
        body = method(after, signature)
        assert body == method(before, signature), (name, signature)
        preserved_methods[name + ': ' + signature] = hashlib.sha256(body.encode()).hexdigest()

host, old_host = (src / 'WXGHost.m').read_text(), (old / 'WXGHost.m').read_text()
def chat_title(text):
    navigation = method(text, '- (void)buildNavigation')
    return navigation.split('    if(_route.chat) {', 1)[1].split('    if(_route.primary) {', 1)[0]
assert 'WXGCapsuleWidth([title sizeWithAttributes:' in chat_title(host)
current_input = (src / 'WXGInput.m').read_text()
# FIX3 deliberately replaces the two-segment editor sizing/action policy.
# The outer geometry file is still checked byte-for-byte above; editor state
# must remain native, and the narrower FIX2 diff is checked separately.
assert 'WXGInputContentHost(' in current_input
assert 'WXGInputRightAction(' in current_input
assert not re.search(r'\b_?editor\.(?:frame|bounds|transform|contentInset|textContainerInset)\s*=', current_input)
assert 'WXGPreferences.shared.nativeInputTest' in current_input
assert '_nativeInputTest=YES' not in (src / 'WXGNative.m').read_text()
experimental = (src / 'WXGNativeInput.m').read_text()
for name in ['editor', 'grow', 'panel', 'voiceButton', 'sendButton', 'emojiButton', 'attachment']:
    assert not re.search(r'_' + name + r'\.(?:frame|bounds|transform|contentInset|textContainerInset)\s*=', experimental)
assert 'sendActionsForControlEvents' not in experimental
assert 'WXGCompactInputLayout(' in experimental
assert '[view isKindOfClass:UITextView.class]' in method(experimental, '- (void)placeNative:')

renderer = (src / 'WXGGlassView.m').read_text()
assert 'presentsWithTransaction' not in renderer
assert 'nativeBar addSubview:_dockView' not in host
assert 'mountNavigationHost' not in host
assert '[_dockStates reapply]' in method(host, '- (void)tick:')
assert '_preserveDockDuringReset=' in method(host, '- (void)refresh')
assert 'showRightTopMenuBtn' in method(host, '- (NSArray<UIControl *> *)navigationControls')
assert 'bindHomeGesture:v' in method(host, '- (void)buildNavigation')
assert 'surface.motionHost=host' in method(host, '- (WXGSurface *)bindHomeGesture:')
assert 'conceal:s.original' in method(host, '- (void)buildNavigation')
assert '_overlay.hidden=YES' not in method(host, '- (void)presentSettings')
assert 'percentComplete' in method(host, '- (NSDictionary *)runtimeMetrics')
assert 'followNativePresentation' in method(host, '- (void)tick:')

report = {
    'baseline': 'original 0.4 TEST4',
    'release': '0.4.4-test4fix4',
    'exactFileSHA256': unchanged,
    'exactMethodSHA256': preserved_methods,
    'chatTitleWidthFormulaRetainedWithFullNativeSuffix': True,
    'outerInputGeometryFileExact': True,
    'twoSegmentActionAndHostWidthIntentionallyChangedInFIX3': True,
    'twoSegmentDoesNotAssignNativeEditorGeometry': True,
    'experimentalInputDoesNotAssignNativeEditorGeometryOrForwardActions': True,
    'threeSegmentHostWidthAndControlOriginsIntentionallyChangedInFIX4': True,
    'scope': 'source preservation and opt-in boundary only; no UIKit, GPU or device performance claim',
}
(root / 'Validation' / 'test4_rollback_preservation.json').write_text(
    json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(f'PASS: {len(unchanged)} TEST4 files and {len(preserved_methods)} layout/render/action methods byte-exact; title/two-segment geometry retained; native three-segment editor/actions retained.')
