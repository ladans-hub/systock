require 'xcodeproj'

project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
runner = project.targets.find { |target| target.name == 'Runner' }
raise 'Runner target not found' unless runner

runner.build_configurations.each do |configuration|
  next unless configuration.name == 'Release'

  settings = configuration.build_settings
  settings['CODE_SIGN_STYLE'] = 'Manual'
  settings['CODE_SIGN_IDENTITY'] = 'Apple Distribution'
  settings['DEVELOPMENT_TEAM'] = ENV.fetch('IOS_TEAM_ID')
  settings['PROVISIONING_PROFILE_SPECIFIER'] = ENV.fetch('IOS_PROFILE_UUID')
end
project.save
