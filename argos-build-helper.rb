$:.unshift './lib' # force use of local rkelly

require_relative 'lib/docjs'

def is_interesting_file(file)
  file_name = File.basename(file).downcase
  return false if ['loader.js', 'require.js'].include? file_name
  file_name =~ /\.js$/i
end

def resolve_dependencies(mod, lookup)
  chain = []
  for import in mod.imports
    chain << resolve_dependencies(lookup[import], lookup) if lookup[import]
    chain << import
  end
  return chain
end

inspector = DocJS::Inspectors::DojoAmdInspector.new()
meta = inspector.inspect_path('C:\Development\DojoSandbox', true) do |file| is_interesting_file(file) end

module_lookup = {}

meta.modules do |mod|
  module_lookup[mod.name] = mod
end

locate = module_lookup['Sage/One']
resolved = resolve_dependencies(locate, module_lookup).flatten.uniq

print resolved

print meta
