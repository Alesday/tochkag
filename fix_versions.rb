require 'xcodeproj'

project = Xcodeproj::Project.open('tochkaG.xcodeproj')

new_build = '5'
new_version = '1.0'

project.targets.each do |target|
  puts "Target: #{target.name}"
  target.build_configurations.each do |config|
    config.build_settings['CURRENT_PROJECT_VERSION'] = new_build
    config.build_settings['MARKETING_VERSION'] = new_version
    puts "  #{config.name}: build=#{new_build}, version=#{new_version}"
  end
end

project.save
puts "Done. All targets now have build #{new_build}"
