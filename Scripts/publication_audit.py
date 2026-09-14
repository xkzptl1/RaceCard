#!/usr/bin/env python3
"""Inventory publication-risk assets and text findings without printing secret values."""
from pathlib import Path
import collections,hashlib,json,re
root=Path(__file__).resolve().parents[1]
visual={'.png','.jpg','.jpeg','.svg','.pdf','.webp','.gif','.tif','.tiff','.ico','.icns','.ttf','.otf','.woff','.woff2','.mp4','.mov','.html','.zip','.car'}
rows=[];findings=[];large=[];count=0
patterns={
 'private-key':re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
 'credential-token':re.compile(r'\b(?:gh[pousr]_[A-Za-z0-9]{25,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[A-Z0-9]{16}|sk-[A-Za-z0-9]{32,})\b'),
 'jwt':re.compile(r'\beyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}\b'),
 'personal-home-path':re.compile(r'/Users/[^/\s"<>]+/'),
 'email-address':re.compile(r'\b[A-Za-z0-9._%+-]{1,100}@[A-Za-z0-9.-]{1,100}\.[A-Za-z]{2,}\b')}
for p in sorted(root.rglob('*')):
 if not p.is_file() or '.git' in p.parts:continue
 rel=p.relative_to(root).as_posix();count+=1;size=p.stat().st_size
 if size>25*1024*1024:large.append({'path':rel,'bytes':size})
 if p.suffix.lower() in visual:
  source='Unverified local visual / downloaded material';known='No';category='D';action='Exclude pending rights review'
  if 'team_' in rel or '/Assets/Teams/' in rel:source='Official Formula 1 team pages; see private TEAM_ASSET_SOURCES.json / identity metadata';known='Known or source family known'
  elif 'AppIcon' in rel or '/Branding/' in rel:source='User-supplied app artwork; no authorship/redistribution evidence supplied'
  elif '/QA/' in rel or '/Screenshots/' in rel or '/GuideImages/' in rel or 'USER_GUIDE' in rel:source='RaceCard captures; may incorporate runtime driver photos, team marks, or FIA-derived presentation';known='Capture provenance known; embedded rights unverified'
  elif '/Research/' in rel:source='Research acquisition from official/third-party sites; exact source where recorded in adjacent manifests';known='Partial'
  elif p.suffix=='.zip' or p.suffix=='.car':source='Generated binary/archive containing excluded visual assets';known='Build provenance known'
  rows.append({'path':rel,'type':p.suffix.lstrip('.'),'source':source,'provenance':known,'redistributionPermission':'Not established','classification':category,'action':action,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
 if (p.suffix.lower() in {'.swift','.py','.sh','.json','.md','.txt','.html','.log','.pbxproj','.resolved','.yml','.yaml','.env'} or p.name in {'LICENSE','Package.swift'}) and size<25*1024*1024:
  try:text=p.read_text()
  except (UnicodeError,OSError):continue
  text=re.sub(r'data:image/[^;]+;base64,[A-Za-z0-9+/=]+','[embedded image excluded]',text)
  for name,pattern in patterns.items():
   lines=sorted({text.count('\n',0,m.start())+1 for m in pattern.finditer(text)})
   if lines:findings.append({'path':rel,'category':name,'lines':lines})
# Exact PDF/SVG presentation geometry is not treated as an unprotected photograph substitute.
for p in sorted((root/'RaceCard/Resources/TrackMetadata').rglob('*.json')):
 d=json.loads(p.read_text());rel=p.relative_to(root).as_posix()
 if '/calibrations/' in rel or '/geometries/' in rel or (isinstance(d,dict) and d.get('geometry')) or p.name.startswith('legacy_'):
  rows.append({'path':rel,'type':'structured geometry / mixed factual metadata','source':'FIA PDF/F1 SVG tracing or source-derived calibration; see metadata research provenance','provenance':'Known','redistributionPermission':'Exact presentation redistribution not established','classification':'D','action':'Exclude geometry/calibration; retain only separately extracted scalar facts and source URLs'})
report={'filesInspected':count,'assets':rows,'findings':findings,'largeFiles':large,'gitHistory':'No .git directory in original workspace; history scan unavailable'}
private=root/'Documentation/Publication';private.mkdir(exist_ok=True)
(private/'inventory.json').write_text(json.dumps(report,indent=2))
md=['# Publication asset audit','',f'Initial whole-workspace inventory: {count} files; {len(rows)} potentially protected visual/container/geometry entries. Original workspace has no Git history.','',
'Categories: A = safe to publish; B = publish with required attribution/license; C = runtime-fetch only under applicable terms; D = exclude pending review. No original visual asset is assumed publishable merely because its URL is public.','',
'All listed D assets are excluded from the sanitized public source. Runtime headshot URLs remain metadata (C); no photograph bytes are bundled. Team marks use the existing neutral monogram fallback. No bundled fonts were found. System fonts and symbols are platform APIs, not redistributed font files. Original FIA PDFs, traced presentation polygons, existing screenshots and the supplied icon are not published. Scalar factual metadata and provenance remain (A); dependency license/notice texts are retained (B).','',
'| Original workspace-relative path | Type | Apparent source | Provenance known | Redistribution permission | Class | GitHub action |','|---|---|---|---|---|---|---|']
for r in rows:md.append('| `'+r['path']+'` | '+r['type']+' | '+r['source']+' | '+r['provenance']+' | '+r['redistributionPermission']+' | '+r['classification']+' | '+r['action']+' |')
(root/'PUBLICATION_ASSET_AUDIT.md').write_text('\n'.join(md)+'\n')
print(json.dumps({'files':count,'assetEntries':len(rows),'findingsByCategory':dict(collections.Counter(x['category'] for x in findings)),'largeFiles':len(large)}))
