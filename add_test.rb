require 'xcodeproj'
project = Xcodeproj::Project.open('OpenClip.xcodeproj')
test_target = project.targets.find { |t| t.name == 'OpenClipTests' }

project.files.select { |f| f.path == 'ActionRegistryTests.swift' || f.name == 'ActionRegistryTests.swift' }.each(&:remove_from_project)

tests_group = project.main_group.find_subpath('Tests/OpenClipTests', true)
ref = tests_group.new_file('Tests/OpenClipTests/ActionRegistryTests.swift')
ref.name = 'ActionRegistryTests.swift'
ref.source_tree = '<group>'

test_target.source_build_phase.add_file_reference(ref)

project.save
