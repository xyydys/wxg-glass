#!/usr/bin/env python3
"""Bound this input hotfix to FIX2; not a device/visual acceptance test."""
import argparse
import hashlib
import json
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--baseline', required=True)
a = p.parse_args()
root = Path(__file__).resolve().parents[1]
old = Path(a.baseline) / 'Sources'
src = root / 'Sources'
allowed = {'WXGInput.m', 'WXGHost.m', 'WXGSettings.m'}
exact = {}
changed = {}
for f in sorted(old.iterdir()):
    if not f.is_file():
        continue
    before, after = f.read_bytes(), (src / f.name).read_bytes()
    if before == after:
        exact[f.name] = hashlib.sha256(after).hexdigest()
    else:
        assert f.name in allowed, f'unexpected source change: {f.name}'
        if f.name in {'WXGHost.m', 'WXGSettings.m'}:
            normalized = after.replace(b'TEST4_FIX3', b'TEST4_FIX2').replace(b'TEST4 FIX3', b'TEST4 FIX2')
            normalized = normalized.replace(b'0.4.3-test4fix3', b'0.4.2-test4fix2').replace(b'test4fix3', b'test4fix2')
            normalized = normalized.replace(b'0.4.3 TEST4', b'0.4.2 TEST4').replace(b'wxg-test4-fix3', b'wxg-test4-fix2')
            assert normalized == before, f'non-version change: {f.name}'
        changed[f.name] = {'before': hashlib.sha256(before).hexdigest(), 'after': hashlib.sha256(after).hexdigest()}
added = {f.name for f in src.iterdir() if f.is_file()} - {f.name for f in old.iterdir() if f.is_file()}
assert added == {'WXGInputPolicy.h'}, added
assert {'WXGNativeInput.m', 'WXGNativeInputGeometry.h', 'WXGGeometry.h'} <= exact.keys()
adapter = (src / 'WXGInput.m').read_text()
assert 'onInputModeChangeButtonClicked:' in adapter
assert 'WXGViews(_dictation,24)' in adapter
assert 'if(_usingNativeLayout){[_nativeAdapter layout];return;}' in adapter
assert 'holdingVoice?_recordButton:grow' in adapter
for forbidden in ['addGestureRecognizer:', 'removeGestureRecognizer:', 'resignFirstResponder',
                  'setText:', 'setAttributedText:', 'sendActionsForControlEvents:', 'textContainer.size=']:
    assert forbidden not in adapter, forbidden
report = {
    'baseline': '0.4.2-test4fix2', 'release': '0.4.3-test4fix3',
    'exactFileSHA256': exact, 'changedSourceSHA256': changed, 'addedSource': sorted(added),
    'scope': 'two-segment input action/host width; Host and Settings version strings only',
    'nativeThreeSegmentByteExact': True, 'nativeRecordGestureUntouched': True,
    'deviceTested': False,
}
(root / 'Validation' / 'fix3_scope.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(f'PASS: {len(exact)} FIX2 source files byte-exact; only two-segment adapter/policy and version-only edits in Host/Settings changed.')
