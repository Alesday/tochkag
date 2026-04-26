require 'xcodeproj'

project_path = 'tochkaG.xcodeproj'
project = Xcodeproj::Project.open(project_path)

framework_name = 'Libbox.xcframework'

# Таргеты, которые НЕ должны embedding-ить фреймворк (extensions)
extension_targets = ['TochkaGTunnel', 'TochkaGTunnelWG']

# Главное приложение — должно embedding-ить
main_target = 'tochkaG'

project.targets.each do |target|
  puts "\n=== Target: #{target.name} (type: #{target.product_type}) ==="

  # Ищем Embed Frameworks фазу
  embed_phase = target.copy_files_build_phases.find do |phase|
    phase.symbol_dst_subfolder_spec == :frameworks ||
    phase.name == 'Embed Frameworks' ||
    phase.name == 'Embed Foundation Extensions'
  end

  if embed_phase.nil?
    puts "  No Embed Frameworks phase found"
    next
  end

  # Ищем Libbox.xcframework в этой фазе
  libbox_file = embed_phase.files.find do |f|
    f.display_name && f.display_name.include?('Libbox')
  end

  if libbox_file.nil?
    puts "  Libbox not found in Embed phase"
    next
  end

  if extension_targets.include?(target.name)
    # Удаляем из Embed phase у расширений
    puts "  REMOVING Libbox from Embed Frameworks (extension)"
    embed_phase.remove_build_file(libbox_file)
  elsif target.name == main_target
    # Убеждаемся, что в главном таргете стоит Code Sign On Copy
    puts "  KEEPING Libbox in Embed Frameworks (main app)"
    libbox_file.settings ||= {}
    libbox_file.settings['ATTRIBUTES'] = ['CodeSignOnCopy', 'RemoveHeadersOnCopy']
    puts "  Set CodeSignOnCopy"
  end
end

project.save
puts "\n✅ Project saved successfully"
