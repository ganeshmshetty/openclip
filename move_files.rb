require 'xcodeproj'
project = Xcodeproj::Project.open('OpenClip.xcodeproj')
core_target = project.targets.find { |t| t.name == 'Core' }
openclip_target = project.targets.find { |t| t.name == 'OpenClip' }

files = ['CopyAction.swift', 'CutAction.swift', 'PasteAction.swift', 'SearchAction.swift', 'OpenURLAction.swift', 'ServicesAction.swift']

files.each do |f|
  bf = core_target.source_build_phase.files.find { |b| b.file_ref && (b.file_ref.name == f || b.file_ref.path == f) }
  if bf
    bf.file_ref.remove_from_project
  end
end

openclip_group = project.main_group.find_subpath('Sources/OpenClip', true)
platform_group = openclip_group.find_subpath('Platform', true)
builtin_group = platform_group.find_subpath('BuiltinActions', true)

files.each do |f|
  file_path = "Sources/OpenClip/Platform/BuiltinActions/#{f}"
  ref = builtin_group.new_file(file_path)
  openclip_target.source_build_phase.add_file_reference(ref)
end

project.save
