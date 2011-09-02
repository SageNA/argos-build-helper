$:.unshift './lib' # force use of local rkelly

require_relative 'lib/docjs'

def is_interesting_file(file)
  file_name = File.basename(file).downcase
  return false if ['loader.js', 'require.js'].include? file_name
  file_name =~ /\.js$/i
end

inspector = DocJS::Inspectors::DojoAmdInspector.new()
meta = inspector.inspect_path('C:\Development\DojoSandbox', true) do |file| is_interesting_file(file) end

print meta
