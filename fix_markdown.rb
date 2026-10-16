require 'find'

# Регексп ловит [текст](http://что-угодно) и оставляет только "текст"
pattern = /\[([^\]]+)\]\(http[^)]+\)/

fixed_files = []

Find.find('.') do |path|
  next unless path.end_with?('.swift', '.plist', '.json', '.entitlements')
  next if path.include?('/build/') || path.include?('/.spm-checkouts/') || path.include?('/SourcePackages/')
  next if path.include?('/DerivedData/')
  
  begin
    content = File.read(path)
    if content =~ pattern
      new_content = content.gsub(pattern, '\1')
      File.write(path, new_content)
      fixed_files << path
      puts "Fixed: #{path}"
    end
  rescue => e
    puts "Skipped #{path}: #{e.message}"
  end
end

puts "\nTotal files fixed: #{fixed_files.length}"
