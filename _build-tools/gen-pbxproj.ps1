param(
    [string]$ProjectDir = "E:\DrinkTrack\DrinkTrack",
    [string]$OutFile = "E:\DrinkTrack\DrinkTrack\DrinkTrack.xcodeproj\project.pbxproj"
)

$ErrorActionPreference = "Stop"
$srcRoot = Join-Path $ProjectDir "DrinkTrack"

# ---- 1. Explicit file manifest (must match what is actually on disk) ----
$swiftFiles = @(
    "DrinkTrackApp.swift",
    "Model/PersistenceController.swift",
    "HealthKit/HealthKitManager.swift",
    "HealthKit/HealthKitTypes.swift",
    "Domain/FeatureFlags.swift",
    "Domain/DrinkCategory.swift",
    "Domain/StandardDrinkConverter.swift",
    "Domain/AlertThresholdEngine.swift",
    "Domain/SessionAutoArchiver.swift",
    "Repositories/DrinkRepository.swift",
    "Repositories/FriendRepository.swift",
    "Features/Onboarding/OnboardingCoordinator.swift",
    "Features/Onboarding/DisclaimerView.swift",
    "Features/Onboarding/PrivacyPolicyView.swift",
    "Features/Onboarding/AppIntroView.swift",
    "Features/Dashboard/SessionControlView.swift",
    "Features/Dashboard/SessionLogListView.swift",
    "Features/Dashboard/HeartRateChartView.swift",
    "Features/Dashboard/SpO2View.swift",
    "Features/Dashboard/AlertToastView.swift",
    "Features/Dashboard/DashboardView.swift",
    "Features/DrinkLogging/QuickLogSheet.swift",
    "Features/DrinkLogging/DrinkCategoryPicker.swift",
    "Features/DrinkLogging/VolumeInputView.swift",
    "Features/Trends/TrendsView.swift",
    "Features/Trends/FrequencyChart.swift",
    "Features/Trends/VolumeTrendChart.swift",
    "Features/Trends/DrinkVsNonDrinkComparisonView.swift",
    "Features/Trends/MonthlySpendSummaryView.swift",
    "Features/Social/FriendFeedView.swift",
    "Features/Social/FriendCodeView.swift",
    "Features/Social/ShareCardView.swift",
    "Features/Social/SessionDetailView.swift",
    "Features/Social/SessionTimelineChart.swift",
    "Features/Settings/SettingsView.swift",
    "Features/Settings/DataManagementView.swift",
    "Features/Settings/ProfileView.swift",
    "Features/Settings/HealthConnectionStatusView.swift",
    "Shared/DisclaimerStrings.swift",
    "Shared/DesignSystem.swift",
    "Shared/NumericField.swift",
    "Shared/RootView.swift",
    "Shared/UserPreferences.swift"
)

$plainOtherFiles = @(
    @{ Path = "Info.plist"; Type = "text.plist.xml" },
    @{ Path = "DrinkTrack.entitlements"; Type = "text.plist.entitlements" },
    @{ Path = "Assets.xcassets"; Type = "folder.assetcatalog" }
)

$xcdatamodeldRel = "Model/DrinkTrack.xcdatamodeld"
$xcdatamodelChildNames = @(
    "DrinkTrack.xcdatamodel",
    "DrinkTrack 2.xcdatamodel"
)
$xcdatamodelCurrentName = "DrinkTrack 2.xcdatamodel"

# ---- 2. Verify every referenced file actually exists on disk ----
foreach ($f in $swiftFiles) {
    $full = Join-Path $srcRoot $f
    if (-not (Test-Path $full)) { throw "Missing file: $full" }
}
foreach ($f in $plainOtherFiles) {
    $full = Join-Path $srcRoot $f.Path
    if (-not (Test-Path $full)) { throw "Missing file: $full" }
}
foreach ($childName in $xcdatamodelChildNames) {
    $xcdatamodelFull = Join-Path $srcRoot (Join-Path $xcdatamodeldRel $childName)
    if (-not (Test-Path $xcdatamodelFull)) { throw "Missing Core Data model: $xcdatamodelFull" }
}
Write-Host ("Verified {0} swift files + {1} other files + {2} Core Data model versions" -f $swiftFiles.Count, $plainOtherFiles.Count, $xcdatamodelChildNames.Count)

