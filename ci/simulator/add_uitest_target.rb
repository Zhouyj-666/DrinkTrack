# Adds a throwaway UI-test target + "DrinkTrackSmoke" scheme to the Xcode project
# at CI time only. The committed project.pbxproj is NOT modified in git, so the
# IPA workflow (.github/workflows/build.yml) is unaffected.
#
# Usage (from repo root, on macOS CI):  ruby ci/simulator/add_uitest_target.rb
require 'xcodeproj'

PROJECT_PATH = 'DrinkTrack/DrinkTrack.xcodeproj'
UITEST_NAME  = 'DrinkTrackUITests'
SCHEME_NAME  = 'DrinkTrackSmoke'

project = Xcodeproj::Project.open(PROJECT_PATH)
app = project.targets.find { |t| t.name == 'DrinkTrack' }
abort 'DrinkTrack app target not found' unless app

if project.targets.any? { |t| t.name == UITEST_NAME }
  puts "#{UITEST_NAME} already exists, skipping target creation"
  ui = project.targets.find { |t| t.name == UITEST_NAME }
else
  ui = project.new_target(:ui_test_bundle, UITEST_NAME, :ios, '17.0')

  group = project.main_group.find_subpath(UITEST_NAME, true)
  group.set_source_tree('<group>')
  group.set_path(UITEST_NAME)
  ref = group.new_reference('DrinkTrackSmokeUITests.swift')
  ui.add_file_references([ref])
  ui.add_dependency(app)

  ui.build_configurations.each do |c|
    s = c.build_settings
    s['TEST_TARGET_NAME'] = 'DrinkTrack'
    s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.drinktrack.app.uitests'
    s['PRODUCT_NAME'] = '$(TARGET_NAME)'
    s['SWIFT_VERSION'] = '5.0'
    s['GENERATE_INFOPLIST_FILE'] = 'YES'
    s['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
    s['TARGETED_DEVICE_FAMILY'] = '1,2'
    s['CODE_SIGN_STYLE'] = 'Manual'
    s['CODE_SIGN_IDENTITY'] = '-'
    s['DEVELOPMENT_TEAM'] = ''
  end

  attrs = (project.root_object.attributes['TargetAttributes'] ||= {})
  attrs[ui.uuid] = { 'CreatedOnToolsVersion' => '16.0', 'TestTargetID' => app.uuid }
  project.save
end

scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app, ui, launch_target: true)
scheme.test_action.build_configuration = 'Debug'
scheme.save_as(PROJECT_PATH, SCHEME_NAME, true)

puts "Added #{UITEST_NAME} target and #{SCHEME_NAME} scheme"
