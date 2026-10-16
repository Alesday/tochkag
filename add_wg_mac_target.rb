require 'xcodeproj'

NAME = 'TunnelMacWG'
BUNDLE = 'com.tochkag.app.mac.tunnelwg'
TEAM = '9ZZZ238P2J'

proj = Xcodeproj::Project.open('tochkaG.xcodeproj')
app  = proj.targets.find { |t| t.name == 'tochaGmac' } or abort 'нет таргета tochaGmac'
abort "таргет #{NAME} уже есть — нечего делать" if proj.targets.any? { |t| t.name == NAME }

t = proj.new_target(:app_extension, NAME, :osx, '13.5')

xcconfig = proj.main_group.new_file("#{NAME}/#{NAME}.xcconfig")
t.build_configurations.each do |c|
  c.base_configuration_reference = xcconfig
  c.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => BUNDLE,
    'PRODUCT_NAME'              => '$(TARGET_NAME)',
    'INFOPLIST_FILE'            => "#{NAME}/Info.plist",
    'GENERATE_INFOPLIST_FILE'   => 'YES',
    'CODE_SIGN_ENTITLEMENTS'    => "#{NAME}/#{NAME}.entitlements",
    'CODE_SIGN_STYLE'           => 'Automatic',
    'DEVELOPMENT_TEAM'          => TEAM,
    'SDKROOT'                   => 'macosx',
    'MACOSX_DEPLOYMENT_TARGET'  => '13.5',
    'SKIP_INSTALL'              => 'YES',
    'SWIFT_VERSION'             => '5.0',
    'CLANG_ENABLE_MODULES'      => 'YES',
    'ENABLE_APP_SANDBOX'        => 'YES',
    'ENABLE_HARDENED_RUNTIME'   => 'YES',
    'CURRENT_PROJECT_VERSION'   => '18',
    'MARKETING_VERSION'         => '1.0',
    'LD_RUNPATH_SEARCH_PATHS'   => ['$(inherited)',
                                    '@executable_path/../Frameworks',
                                    '@executable_path/../../../../Frameworks']
  )
end

group = proj.main_group.find_subpath(NAME, true)
group.set_source_tree('SOURCE_ROOT')

sources = Dir.glob("#{NAME}/**/*.swift") + Dir.glob("#{NAME}/WireGuardKitC/*.c")
sources.sort.each do |f|
  ref = group.new_file(f)
  t.add_file_references([ref])
  puts "  + #{f}"
end

app.add_dependency(t)

embed = app.copy_files_build_phases.find { |ph| ph.symbol_dst_subfolder_spec == :plug_ins }
unless embed
  embed = app.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.symbol_dst_subfolder_spec = :plug_ins
end
bf = embed.add_file_reference(t.product_reference)
bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

proj.save
puts "таргет #{NAME} создан, файлов: #{sources.size}"
