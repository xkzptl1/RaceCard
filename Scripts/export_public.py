#!/usr/bin/env python3
"""Create a source-only publication copy. Never include private preview assets."""
from pathlib import Path
import argparse,json,shutil,subprocess
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('destination',type=Path);a=p.parse_args();out=a.destination.resolve()
if out==root or root in out.parents and out.parts[-1] in ['RaceCard','Scripts']:raise SystemExit('Choose a separate export directory')
if out.exists() and any(out.iterdir()):raise SystemExit('Destination must be empty')
out.mkdir(parents=True,exist_ok=True)
for folder in ['RaceCard','RaceCardDataKit','RaceCardTests','RaceCardUITests']:
 for source in (root/folder).rglob('*'):
  if not source.is_file() or any(x in source.parts for x in ['.build','.swiftpm']):continue
  rel=source.relative_to(root)
  if source.suffix not in ['.swift','.strings'] and source.name!='Package.swift':continue
  target=out/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
# Curated factual identity metadata, no API record dump or bundled image bytes.
identity=out/'RaceCard/Resources/IdentityMetadata';identity.mkdir(parents=True,exist_ok=True)
for name in ['drivers.json','teams.json']:shutil.copyfile(root/'RaceCard/Resources/IdentityMetadata'/name,identity/name)
(identity/'snapshots.json').write_text('[]\n')
# Remove copyrighted diagram presentation while retaining scalar facts/provenance.
remove={'geometry','roadRings','operationalRings','timingSectorAreas','raceControlAreas','rings','points','polygons','referenceCenterline','canonicalCenterline'}
def factual(x):
 if isinstance(x,dict):return {k:factual(v) for k,v in x.items() if k not in remove}
 if isinstance(x,list):return [factual(v) for v in x]
 return x
metadata=root/'RaceCard/Resources/TrackMetadata'
for source in metadata.rglob('*.json'):
 rel=source.relative_to(metadata)
 if rel.parts[0] in ['calibrations','geometries'] or source.name.startswith('legacy_'):continue
 target=out/'RaceCard/Resources/TrackMetadata'/rel;target.parent.mkdir(parents=True,exist_ok=True)
 target.write_text(json.dumps(factual(json.loads(source.read_text())),ensure_ascii=False,indent=2)+'\n')
assets=out/'RaceCard/Resources/TeamAssets.xcassets';assets.mkdir(parents=True,exist_ok=True);(assets/'Contents.json').write_text('{"info":{"author":"xcode","version":1}}\n')
for name in ['README.md','LICENSE','THIRD_PARTY_NOTICES.md','CONTRIBUTING.md','SECURITY.md','INSTALL_EN.md','INSTALL_JA.md','.gitignore']:
 shutil.copyfile(root/name,out/name)
for source in (root/'Documentation/ThirdParty').rglob('*'):
 if source.is_file():
  dest=out/source.relative_to(root);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,dest)
(out/'Documentation').mkdir(exist_ok=True);shutil.copyfile(root/'Documentation/PUBLIC_BUILD.md',out/'Documentation/PUBLIC_BUILD.md')
(out/'Scripts').mkdir()
for name in ['generate_project.py','publication_audit.py','export_public.py']:
 shutil.copyfile(root/'Scripts'/name,out/'Scripts'/name)
shutil.copyfile(root/'Scripts/build_public.sh' if (root/'Scripts/build_public.sh').exists() else root/'Scripts/build.sh',out/'Scripts/build.sh');(out/'Scripts/build.sh').chmod(0o755)
subprocess.run(['python3',str(out/'Scripts/generate_project.py')],cwd=out,check=True)
pin=Path('RaceCard.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved');(out/pin).parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(root/pin,out/pin)
print('Exported source-only repository:',out.name)