function Format-PbxValue($name) {
    if ($name -match '[^A-Za-z0-9._]') {
        $escaped = $name -replace '\\', '\\' -replace '"', '\"'
        return ('"{0}"' -f $escaped)
    }
    return $name
}

# ---- 3. ID generator ----
$script:counter = 0
function New-Id {
    $script:counter++
    return ('{0:X24}' -f $script:counter)
}

# ---- 4. Build group tree ----
function New-GroupNode($name) {
    [ordered]@{ Name = $name; Kind = 'group'; Children = (New-Object System.Collections.ArrayList) }
}

$root = New-GroupNode "DrinkTrack" # corresponds to the DrinkTrack/DrinkTrack folder on disk

function Get-OrCreateSubgroup($parentNode, $name) {
    foreach ($c in $parentNode.Children) {
        if ($c.Kind -eq 'group' -and $c.Name -eq $name) { return $c }
    }
    $g = New-GroupNode $name
    [void]$parentNode.Children.Add($g)
    return $g
}

function Add-FileNode($relPath, $fileType) {
    $parts = $relPath -split '/'
    $node = $root
    for ($i = 0; $i -lt $parts.Length - 1; $i++) {
        $node = Get-OrCreateSubgroup $node $parts[$i]
    }
    $leaf = $parts[-1]
    $fileNode = [ordered]@{ Name = $leaf; Kind = 'file'; FileType = $fileType; RelPath = $relPath }
    [void]$node.Children.Add($fileNode)
}

foreach ($f in $swiftFiles) { Add-FileNode $f "sourcecode.swift" }
foreach ($f in $plainOtherFiles) { Add-FileNode $f.Path $f.Type }

# xcdatamodeld special node (XCVersionGroup), placed under the Model group
$modelParts = $xcdatamodeldRel -split '/'
$modelGroupNode = $root
for ($i = 0; $i -lt $modelParts.Length - 1; $i++) {
    $modelGroupNode = Get-OrCreateSubgroup $modelGroupNode $modelParts[$i]
}
$xcVersionNode = [ordered]@{
    Name = $modelParts[-1]; Kind = 'xcversion'; RelPath = $xcdatamodeldRel; ChildNames = $xcdatamodelChildNames; CurrentName = $xcdatamodelCurrentName
}
[void]$modelGroupNode.Children.Add($xcVersionNode)

# ---- 5. Walk the tree, assign IDs, collect pbxproj objects ----
$fileRefs = New-Object System.Collections.ArrayList
$groups = New-Object System.Collections.ArrayList
$xcVersionGroups = New-Object System.Collections.ArrayList
$sourceBuildFiles = New-Object System.Collections.ArrayList
$resourceBuildFiles = New-Object System.Collections.ArrayList

function Walk-Node($node) {
    if ($node.Kind -eq 'group') {
        $id = New-Id
        $childIds = New-Object System.Collections.ArrayList
        foreach ($c in $node.Children) {
            $cid = Walk-Node $c
            [void]$childIds.Add($cid)
        }
        [void]$groups.Add(@{ Id = $id; Name = $node.Name; ChildrenIds = $childIds })
        return $id
    } elseif ($node.Kind -eq 'file') {
        $id = New-Id
        [void]$fileRefs.Add(@{ Id = $id; Name = $node.Name; FileType = $node.FileType })
        if ($node.FileType -eq 'sourcecode.swift') {
            $bfId = New-Id
            [void]$sourceBuildFiles.Add(@{ Id = $bfId; FileRefId = $id; Name = $node.Name })
        } elseif ($node.FileType -eq 'folder.assetcatalog') {
            $bfId = New-Id
            [void]$resourceBuildFiles.Add(@{ Id = $bfId; FileRefId = $id; Name = $node.Name })
        }
        return $id
    } elseif ($node.Kind -eq 'xcversion') {
        $childIds = New-Object System.Collections.ArrayList
        $currentId = $null
        foreach ($childName in $node.ChildNames) {
            $childFileRefId = New-Id
            [void]$fileRefs.Add(@{ Id = $childFileRefId; Name = $childName; FileType = 'wrapper.xcdatamodel'; IsDataModelChild = $true })
            [void]$childIds.Add(@{ Id = $childFileRefId; Name = $childName })
            if ($childName -eq $node.CurrentName) { $currentId = $childFileRefId }
        }
        if (-not $currentId) { throw "Current Core Data model version not listed in children: $($node.CurrentName)" }
        $groupId = New-Id
        [void]$xcVersionGroups.Add(@{ Id = $groupId; Name = $node.Name; Children = $childIds; CurrentId = $currentId; CurrentName = $node.CurrentName })
        $bfId = New-Id
        [void]$sourceBuildFiles.Add(@{ Id = $bfId; FileRefId = $groupId; Name = $node.Name; IsVersionGroup = $true })
        return $groupId
    }
}

