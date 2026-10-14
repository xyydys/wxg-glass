#!/usr/bin/env python3
"""Full function-body semantic check, with a real Apple SDK. No linking."""
import argparse,json,pathlib,sys
from clang.cindex import Index,Diagnostic
p=argparse.ArgumentParser();p.add_argument('--sdk',required=True);p.add_argument('--resource-dir',required=True);p.add_argument('--arch',action='append');a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1];records=[]
for arch in a.arch or ['arm64','arm64e']:
 for source in sorted((root/'Sources').glob('*.m')):
  args=['-x','objective-c','-target',arch+'-apple-ios13.0','-isysroot',a.sdk,'-resource-dir',a.resource_dir,'-fobjc-arc','-fblocks','-O2','-Wall','-Wextra','-Wno-deprecated-declarations','-I'+str(root/'Sources')]
  tu=Index.create().parse(str(source),args=args)
  errors=[str(d) for d in tu.diagnostics if d.severity>=Diagnostic.Error]
  warnings=[str(d) for d in tu.diagnostics if d.severity==Diagnostic.Warning]
  records.append(dict(arch=arch,file=source.name,errors=errors,warnings=warnings))
  print(arch,source.name,len(errors),'errors',len(warnings),'warnings',flush=True)
  for diagnostic in errors+warnings:print(diagnostic,flush=True)
sdk_settings=pathlib.Path(a.sdk)/'SDKSettings.json'
sdk_version=json.loads(sdk_settings.read_text()).get('Version','unknown') if sdk_settings.exists() else 'unknown'
report=dict(method='libclang 18.1.1 full Objective-C semantic parse with real Apple SDK, no private-header stubs; not codegen/link/Metal validation',sdkVersion=sdk_version,sdkDirectory=pathlib.Path(a.sdk).name,deploymentTarget='13.0',units=records)
(root/'Validation'/'objc_sdk_diagnostics.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
sys.exit(any(r['errors'] or r['warnings'] for r in records))
