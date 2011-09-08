$:.unshift './lib' # force use of local rkelly

require 'trollop'
require_relative 'lib/docjs'

module Argos
  class BuildHelper
    attr_accessor :project_path,
                  :project_aliases,
                  :dojo_path,
                  :dojo_cache,
                  :dojo_amd,
                  :dojo_amd_compatible,
                  :dojo_sizzle,
                  :dojo_is_local

    def initialize(options = {})
      @project_path = nil
      @project_aliases = nil
      @dojo_path = nil
      @dojo_cache = nil
      @dojo_amd = true
      @dojo_amd_compatible = true
      @dojo_sizzle = false
      @dojo_is_local = false

      options.each {|k,v| instance_variable_set "@#{k}", v} if options.is_a? Hash

      @dojo_is_local =  @project_path.any? do |path|
        (File.expand_path(path).downcase == File.expand_path(@dojo_path).downcase)
      end if @project_path
    end

    def load_source_projects
      is_interesting_file = lambda do |file|
        return false if @dojo_is_local && (file =~ /\W+(dojo|dijit|dojox)\W+/i)
        file_name = File.basename(file).downcase
        return false if ['loader.js', 'require.js'].include? file_name
        return file_name =~ /\.js$/i
      end

      projects = {}
      (@project_aliases.zip(@project_path)).each do |alias_and_path|
        inspector = DocJS::Inspectors::DojoAmdInspector.new()
        projects[alias_and_path[0]] = inspector.inspect_path(alias_and_path[1], true, &is_interesting_file)
      end

      projects
    end

    def load_dojo_project
      if @dojo_cache && File.exists?(@dojo_cache)
        return File.open(@dojo_cache) do |file|
          Marshal::load(file)
        end
      end

      is_interesting_file = lambda do |file|
        file_name = File.basename(file).downcase
        return file_name =~ /\.js$/i
      end

      inspector = DocJS::Inspectors::DojoAmdInspector.new()
      project = inspector.inspect_path(['dojo', 'dijit', 'dojox'].map {|path| "#{@dojo_path}/#{path}"}, true, &is_interesting_file)

      if @dojo_cache
        File.open(@dojo_cache, 'w') do |io|
          Marshal::dump(project, io)
        end
      end
      project
    end

    def resolve_dependencies_old(mod, lookup)
      chain = []
      for import in mod.imports
        chain << resolve_dependencies(lookup[import], lookup) if lookup[import]
        chain << import
      end
      chain
    end

    def on_module_not_found(name)
      raise "Could not find module with name '#{name}'."
    end

    def resolve_dependencies(imports, name_to_module)
      module_added = {}
      resolved = []

      visit = lambda do |name,visited|
        module_info = name_to_module[name]

        # print "#{depth}: visit: #{name}, actual: #{module_info ? module_info.name : 'none'}, imports: #{module_info ? module_info.imports : 'none'}\n"

        return on_module_not_found(name) if module_info.nil?
        return if module_added[module_info.name]

        if module_info.imports.length > 0
          visited = {} if visited.nil?

          if visited[module_info.name]
            raise "Circular dependency detected for '#{module_info.name}'."
          end

          visited[module_info.name] = true

          for import in module_info.imports
            import_type, import_name = import.split '!'
            import_name = import_type if import_name.nil?

            visit.call(import_name, visited) if visit
          end
        end

        resolved << module_info.name

        module_added[module_info.name] = true

      end

      for import in imports
        import_type, import_name = import.split '!'
        import_name = import_type if import_name.nil?

        visit.call(import_name, nil)
      end

      resolved
    end

    def run
      source_projects = load_source_projects
      dojo_project = load_dojo_project

      name_to_module = {}
      name_to_file = {}

      dojo_project.files.each do |project_file|
        next if project_file.path =~ /dojo\/_base\/_loader\/loader\.js$/i # always skip (provides stub modules)
        next if project_file.path =~ /dojo\/lib\/kernel\.js$/i unless not @dojo_amd_compatible
        next if project_file.path =~ /dojo\/lib\/backCompat\.js$/i unless not @dojo_amd_compatible
        next if project_file.path =~ /dojo\/_base\/query\.js/i unless not @dojo_sizzle
        next if project_file.path =~ /dojo\/_base\/query-sizzle\.js/i unless @dojo_sizzle

        project_file.modules.each do |module_info|
          if name_to_module[module_info.name]
            # todo: find conflicts for kernel and main-browser
            print "*** conflict ***\n"
            print "existing:\n"
            print "\tname: #{name_to_module[module_info.name].name}\n"
            print "\tfile: #{name_to_file[module_info.name].path}\n"
            print "\tmods: %s\n" % name_to_file[module_info.name].modules.map {|mod| mod.name}.join(',')
            print "new:\n"
            print "\tname: #{module_info.name}\n"
            print "\tfile: #{project_file.path}\n"
            print "\tmods: %s\n" % project_file.modules.map {|mod| mod.name}.join(',')
            print "******\n"
            next
          end

          name_to_module[module_info.name] = module_info
          name_to_file[module_info.name] = project_file
        end
      end

      if @dojo_amd
        # the dijit module (dijit/lib/main.js) is an anonymous module
        # re-associate it appropriately (an AMD loader would do this)
        name_to_module["dijit"] = name_to_module["dijit/lib/main"]
        name_to_file["dijit"] = name_to_file["dijit/lib/main"]
      end

      if @dojo_amd_compatible
        # compatible AMD requires a couple of dependency changes since it uses a compatible shim
        # that exposes module stubs (not the real modules)
        # bootstrap >> loader >> host
        kernel_module = DocJS::Meta::Module.new("dojo/lib/kernel")
        kernel_module.imports << "dojo/_base/_loader/hostenv_browser"
        compat_module = DocJS::Meta::Module.new("dojo/lib/backCompat")
        compat_module.imports << "dojo/_base/_loader/bootstrap"
        compat_module.imports << "require"
        loader_module = DocJS::Meta::Module.new("require")
        loader_file = dojo_project.files.find {|project_file| project_file.path =~ /dojo\/_base\/_loader\/loader\.js$/i}

        name_to_module[kernel_module.name] = kernel_module
        name_to_file[kernel_module.name] = nil # no file in AMD compatible mode

        name_to_module[compat_module.name] = compat_module
        name_to_file[compat_module.name] = nil # no file in AMD compatible mode

        name_to_module[loader_module.name] = loader_module
        name_to_file[loader_module.name] = loader_file

        # since we are in a compatible AMD mode, we do not want the original anonymous dijit module
        name_to_file["dijit/lib/main"] = nil # no file in AMD compatible mode
      end

      source_projects.each do |key,project|
        project.files.each do |project_file|
          project_file.modules.each do |module_info|
            name_to_module[module_info.name] = module_info
            name_to_file[module_info.name] = project_file
          end
        end
      end

      dojo_imports = []
      source_projects.each do |key,project|
        dojo_imports << project.modules.flat_map {|mod|
          mod.imports.select {|import| import =~ /^(dojo|dijit|dojox)(\W+|$)/i}
        }
      end

      dojo_imports.flatten!.uniq!
      dojo_resolved = resolve_dependencies dojo_imports, name_to_module
      dojo_ordered = dojo_resolved.map {|resolved| name_to_file[resolved]}.select {|project_file| !project_file.nil?}

      print "build order:\n"
      dojo_ordered.each {|project_file| print "#{project_file.path}\n"}
    end
  end
end

def process_command_line
  options = Trollop::options do
    opt :project_path, "project path", :type => :strings, :short => 'p', :required => true
    opt :project_aliases, "project aliases", :type => :strings, :short => 'a', :required => true
    opt :dojo_path, "dojo path", :type => :string, :short => 'd', :required => true
    opt :dojo_cache, "dojo cache", :type => :string, :short => 'c', :required => false
    opt :dojo_amd, "dojo amd", :type => :bool, :default => true
    opt :dojo_amd_compatible, "dojo amd compatible", :type => :bool, :default => true
    opt :dojo_sizzle, "dojo sizzle", :type => :bool, :default => false # not compatible with AMD right now
  end

  Trollop::die :project_path, "must exist" unless options[:project_path].all? {|path| File.exists?(path)}
  Trollop::die :project_aliases, "must exist for each path" unless options[:project_path].length == options[:project_aliases].length
  Trollop::die :dojo_path, "must exist" unless File.exist?(options[:dojo_path])

  options
end

helper = Argos::BuildHelper.new(process_command_line)
helper.run