$rootGroupId = Walk-Node $root

# ---- 5b. Resolve every leaf's path EXACTLY the way Xcode would (by walking
# the $root tree and concatenating each ancestor's directory name), then
# confirm that path exists on disk. This is the check that would have caught
# the "Model" group losing its path segment, which a text search for
# `path = Foo.swift;` anywhere in the file cannot catch -- that string is
# present either way, it just resolves to the wrong on-disk location.
function Test-ResolvedPaths($node, $accumulatedPath) {
    if ($node.Kind -eq 'group') {
        $childPath = Join-Path $accumulatedPath $node.Name
        foreach ($c in $node.Children) {
            Test-ResolvedPaths $c $childPath
        }
    } elseif ($node.Kind -eq 'file') {
        $full = Join-Path $accumulatedPath $node.Name
        if (-not (Test-Path $full)) {
            throw "Group-path resolution mismatch: pbxproj would look for '$($node.Name)' at '$full', which does not exist on disk. A parent group's `path` is probably missing."
        }
    } elseif ($node.Kind -eq 'xcversion') {
        foreach ($childName in $node.ChildNames) {
            $full = Join-Path (Join-Path $accumulatedPath $node.Name) $childName
            if (-not (Test-Path $full)) {
                throw "Group-path resolution mismatch: pbxproj would look for the Core Data model at '$full', which does not exist on disk."
            }
        }
    }
}
# $root's own name ("DrinkTrack") is itself a path segment relative to srcRoot's
# parent (i.e. relative to the .xcodeproj's directory), so start resolution
# from $ProjectDir, not from $srcRoot.
Test-ResolvedPaths $root $ProjectDir
Write-Host "Group-path resolution check passed: every file's full path (as the pbxproj group tree encodes it) exists on disk."

# These IDs are intentionally FIXED (not sequential) so that adding/removing source
# files never shifts them. The shared scheme at
# DrinkTrack.xcodeproj/xcshareddata/xcschemes/DrinkTrack.xcscheme references
# $targetId as its BlueprintIdentifier -- if that value changed on every regeneration,
# the scheme would silently break and CI would fail with "scheme not found".
$appRefId               = 'FFFFFFFF000000000000000A'
$productsGroupId        = 'FFFFFFFF000000000000000B'
$mainGroupId            = 'FFFFFFFF000000000000000C'

$targetId               = 'FFFFFFFF0000000000000001'
$projectId              = 'FFFFFFFF0000000000000002'
$sourcesPhaseId         = 'FFFFFFFF0000000000000003'
$resourcesPhaseId       = 'FFFFFFFF0000000000000004'
$frameworksPhaseId      = 'FFFFFFFF0000000000000005'
$targetDebugConfigId    = 'FFFFFFFF0000000000000006'
$targetReleaseConfigId  = 'FFFFFFFF0000000000000007'
$targetConfigListId     = 'FFFFFFFF0000000000000008'
$projectDebugConfigId   = 'FFFFFFFF0000000000000009'
$projectReleaseConfigId = 'FFFFFFFF000000000000000D'
$projectConfigListId    = 'FFFFFFFF000000000000000E'

# ---- 6. Emit text ----
$sb = New-Object System.Text.StringBuilder
function W($s) { [void]$sb.AppendLine($s) }

W '// !$*UTF8*$!'
W '{'
W '	archiveVersion = 1;'
W '	classes = {'
W '	};'
W '	objectVersion = 56;'
W '	objects = {'
W ''

W '/* Begin PBXBuildFile section */'
foreach ($bf in $sourceBuildFiles) {
    W "		$($bf.Id) /* $($bf.Name) in Sources */ = {isa = PBXBuildFile; fileRef = $($bf.FileRefId) /* $($bf.Name) */; };"
}
foreach ($bf in $resourceBuildFiles) {
    W "		$($bf.Id) /* $($bf.Name) in Resources */ = {isa = PBXBuildFile; fileRef = $($bf.FileRefId) /* $($bf.Name) */; };"
}
W '/* End PBXBuildFile section */'
W ''

