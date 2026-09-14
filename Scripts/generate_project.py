from pathlib import Path
import hashlib
root=Path(__file__).resolve().parent.parent
objects={}
def uid(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def add(name,body): i=uid(name); objects[i]=body; return i
def arr(values): return '('+','.join(values)+',)' if values else '()'
products=add('products','isa = PBXGroup; children = (APPREF,TESTREF,UIREF); name = Products; sourceTree = "<group>";')
refs=[]; phases={}
for target,folder in [('app','RaceCard'),('test','RaceCardTests'),('ui','RaceCardUITests')]:
    builds=[]
    for path in sorted((root/folder).rglob('*.swift')):
        rel=str(path.relative_to(root)); ref=add(rel,f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{rel}"; sourceTree = "<group>";'); refs.append(ref); builds.append(add(rel+'build',f'isa = PBXBuildFile; fileRef = {ref};'))
    phases[target]=add(target+'sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr(builds)}; runOnlyForDeploymentPostprocessing = 0;')
resourceBuilds=[]
for path in sorted((root/'RaceCard/Resources').rglob('*.strings')):
    rel=str(path.relative_to(root)); ref=add(rel,f'isa = PBXFileReference; lastKnownFileType = text.plist.strings; path = "{rel}"; sourceTree = "<group>";'); refs.append(ref)
    resourceBuilds.append(add(rel+'build',f'isa = PBXBuildFile; fileRef = {ref};'))
for path in sorted((root/'RaceCard/Resources').glob('*.json')):
    rel=str(path.relative_to(root)); ref=add(rel,f'isa = PBXFileReference; lastKnownFileType = text.json; path = "{rel}"; sourceTree = "<group>";'); refs.append(ref); resourceBuilds.append(add(rel+'build',f'isa = PBXBuildFile; fileRef = {ref};'))
folderPath='RaceCard/Resources/TrackMetadata'
folderRef=add(folderPath,f'isa = PBXFileReference; lastKnownFileType = folder; path = "{folderPath}"; sourceTree = "<group>";'); refs.append(folderRef)
resourceBuilds.append(add(folderPath+'build',f'isa = PBXBuildFile; fileRef = {folderRef};'))
identityPath='RaceCard/Resources/IdentityMetadata'
identityRef=add(identityPath,f'isa = PBXFileReference; lastKnownFileType = folder; path = "{identityPath}"; sourceTree = "<group>";'); refs.append(identityRef)
resourceBuilds.append(add(identityPath+'build',f'isa = PBXBuildFile; fileRef = {identityRef};'))
assetPath='RaceCard/Resources/TeamAssets.xcassets'
assetRef=add(assetPath,f'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = "{assetPath}"; sourceTree = "<group>";'); refs.append(assetRef)
resourceBuilds.append(add(assetPath+'build',f'isa = PBXBuildFile; fileRef = {assetRef};'))
resources=add('resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {arr(resourceBuilds)}; runOnlyForDeploymentPostprocessing = 0;')
appref=add('appref','isa = PBXFileReference; explicitFileType = wrapper.application; path = RaceCard.app; sourceTree = BUILT_PRODUCTS_DIR;')
testref=add('testref','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = RaceCardTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
uiref=add('uiref','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = RaceCardUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
objects[products]=objects[products].replace('APPREF',appref).replace('TESTREF',testref).replace('UIREF',uiref)
group=add('main',f'isa = PBXGroup; children = {arr(refs+[products])}; sourceTree = "<group>";')
pkg=add('mqtt','isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/swift-server-community/mqtt-nio.git"; requirement = { kind = revision; revision = 14c8e627440a751ea564d996185d9a2d8a37593b; };')
mqtt=add('mqttproduct',f'isa = XCSwiftPackageProductDependency; package = {pkg}; productName = MQTTNIO;')
localpkg=add('datakitpackage','isa = XCLocalSwiftPackageReference; relativePath = RaceCardDataKit;')
datakit=add('datakitproduct',f'isa = XCSwiftPackageProductDependency; package = {localpkg}; productName = RaceCardDataKit;')
ssl=add('sslproduct','isa = XCSwiftPackageProductDependency; productName = NIOSSL;')
frameworks=add('frameworks',f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {arr([add("datakitbuild",f"isa = PBXBuildFile; productRef = {datakit};"),add("mqttbuild",f"isa = PBXBuildFile; productRef = {mqtt};"),add("sslbuild",f"isa = PBXBuildFile; productRef = {ssl};")])}; runOnlyForDeploymentPostprocessing = 0;')
def configs(name,extra):
    ids=[]
    for mode in ['Debug','Release']:
        settings=('SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG; ' if mode=='Debug' else 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = RELEASE; ')+'SDKROOT = macosx; ONLY_ACTIVE_ARCH = YES; MACOSX_DEPLOYMENT_TARGET = 15.0; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES; SWIFT_STRICT_CONCURRENCY = minimal; CODE_SIGN_STYLE = Automatic; CODE_SIGN_IDENTITY = "-"; ENABLE_APP_SANDBOX = NO; SWIFT_OPTIMIZATION_LEVEL = '+ ('"-Onone"' if mode=='Debug' else '"-O"')+'; DEBUG_INFORMATION_FORMAT = dwarf; ENABLE_TESTABILITY = YES; '+extra
        ids.append(add(name+mode,f'isa = XCBuildConfiguration; name = {mode}; buildSettings = {{ {settings} }};'))
    return add(name+'configs',f'isa = XCConfigurationList; buildConfigurations = {arr(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
app=uid('app'); test=uid('test'); ui=uid('ui'); project=uid('project')
iconSetting='ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; ' if (root/'RaceCard/Resources/TeamAssets.xcassets/AppIcon.appiconset').exists() else ''
appcfg=configs('app',iconSetting+'PRODUCT_NAME = RaceCard; PRODUCT_BUNDLE_IDENTIFIER = local.racecard.mac; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.sports"; INFOPLIST_KEY_NSPrincipalClass = NSApplication; MARKETING_VERSION = 2.7; CURRENT_PROJECT_VERSION = 273; OTHER_LDFLAGS = "$(inherited) -lsqlite3";')
add('app',f'isa = PBXNativeTarget; buildConfigurationList = {appcfg}; buildPhases = {arr([phases["app"],frameworks,resources])}; buildRules = (); dependencies = (); name = RaceCard; productName = RaceCard; productReference = {appref}; productType = "com.apple.product-type.application"; packageProductDependencies = {arr([mqtt,ssl,datakit])};')
for key,name,ref,ptype in [('test','RaceCardTests',testref,'bundle.unit-test'),('ui','RaceCardUITests',uiref,'bundle.ui-testing')]:
    proxy=add(key+'proxy',f'isa = PBXContainerItemProxy; containerPortal = {project}; proxyType = 1; remoteGlobalIDString = {app}; remoteInfo = RaceCard;')
    dep=add(key+'dep',f'isa = PBXTargetDependency; target = {app}; targetProxy = {proxy};')
    extra=f'PRODUCT_NAME = {name}; PRODUCT_BUNDLE_IDENTIFIER = local.racecard.{key}; GENERATE_INFOPLIST_FILE = YES; '
    extra+= 'TEST_HOST = "$(BUILT_PRODUCTS_DIR)/RaceCard.app/Contents/MacOS/RaceCard"; BUNDLE_LOADER = "$(TEST_HOST)";' if key=='test' else 'TEST_TARGET_NAME = RaceCard;'
    cfg=configs(key,extra)
    add(key,f'isa = PBXNativeTarget; buildConfigurationList = {cfg}; buildPhases = {arr([phases[key]])}; buildRules = (); dependencies = {arr([dep])}; name = {name}; productName = {name}; productReference = {ref}; productType = "com.apple.product-type.{ptype}";')
pconfig=configs('project','')
add('project',f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2660; TargetAttributes = {{ {test} = {{ TestTargetID = {app}; }}; {ui} = {{ TestTargetID = {app}; }}; }}; }}; buildConfigurationList = {pconfig}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,ja,Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {arr([app,test,ui])}; packageReferences = {arr([pkg,localpkg])};')
p=root/'RaceCard.xcodeproj'; p.mkdir(exist_ok=True)
(p/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+''.join(i+' = { '+body+' };\n' for i,body in objects.items())+'}; rootObject = '+project+'; }\n')
s=p/'xcshareddata/xcschemes';s.mkdir(parents=True,exist_ok=True)
def entry(id,name): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{id}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:RaceCard.xcodeproj"/>'
(s/'RaceCard.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?><Scheme LastUpgradeVersion="2660" version="1.7"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{entry(app,'RaceCard.app')}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{entry(test,'RaceCardTests.xctest')}</TestableReference><TestableReference skipped="NO">{entry(ui,'RaceCardUITests.xctest')}</TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{entry(app,'RaceCard.app')}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{entry(app,'RaceCard.app')}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
