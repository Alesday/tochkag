require 'xcodeproj'

project = Xcodeproj::Project.open('tochkaG.xcodeproj')

mac_target = project.targets.find { |t| t.name == 'tochaGmac' }
unless mac_target
  puts "ERROR: tochaGmac target not found"
  exit 1
end

# Категория "Утилиты" — для VPN-приложений идеально подходит
category = 'public.app-category.utilities'

mac_target.build_configurations.each do |config|
  config.build_settings['INFOPLIST_KEY_LSApplicationCategoryType'] = category
  puts "#{config.name}: set LSApplicationCategoryType = #{category}"
end

project.save
puts "Done."
