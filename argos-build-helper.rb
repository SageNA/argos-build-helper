$:.unshift './lib' # force use of local rkelly

require 'trollop'
require_relative 'lib/docjs'

module Argos
  class ResolverContext
    attr_accessor :files,
                  :modules,
                  :aliases

    def initialize
      @files = {}
      @modules = {}
      @aliases = {}
    end
  end

  class BuildHelper
    attr_accessor :project_path,
                  :project_aliases,
                  :dojo_path,
                  :dojo_cache,
                  :dojo_is_local

    def initialize(options = {})
      @project_path = nil
      @project_aliases = nil
      @dojo_path = nil
      @dojo_cache = nil
      @dojo_compilation = nil

      options.each {|k,v| instance_variable_set "@#{k}", v} if options.is_a? Hash

      @dojo_is_local = @project_path.any? do |path|
        (File.expand_path(path).downcase == File.expand_path(@dojo_path).downcase)
      end if @project_path
    end

    def load_source_projects
      is_interesting_file = lambda do |file|
        return false if @dojo_is_local && (file =~ /\W+(dojo|dijit|dojox)\W+/i)
        file_name = File.basename(file)
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
        file_name = File.basename(file)
        return false if [].include? file_name
        return file_name =~ /(?<!uncompressed)\.js$/i
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

    def on_module_not_found(module_name, importing_module, context)
      raise "Could not find module with name '#{module_name}'." unless module_name =~ /^[\w-]+\?/i
    end

    def resolve_module(module_name, parent_module, context)
      print "original: #{module_name}\n"
      module_path = module_name.split('/')

      if module_path[0] == '.' || module_path[0] == '..'
        base_name = parent_module.name
        # root_name = context.aliases.rassoc(base_name)
        # base_name = root_name[0] unless root_name.nil?

        base_path = base_name.split('/').slice(0..-2)

        module_path.reverse!

        while ((segment = module_path.pop()))
          case segment
            when '.' then next
            when '..' then
              base_path.pop()
            else
              base_path << segment
          end
        end

        module_name = base_path.join('/')
      end
      print "resolved: #{module_name}\n"
      context.modules[module_name] || context.modules[context.aliases[module_name]]
    end

    def resolve_dependencies(imports, context)
      module_added = {}
      resolved = []

      depth = 0
      visit = lambda do |module_name, parent_module, visited|

        module_info = resolve_module(module_name, parent_module, context)

        print "#{depth}: visit: #{module_name}, actual: #{module_info ? module_info.name : 'none'}, imports: #{module_info ? module_info.imports : 'none'}\n"

        return on_module_not_found(module_name, parent_module, context) if module_info.nil?
        return if module_added[module_info.name]

        if module_info.imports.length > 0
          visited = {} if visited.nil?

          if visited[module_info.name]
            return
            raise "Circular dependency detected for '#{module_info.name}'."
          end

          visited[module_info.name] = true

          for import in module_info.imports
            import_type, import_name = import.split '!'
            import_name = import_type if import_name.nil?

            depth += 1
            visit.call(import_name, module_info, visited) if visit
            depth -= 1
          end
        end

        resolved << module_info.name

        module_added[module_info.name] = true

      end

      for import in imports
        import_type, import_name = import.split '!'
        import_name = import_type if import_name.nil?

        visit.call(import_name, nil, nil)
      end

      resolved
    end

    def run
      source_projects = load_source_projects
      dojo_project = load_dojo_project

      resolver_context = ResolverContext.new

      dojo_project.files.each do |project_file|
        project_file.modules.each do |module_info|
          # ignore all "compilations" unless explicitly allowed
          next if project_file.modules.length > 1 unless @dojo_compilation.include?(File.basename(project_file.path))

          existing_file = resolver_context.files[module_info.name]
          existing_module = resolver_context.modules[module_info.name]

          if existing_module.nil?
            resolver_context.files[module_info.name] = project_file
            resolver_context.modules[module_info.name] = module_info
          elsif project_file.modules.length >= existing_file.modules.length
            resolver_context.files[module_info.name] = project_file
            resolver_context.modules[module_info.name] = module_info
          else
            print "*** conflict ***\n"
            print "existing:\n"
            print "\tname: #{existing_module.name}\n"
            print "\tfile: #{existing_file.path}\n"
            print "\tmods: %s\n" % existing_file.modules.map {|mod| mod.name}.join(',')
            print "new:\n"
            print "\tname: #{module_info.name}\n"
            print "\tfile: #{project_file.path}\n"
            print "\tmods: %s\n" % project_file.modules.map {|mod| mod.name}.join(',')
            print "******\n"
          end
        end
      end

      resolver_context.modules['require'] = DocJS::Meta::Module.new('require')
      resolver_context.files['require'] = nil

      resolver_context.modules['exports'] = DocJS::Meta::Module.new('exports')
      resolver_context.files['exports'] = nil

      resolver_context.modules['module'] = DocJS::Meta::Module.new('module')
      resolver_context.files['module'] = nil

      resolver_context.modules['default'] = DocJS::Meta::Module.new('default')
      resolver_context.files['default'] = nil

      resolver_context.aliases["dojo"] = "dojo/main"
      resolver_context.aliases["dijit"] = "dijit/main"
      resolver_context.aliases["dojox"] = "dojox/main"

      resolver_context.files.each do |name,project_file|
        print "#{name} => #{project_file.path}\n" unless project_file.nil?
      end

      source_projects.each do |key,project|
        project.files.each do |project_file|
          project_file.modules.each do |module_info|
            resolver_context.files[module_info.name] = project_file
            resolver_context.modules[module_info.name] = module_info
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
      dojo_resolved = resolve_dependencies dojo_imports, resolver_context
      dojo_ordered = dojo_resolved.map {|resolved| resolver_context.files[resolved]}.select {|project_file| !project_file.nil?}
      dojo_ordered.uniq!

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
    opt :dojo_compilation, "dojo compilation", :type => :strings, :short => 'w', :required => false
  end

  Trollop::die :dojo_path, "must exist" unless File.exist?(options[:dojo_path])
  Trollop::die :project_path, "must exist" unless options[:project_path].all? {|path| File.exists?(path)}
  Trollop::die :project_aliases, "must exist for each path" unless options[:project_path].length == options[:project_aliases].length

  options
end

helper = Argos::BuildHelper.new(process_command_line)
helper.run


