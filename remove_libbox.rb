require 'xcodeproj'

project_path = 'tochkaG.xcodeproj'
project = Xcodeproj::Project.open(project_path)

removed_count = 0

# Проходим по всем таргетам
project.targets.each do |target|
  puts "\n=== Target: #{target.name} ==="

  # 1. Удаляем из Embed Frameworks фаз
  target.copy_files_build_phases.each do |phase|
    phase.files.dup.each do |build_file|
      next unless build_file.display_name && build_file.display_name.include?('Libbox')
      puts "  REMOVING from Embed phase: #{build_file.display_name}"
      phase.remove_build_file(build_file)
      removed_count += 1
    end
  end

  # 2. Удаляем из Link Binary With Libraries
  target.frameworks_build_phase.files.dup.each do |build_file|
    next unless build_file.display_name && build_file.display_name.include?('Libbox')
    puts "  REMOVING from Link Binary: #{build_file.display_name}"
    target.frameworks_build_phase.remove_build_file(build_file)
    removed_count += 1
  end
end

# 3. Удаляем файловые ссылки на Libbox.xcframework из проекта
puts "\n=== Removing file references ==="
project.files.dup.each do |file_ref|
  next unless file_ref.path && file_ref.path.include?('Libbox')
  puts "  REMOVING file reference: #{file_ref.path}"
  file_ref.remove_from_project
  removed_count += 1
end

project.save
puts "\n✅ Project saved. Total removals: #{removed_count}"
