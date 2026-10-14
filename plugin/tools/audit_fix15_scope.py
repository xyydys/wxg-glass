#!/usr/bin/env python3
"""Source scope regression check. Does not claim native pixels or performance."""
from pathlib import Path
import argparse, hashlib, json, re
p=argparse.ArgumentParser();p.add_argument('--baseline',required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[1];src=root/'Sources';old=Path(a.baseline)/'Sources'
def method(text,signature):
    matches=list(re.finditer(re.escape(signature)+r'[^;\n]*\{',text));assert matches,signature
    body=text[matches[-1].start():];end=re.search(r'\n(?:[-+] \(|@end)',body)
    return body[:end.start()] if end else body.rstrip()
mutable={'WXGBackdrop.m','WXGBackdropTraversal.h','WXGHost.m','WXGGlassView.m','WXGSettings.m'}
unchanged={}
for path in sorted(old.iterdir()):
    if not path.is_file() or path.name in mutable:continue
    assert (src/path.name).read_bytes()==path.read_bytes(),path.name
    unchanged[path.name]=hashlib.sha256(path.read_bytes()).hexdigest()
assert (src/'WXGSettings.m').read_text().replace('FIX15','FIX14')==(old/'WXGSettings.m').read_text()
renderer=(src/'WXGGlassView.m').read_text()
assert renderer.replace('current_layers_native_media_shared_Metal_FIX15','live_scene_spatial_native_branches_shared_Metal_FIX14')==(old/'WXGGlassView.m').read_text()
host=(src/'WXGHost.m').read_text();previous=(old/'WXGHost.m').read_text()
signatures=['- (void)refresh','- (void)tick:','- (void)presentSettings','- (NSDictionary *)samplingMetrics',
            '- (NSString *)diagnostics','- (void)exportDiagnosticsFrom:']
normalized=host.replace('0.4.15','0.4.14').replace('FIX15','FIX14').replace('fix15','fix14')
normalized=normalized.replace('@property(nonatomic) NSUInteger coveredRenderFrames;\n','')
original=previous
for signature in signatures:
    # Replace only the reviewed main method body, not declarations/the tick proxy.
    normalized=normalized.replace(method(normalized,signature),'/* '+signature+' reviewed */\n')
    original=original.replace(method(original,signature),'/* '+signature+' reviewed */\n')
assert normalized==original,'Unintended host layout, hooks, navigation, input, or state repair change'
methods={}
for signature in ['- (void)layoutInput','- (void)flushInputRepair','- (void)changed:',
                  '- (void)buildNavigation','- (void)buildDock','- (void)dockChanged:',
                  '- (void)applyDockPresentation:','- (void)observeTransition:',
                  '- (void)prepareController:','- (void)repairDetachedNavigationBindings']:
    value=method(host,signature)
    assert value==method(previous,signature),signature
    methods[signature]=hashlib.sha256(value.encode()).hexdigest()
tick=method(host,'- (void)tick:')
assert 'if(_inputRepairsSuspended || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;' in tick
assert 'WXGInputRepairNextFrame(&_inputRepairGate)' in tick
assert 'if(!_suspendedByCover) {' in tick
assert 'WXGBeginBackdropFrame(glass,moving,link.timestamp)' in tick
assert '_suspendedByCover)return' not in tick
settings=method(host,'- (void)presentSettings')
assert '_displayLink.paused=YES' not in settings
refresh=method(host,'- (void)refresh')
cover=refresh[refresh.index('if(r.presented'):refresh.index('if(_suspendedByCover){')]
assert '_displayLink.paused=YES' not in cover
assert '@"liveSamplingAtExport":self.samplingMetrics' in host
sampler=(src/'WXGBackdrop.m').read_text()
assert 'WXGContainerSplitGuard(view,exactChildOrder)' in sampler and 'return @"layerOrder"' not in sampler
assert 'NSSortStable' in sampler and 'WXGBackdropCompareZ(x.zPosition,y.zPosition)' in sampler
assert 'for(UIView *child in children)' in sampler
assert '[shown renderInContext:ctx]' in sampler and '[view drawViewHierarchyInRect:shown.bounds afterScreenUpdates:NO]' in sampler
assert 'WXGLayerRasterGuard(view.layer,0,&inspected)' in sampler
for gate in ['layerTreeBudget','specialLayer:','nonImageContents','layerFilter','layerShadow','layer3D']:
    assert '@"'+gate+'"' in sampler,gate
assert 'WXGLayerRasterGuard(layer.mask,depth+1,visited)' in sampler
assert 'for(CALayer *child in layer.sublayers)' in sampler
for forbidden in ['setHidden:','removeFromSuperlayer','removeFromSuperview','afterScreenUpdates:YES','CATransaction flush','dispatch_sync','sleep(']:
    assert forbidden not in sampler,forbidden
assert 'sample.leases' not in sampler  # no bypass of acquire/release ownership
assert 's.leases==0 && s!=r.sample' in sampler and 'r.pool.count<3' in sampler
assert 'sample.coverage=coverage' in sampler and 'WXGROICovers(&published,consumer.footprint)' in sampler
assert 'WXGBackdropDue(frameTime,r.captured,fps,covered)' in sampler
report={'release':'0.4.15-test4fix15','baseline':'FIX14','unchangedSourceFiles':unchanged,'unchangedHostMethods':methods,
        'rendererIdenticalExceptDiagnosticName':True,'hostIdenticalOutsideReviewedRenderAndExportMethods':True,
        'opticsAndGeometryPreserved':True,'fix12InputProtectionPreserved':True,
        'nativeLayerOrderUsed':True,'ordinaryLayerReadInspectedEveryFrame':True,'nativeSpecialRendererPathRetained':True,
        'noSourceVisibilityOrLayerTreeMutationDuringRead':True,'sameCadenceAndPoolLeasePolicy':True,
        'foregroundSheetDoesNotPauseSampling':True,'systemInactivePausePreserved':True,
        'deviceTested':False,'verifiedDeviceFPS':None}
(root/'Validation/fix15_scope.json').write_text(json.dumps(report,indent=2)+'\n')
print(f'PASS: {len(unchanged)} source files unchanged; renderer unchanged except backend label; host changes confined to render/cover/export; native draw order, special renderer guards, buffer leases, input protection and source mutation boundaries checked.')
