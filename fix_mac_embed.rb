require 'xcodeproj'

project = Xcodeproj::Project.open('tochkaG.xcodeproj')

mac_target = project.targets.find { |t| t.name == 'tochaGmac' }
unless mac_target
  puts "ERROR: tochaGmac target not found"
  exit 1
end

puts "Inspecting tochaGmac target..."

# 1. Удаляем dependency на TochkaGTunnelWG (если есть)
mac_target.dependencies.each do |dep|
  if dep.target && dep.target.name == 'TochkaGTunnelWG'
    puts "Removing target dependency: #{dep.target.name}"
    mac_target.dependencies.delete(dep)
  end
end

# 2. Проходим по всем build phases и удаляем ссылки на TochkaGTunnelWG
mac_target.build_phases.each do |phase|
  next unless phase.respond_to?(:files) && phase.files
  
  to_remove = []
  phase.files.each do |build_file|
    file_ref = build_file.file_ref
    next unless file_ref
    
    name = file_ref.path || file_ref.name || ''
    if name.include?('TochkaGTunnelWG')
      to_remove << build_file
      puts "Found TochkaGTunnelWG in phase '#{phase.display_name}': #{name}"
    end
  end
  
  to_remove.each do |bf|
    phase.files.delete(bf)
    puts "  -> Removed"
  end
end

project.save
puts "Done. Saved project."
