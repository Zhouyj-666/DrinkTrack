# Adds throwaway UI-test + unit-test targets + "DrinkTrackSmoke" scheme at CI time.
# The committed project.pbxproj is NOT modified in git.
require 'xcodeproj'

PROJECT_PATH = 'DrinkTrack/DrinkTrack.xcodeproj'
UITEST_NAME  = 'DrinkTrackUITests'
UNITTEST_NAME = 'DrinkTrackTests'
SCHEME_NAME  = 'DrinkTrackSmoke'

project = Xcodeproj::Project.open(PROJECT_PATH)
app = project.targets.find { |t| t.name == 'DrinkTrack' }
abort 'DrinkTrack app target not found' unless app

unless project.targets.any? { |t| t.name == UITEST_NAME }
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

ui = project.targets.find { |t| t.name == UITEST_NAME }

unless project.targets.any? { |t| t.name == UNITTEST_NAME }
  unit = project.new_target(:unit_test_bundle, UNITTEST_NAME, :ios, '17.0')
  group = project.main_group.find_subpath(UNITTEST_NAME, true)
  group.set_source_tree('<group>')
  group.set_path(UNITTEST_NAME)
  %w[
    RouteJournalTests.swift
    DashboardGlanceBuilderTests.swift
    TrendAxisTests.swift
    AuthAPIMappingTests.swift
    AccountRecordTaggerTests.swift
    AuthSessionTests.swift
  ].each do |name|
    ref = group.new_reference(name)
    unit.add_file_references([ref])
  end
  unit.add_dependency(app)
  unit.build_configurations.each do |c|
    s = c.build_settings
    s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.drinktrack.app.tests'
    s['PRODUCT_NAME'] = '$(TARGET_NAME)'
    s['SWIFT_VERSION'] = '5.0'
    s['GENERATE_INFOPLIST_FILE'] = 'YES'
    s['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
    s['TARGETED_DEVICE_FAMILY'] = '1,2'
    s['CODE_SIGN_STYLE'] = 'Manual'
    s['CODE_SIGN_IDENTITY'] = '-'
    s['DEVELOPMENT_TEAM'] = ''
    s['BUNDLE_LOADER'] = '$(TEST_HOST)'
    s['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/DrinkTrack.app/DrinkTrack'
  end
  # Host the unit tests in the app so @testable import works with ENABLE_TESTABILITY.
  app.build_configurations.each do |c|
    c.build_settings['ENABLE_TESTABILITY'] = 'YES'
  end
  attrs = (project.root_object.attributes['TargetAttributes'] ||= {})
  attrs[unit.uuid] = { 'CreatedOnToolsVersion' => '16.0', 'TestTargetID' => app.uuid }
  project.save
end

unit = project.targets.find { |t| t.name == UNITTEST_NAME }

scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app, ui, launch_target: true)
if unit
  test_ref = Xcodeproj::XCScheme::TestAction::TestableReference.new(unit)
  scheme.test_action.add_testable(test_ref)
end
scheme.test_action.build_configuration = 'Debug'
scheme.save_as(PROJECT_PATH, SCHEME_NAME, true)

puts "Added #{UITEST_NAME} + #{UNITTEST_NAME} targets and #{SCHEME_NAME} scheme"