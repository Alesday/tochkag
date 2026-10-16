require 'xcodeproj'

project = Xcodeproj::Project.open('tochkaG.xcodeproj')

# Находим максимальный текущий build number
max_build = 0
project.targets.each do |target|
  target.build_configurations.each do |config|
    current = config.build_settings['CURRENT_PROJECT_VERSION']
    max_build = current.to_i if current && current.to_i > max_build
  end
end

new_build = (max_build + 1).to_s
puts "Current max build: #{max_build}"
puts "New build: #{new_build}"

# Устанавливаем новый build number для всех таргетов
project.targets.each do |target|
  target.build_configurations.each do |config|
    if config.build_settings['CURRENT_PROJECT_VERSION']
      old = config.build_settings['CURRENT_PROJECT_VERSION']
      config.build_settings['CURRENT_PROJECT_VERSION'] = new_build
      puts "#{target.name} (#{config.name}): #{old} → #{new_build}"
    end
  end
end

project.save
puts "\n✅ Build number set to #{new_build}"
