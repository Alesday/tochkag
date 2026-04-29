require 'xcodeproj'

project_path = 'tochkaG.xcodeproj'
project = Xcodeproj::Project.open(project_path)

old_bundle_id = 'com.tochkag.app.tunnel.wg'
new_bundle_id = 'com.tochkag.app.tunnelwg'

target = project.targets.find { |t| t.name == 'TochkaGTunnelWG' }

unless target
  puts "❌ Target TochkaGTunnelWG not found"
  exit 1
end

puts "Target: #{target.name}"

target.build_configurations.each do |config|
  current = config.build_settings['PRODUCT_BUNDLE_IDENTIFIER']
  puts "  Configuration #{config.name}: #{current}"
  if current == old_bundle_id
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = new_bundle_id
    puts "    → Changed to #{new_bundle_id}"
  end
end

project.save
puts "\n✅ Project saved"