W '/* Begin PBXFileReference section */'
W "		$appRefId /* DrinkTrack.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = DrinkTrack.app; sourceTree = BUILT_PRODUCTS_DIR; };"
foreach ($fr in $fileRefs) {
    $quotedName = Format-PbxValue $fr.Name
    if ($fr.FileType -eq 'sourcecode.swift') {
        W "		$($fr.Id) /* $($fr.Name) */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = $quotedName; sourceTree = `"<group>`"; };"
    } elseif ($fr.FileType -eq 'wrapper.xcdatamodel') {
        W "		$($fr.Id) /* $($fr.Name) */ = {isa = PBXFileReference; lastKnownFileType = wrapper.xcdatamodel; path = $quotedName; sourceTree = `"<group>`"; };"
    } else {
        W "		$($fr.Id) /* $($fr.Name) */ = {isa = PBXFileReference; lastKnownFileType = $($fr.FileType); path = $quotedName; sourceTree = `"<group>`"; };"
    }
}
W '/* End PBXFileReference section */'
W ''

W '/* Begin PBXFrameworksBuildPhase section */'
W "		$frameworksPhaseId /* Frameworks */ = {"
W '			isa = PBXFrameworksBuildPhase;'
W '			buildActionMask = 2147483647;'
W '			files = ('
W '			);'
W '			runOnlyForDeploymentPostprocessing = 0;'
W '		};'
W '/* End PBXFrameworksBuildPhase section */'
W ''

W '/* Begin PBXGroup section */'
foreach ($g in $groups) {
    W "		$($g.Id) /* $($g.Name) */ = {"
    W '			isa = PBXGroup;'
    W '			children = ('
    foreach ($cid in $g.ChildrenIds) {
        W "				$cid,"
    }
    W '			);'
    # Every group here - root or nested - maps 1:1 to a real directory on disk
    # (our $swiftFiles manifest is built from actual relative paths), so every
    # group MUST have `path`, not just `name`. A PBXGroup with only `name` and
    # no `path` is a *virtual* group that contributes no path segment of its
    # own - Xcode then resolves its children directly under the PARENT group's
    # path, skipping this folder entirely. That exact bug is what broke the
    # CI build: momc looked for the Core Data model at
    # ".../DrinkTrack/DrinkTrack/DrinkTrack.xcdatamodeld" instead of
    # ".../DrinkTrack/DrinkTrack/Model/DrinkTrack.xcdatamodeld" because the
    # "Model" group had no `path`, and the same would have broken every other
    # subfolder (HealthKit, Domain, Features/*, Shared, ...) once the build
    # got far enough to need them.
    #
    # This was patched once before directly in the committed pbxproj (commit
    # "Fix Xcode group paths so Core Data model and sources resolve") but NOT
    # in this generator script - so the very next time this script regenerated
    # the project (to register new Swift files), the bug came back. Fixing it
    # here instead of in the output file is the only way it sticks.
    W "			path = $($g.Name);"
    W '			sourceTree = "<group>";'
    W '		};'
}
W "		$productsGroupId /* Products */ = {"
W '			isa = PBXGroup;'
W '			children = ('
W "				$appRefId /* DrinkTrack.app */,"
W '			);'
W '			name = Products;'
W '			sourceTree = "<group>";'
W '		};'
W "		$mainGroupId = {"
W '			isa = PBXGroup;'
W '			children = ('
W "				$rootGroupId /* DrinkTrack */,"
W "				$productsGroupId /* Products */,"
W '			);'
W '			sourceTree = "<group>";'
W '		};'
W '/* End PBXGroup section */'
W ''

W '/* Begin XCVersionGroup section */'
foreach ($vg in $xcVersionGroups) {
    W "		$($vg.Id) /* $($vg.Name) */ = {"
    W '			isa = XCVersionGroup;'
    W '			children = ('
    foreach ($child in $vg.Children) {
        W "				$($child.Id) /* $($child.Name) */,"
    }
    W '			);'
    W "			currentVersion = $($vg.CurrentId) /* $($vg.CurrentName) */;"
    W "			path = $(Format-PbxValue $vg.Name);"
    W '			sourceTree = "<group>";'
    W '			versionGroupType = wrapper.xcdatamodel;'
    W '		};'
}
W '/* End XCVersionGroup section */'
W ''

W '/* Begin PBXNativeTarget section */'
W "		$targetId /* DrinkTrack */ = {"
W '			isa = PBXNativeTarget;'
W "			buildConfigurationList = $targetConfigListId /* Build configuration list for PBXNativeTarget `"DrinkTrack`" */;"
W '			buildPhases = ('
W "				$sourcesPhaseId /* Sources */,"
W "				$frameworksPhaseId /* Frameworks */,"
W "				$resourcesPhaseId /* Resources */,"
W '			);'
W '			buildRules = ('
W '			);'
W '			dependencies = ('
W '			);'
W '			name = DrinkTrack;'
W '			productName = DrinkTrack;'
W "			productReference = $appRefId /* DrinkTrack.app */;"
W '			productType = "com.apple.product-type.application";'
W '		};'
W '/* End PBXNativeTarget section */'
W ''

W '/* Begin PBXProject section */'
W "		$projectId /* Project object */ = {"
W '			isa = PBXProject;'
W '			attributes = {'
W '				BuildIndependentTargetsInParallel = 1;'
W '				LastSwiftUpdateCheck = 1530;'
W '				LastUpgradeCheck = 1530;'
W '				TargetAttributes = {'
W "					$targetId = {"
W '						CreatedOnToolsVersion = 15.3;'
W '					};'
W '				};'
W '			};'
W "			buildConfigurationList = $projectConfigListId /* Build configuration list for PBXProject `"DrinkTrack`" */;"
W '			compatibilityVersion = "Xcode 14.0";'
W '			developmentRegion = zh-Hans;'
W '			hasScannedForEncodings = 0;'
W '			knownRegions = ('
W '				zh-Hans,'
W '				Base,'
W '			);'
W "			mainGroup = $mainGroupId;"
W "			productRefGroup = $productsGroupId /* Products */;"
W '			projectDirPath = "";'
W '			projectRoot = "";'
W '			targets = ('
W "				$targetId /* DrinkTrack */,"
W '			);'
W '		};'
W '/* End PBXProject section */'
W ''

W '/* Begin PBXResourcesBuildPhase section */'
W "		$resourcesPhaseId /* Resources */ = {"
W '			isa = PBXResourcesBuildPhase;'
W '			buildActionMask = 2147483647;'
W '			files = ('
foreach ($bf in $resourceBuildFiles) {
    W "				$($bf.Id) /* $($bf.Name) in Resources */,"
}
W '			);'
W '			runOnlyForDeploymentPostprocessing = 0;'
W '		};'
W '/* End PBXResourcesBuildPhase section */'
W ''

W '/* Begin PBXSourcesBuildPhase section */'
W "		$sourcesPhaseId /* Sources */ = {"
W '			isa = PBXSourcesBuildPhase;'
W '			buildActionMask = 2147483647;'
W '			files = ('
foreach ($bf in $sourceBuildFiles) {
    W "				$($bf.Id) /* $($bf.Name) in Sources */,"
}
W '			);'
W '			runOnlyForDeploymentPostprocessing = 0;'
W '		};'
W '/* End PBXSourcesBuildPhase section */'
W ''

$commonProjectSettings = @'
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				MTL_FAST_MATH = YES;
				SDKROOT = iphoneos;
				SWIFT_VERSION = 5.0;
'@

W '/* Begin XCBuildConfiguration section */'
W "		$projectDebugConfigId /* Debug */ = {"
W '			isa = XCBuildConfiguration;'
W '			buildSettings = {'
W $commonProjectSettings
W '				DEBUG_INFORMATION_FORMAT = dwarf;'
W '				ENABLE_TESTABILITY = YES;'
W '				GCC_OPTIMIZATION_LEVEL = 0;'
W '				GCC_PREPROCESSOR_DEFINITIONS = ('
W '					"DEBUG=1",'
W '					"$(inherited)",'
W '				);'
W '				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;'
W '				ONLY_ACTIVE_ARCH = YES;'
W '				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;'
W '				SWIFT_OPTIMIZATION_LEVEL = "-Onone";'
W '			};'
W '			name = Debug;'
W '		};'
W "		$projectReleaseConfigId /* Release */ = {"
W '			isa = XCBuildConfiguration;'
W '			buildSettings = {'
W $commonProjectSettings
W '				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'
W '				MTL_ENABLE_DEBUG_INFO = NO;'
W '				SWIFT_COMPILATION_MODE = wholemodule;'
W '				VALIDATE_PRODUCT = YES;'
W '			};'
W '			name = Release;'
W '		};'

$targetCommonSettings = @'
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_ENTITLEMENTS = DrinkTrack/DrinkTrack.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = DrinkTrack/Info.plist;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 0.1.0;
				PRODUCT_BUNDLE_IDENTIFIER = "com.drinktrack.app";
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 1;
'@

W "		$targetDebugConfigId /* Debug */ = {"
W '			isa = XCBuildConfiguration;'
W '			buildSettings = {'
W $targetCommonSettings
W '			};'
W '			name = Debug;'
W '		};'
W "		$targetReleaseConfigId /* Release */ = {"
W '			isa = XCBuildConfiguration;'
W '			buildSettings = {'
W $targetCommonSettings
W '			};'
W '			name = Release;'
W '		};'
W '/* End XCBuildConfiguration section */'
W ''

W '/* Begin XCConfigurationList section */'
W "		$projectConfigListId /* Build configuration list for PBXProject `"DrinkTrack`" */ = {"
W '			isa = XCConfigurationList;'
W '			buildConfigurations = ('
W "				$projectDebugConfigId /* Debug */,"
W "				$projectReleaseConfigId /* Release */,"
W '			);'
W '			defaultConfigurationIsVisible = 0;'
W '			defaultConfigurationName = Release;'
W '		};'
W "		$targetConfigListId /* Build configuration list for PBXNativeTarget `"DrinkTrack`" */ = {"
W '			isa = XCConfigurationList;'
W '			buildConfigurations = ('
W "				$targetDebugConfigId /* Debug */,"
W "				$targetReleaseConfigId /* Release */,"
W '			);'
W '			defaultConfigurationIsVisible = 0;'
W '			defaultConfigurationName = Release;'
W '		};'
W '/* End XCConfigurationList section */'
W ''

W '	};'
W "	rootObject = $projectId /* Project object */;"
W '}'

$text = $sb.ToString()
[System.IO.File]::WriteAllText($OutFile, $text, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("Generated: {0}" -f $OutFile)
Write-Host ("Total object id count: {0}" -f $script:counter)

# ---- 7. Validate the GENERATED TEXT ITSELF, not just the in-memory tree it came from.
#
# The Test-ResolvedPaths check above re-derives paths from the same $root tree that
# built the pbxproj text -- it can never catch a bug in *how* that tree got serialized
# (e.g. emitting `name = Foo;` instead of `path = Foo;`), because both the check and
# the bug share the same upstream data. This happened for real: the "Model" group was
# emitted with only `name`, no `path`; Test-ResolvedPaths still "passed" because it
# never re-read the output, it just re-confirmed Model/PersistenceController.swift
# exists on disk, which was never in question.
#
# So: read the file back and confirm every PBXGroup object (except the two that are
# legitimately path-less -- the main group, which represents the project itself, and
# the Products group, whose child uses BUILT_PRODUCTS_DIR, not a project-relative
# path) declares a `path = `.
$writtenText = [System.IO.File]::ReadAllText($OutFile)
$groupBlocks = [regex]::Matches(
    $writtenText,
    '(?ms)^\t\t([0-9A-F]{24})(?:\s*/\*[^*]*\*/)?\s*=\s*\{\s*\n\s*isa = PBXGroup;.*?\n\t\t\};'
)
$pathlessAllowed = @($mainGroupId, $productsGroupId)
$missingPath = @()
foreach ($m in $groupBlocks) {
    $id = $m.Groups[1].Value
    if ($pathlessAllowed -contains $id) { continue }
    if ($m.Value -notmatch '(?m)^\t\t\tpath = ') {
        $missingPath += $id
    }
}
if ($missingPath.Count -gt 0) {
    throw "REGRESSION: the following PBXGroup objects in the WRITTEN FILE have no `path`, meaning Xcode will not descend into their on-disk folder: $($missingPath -join ', ')"
}
Write-Host ("Text-level validation passed: all {0} PBXGroup objects in the written file (excluding main/Products) declare a path." -f ($groupBlocks.Count - $pathlessAllowed.Count))
