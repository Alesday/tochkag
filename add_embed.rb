require 'xcodeproj'

project_path = 'tochkaG.xcodeproj'
project = Xcodeproj::Project.open(project_path)

main_target = project.targets.find { |t| t.name == 'tochkaG' }

unless main_target
  puts "❌ Main target tochkaG not found"
  exit 1
end

# Найдём Libbox.xcframework в файлах проекта
libbox_ref = project.files.find do |f|
  f.path && f.path.include?('Libbox.xcframework')
end

unless libbox_ref
  puts "❌ Libbox.xcframework not found in project files"
  puts "Available xcframeworks:"
  project.files.each do |f|
    puts "  - #{f.path}" if f.path && f.path.include?('xcframework')
  end
  exit 1
end

puts "Found Libbox at: #{libbox_ref.path}"

# Проверим, что он линкуется в главном таргете
link_phase = main_target.frameworks_build_phase
already_linked = link_phase.files.any? { |f| f.file_ref == libbox_ref }

unless already_linked
  puts "Adding to Link Binary With Libraries..."
  link_phase.add_file_reference(libbox_ref)
end

# Найдём или создадим Embed Frameworks фазу
embed_phase = main_target.copy_files_build_phases.find do |phase|
  phase.symbol_dst_subfolder_spec == :frameworks
end

if embed_phase.nil?
  puts "Creating Embed Frameworks phase..."
  embed_phase = main_target.new_copy_files_build_phase('Embed Frameworks')
  embed_phase.symbol_dst_subfolder_spec = :frameworks
end

# Проверим, что Libbox ещё не в embed phase
already_embedded = embed_phase.files.any? { |f| f.file_ref == libbox_ref }

if already_embedded
  puts "Libbox already in Embed phase, ensuring CodeSignOnCopy..."
  embed_file = embed_phase.files.find { |f| f.file_ref == libbox_ref }
  embed_file.settings ||= {}
  embed_file.settings['ATTRIBUTES'] = ['CodeSignOnCopy', 'RemoveHeadersOnCopy']
else
  puts "Adding Libbox to Embed Frameworks with CodeSignOnCopy..."
  embed_file = embed_phase.add_file_reference(libbox_ref)
  embed_file.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }
end

project.save
puts "\n✅ Project saved successfully"
puts "Main target now embeds Libbox.xcframework with code signing"
