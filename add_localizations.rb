require 'xcodeproj'
project_path = 'StreetStamps.xcodeproj'
project = Xcodeproj::Project.open(project_path)
main_target = project.targets.find { |t| t.name == 'StreetStamps' }

Dir.glob('StreetStamps/*.lproj').each do |lproj_path|
  lproj_name = File.basename(lproj_path)
  strings_file = File.join(lproj_path, 'Localizable.strings')
  next unless File.exist?(strings_file)

  file_ref = project.main_group.find_file_by_path(strings_file)
  unless file_ref
    variant_group = project.main_group.find_subpath('Localizable.strings', true) ||
                    project.main_group.new_variant_group('Localizable.strings')
    file_ref = variant_group.new_reference(strings_file)
    main_target.resources_build_phase.add_file_reference(file_ref)
  end
end

project.save
puts "✅ Localizable.strings 已添加到项目"
