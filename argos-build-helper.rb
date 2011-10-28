$:.unshift './lib' # force use of local rkelly

require 'trollop'
require 'json'
require 'pathname'
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
    attr_accessor :base_path,
                  :config

    def initialize(path, config)
      @base_path = Pathname.new(path || ".")
      @config = config
    end

    def load_source_projects
      dojo_is_local = @config["projects"].map {|project| project["path"]}.any? do |path|
        (File.expand_path(@base_path + path).downcase == File.expand_path(@base_path + @config["dojoPath"]).downcase)
      end

      is_interesting_file = lambda do |file|
        return false if dojo_is_local && (file =~ /\W+(dojo|dijit|dojox)\W+/i)
        file_name = File.basename(file)
        return file_name =~ /\.js$/i
      end

      projects = {}

      @config["projects"].each do |project|
        inspector = DocJS::Inspectors::DojoAmdInspector.new()
        projects[project["alias"]] = inspector.inspect_path(@base_path + project["path"], true, &is_interesting_file)
      end

      projects
    end

    def load_dojo_project
      dojo_path = @base_path + @config["dojoPath"]
      dojo_cache = @base_path + @config["dojoCache"] if @config["dojoCache"]

      return File.open(dojo_cache) {|file| Marshal::load(file)} if dojo_cache && File.exists?(dojo_cache)

      is_interesting_file = lambda do |file|
        file_name = File.basename(file)
        return false if [].include? file_name
        return file_name =~ /(?<!uncompressed)\.js$/i
      end

      inspector = DocJS::Inspectors::DojoAmdInspector.new()
      project = inspector.inspect_path(["dojo", "dijit", "dojox"].map {|path| dojo_path + path}, true, &is_interesting_file)

      File.open(dojo_cache, 'w') {|file| Marshal::dump(project, file)} if dojo_cache

      project
    end

    def on_module_not_found(module_name, importing_module, context)
      raise "Could not find module with name '#{module_name}'." unless module_name =~ /^[\w-]+\?/i
    end

    def resolve_module(module_name, parent_module, context)
      module_path = module_name.split('/')

      if module_path[0] == '.' || module_path[0] == '..'
        base_name = parent_module.name
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

      context.modules[module_name] || context.modules[context.aliases[module_name]]
    end

    def resolve_dependencies(imports, context, &include)
      module_added = {}
      resolved = []

      depth = 0
      visit = lambda do |module_name, parent_module, visited|

        module_info = resolve_module(module_name, parent_module, context)

        # print "#{depth}: visit: #{module_name}, actual: #{module_info ? module_info.name : 'none'}, imports: #{module_info ? module_info.imports : 'none'}\n"

        return on_module_not_found(module_name, parent_module, context) if module_info.nil?
        return if block_given? && !include.call(module_name, module_info, parent_module, context)
        return if module_added[module_info.name]

        if module_info.imports && module_info.imports.length > 0
          visited = {} if visited.nil?

          if visited[module_info.name]
            # raise "Circular dependency detected for '#{module_info.name}'."
            return
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

      dojo_compilation = @config["dojoCompilation"] || []
      resolver_context = ResolverContext.new

      dojo_project.files.each do |project_file|
        project_file.modules.each do |module_info|
          # ignore all "compilations" unless explicitly allowed
          next if project_file.modules.length > 1 unless dojo_compilation.include?(File.basename(project_file.path))

          existing_file = resolver_context.files[module_info.name]
          existing_module = resolver_context.modules[module_info.name]

          if existing_module.nil?
            resolver_context.files[module_info.name] = project_file
            resolver_context.modules[module_info.name] = module_info
          elsif project_file.modules.length >= existing_file.modules.length
            resolver_context.files[module_info.name] = project_file
            resolver_context.modules[module_info.name] = module_info
          else
            print "*** potential conflict ***\n"
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
          mod.imports.select {|import| import =~ /^(dojo|dijit|dojox)(\W+|$)/i} unless mod.imports.nil?
        }
      end

      create_build_projects source_projects, resolver_context
    end

    def create_build_projects(source_projects, resolver_context)
      for project in @config["projects"]
        template_path = @base_path + project["templatePath"]
        output_path = @base_path + project["outputPath"]

        next unless File.exists? template_path

        build_project = JSON.parse(File.read(template_path))

        build_project["pkgs"] << create_build_package(project, source_projects[project["alias"]], resolver_context)
        build_project["pkgs"] << create_dojo_package(project, source_projects, resolver_context) if project["includeDojo"]

        File.open(output_path, 'w') do |file|
          file.write(JSON.pretty_generate(build_project))
        end
      end
    end

    def create_build_package(project, source_project, resolver_context)
      modules = Hash[*source_project.modules.flat_map {|info| [info.name, info]}.flatten]
      resolved = resolve_dependencies(modules.keys, resolver_context) {|name,info| modules[info.name]}
      ordered = resolved.map {|name| resolver_context.files[name]}.select {|file| !file.nil?}.uniq

      package_base_path = @base_path + File.dirname(project["outputPath"])
      package_includes = []

      for project_file in ordered
        include_path = Pathname.new(File.dirname(project_file.path))
        package_includes << {
            "text" => File.basename(project_file.path),
            "path" => include_path.relative_path_from(package_base_path).to_s
        }
      end

      {
        "name" => project["name"],
        "file" => project["deployAs"],
        "isDebug" => true,
        "fileIncludes" => package_includes
      }
    end

    def create_dojo_package(project, source_projects, resolver_context)
      modules = source_projects.values.flat_map {|source_project|
        source_project.modules.flat_map {|info|
          (info.imports && info.imports.select {|import| import =~ /^(dojo|dijit|dojox)(\W+|$)/i}) || []
        }
      }.uniq

      resolved = resolve_dependencies modules, resolver_context
      ordered = resolved.map {|name| resolver_context.files[name]}.select {|file| !file.nil?}.uniq

      package_base_path = @base_path + File.dirname(project["outputPath"])
      package_includes = []

      for project_file in ordered
        include_path = Pathname.new(File.dirname(project_file.path))
        package_includes << {
            "text" => File.basename(project_file.path),
            "path" => include_path.relative_path_from(package_base_path).to_s
        }
      end

      {
        "name" => project["includeDojo"]["name"],
        "file" => project["includeDojo"]["deployAs"],
        "isDebug" => true,
        "fileIncludes" => package_includes
      }
    end
  end
end

def process_command_line
  options = Trollop::options do
    version "Argos Build Helper v1.0-alpha"
    banner <<-EOS
Argos Build Helper assists in the generation of build projects (jsb2) files
by analyzing the source of an Argos SDK based application in order to determine
dependencies and build order.

Usage:
        ruby argos-build-helper.rb [options]

Options:
EOS
    opt :base_path, "base path for all paths specified in the configuration file", :type => :string, :short => "p", :required => true
    opt :config_path, "configuration file path", :type => :string, :short => "c", :required => true
  end

  Trollop::die :base_path, "must exist" unless File.exist? options[:base_path]
  Trollop::die :config_path, "must exist" unless File.exist? options[:config_path]

  options
end

options = process_command_line
config = JSON.parse(File.read(options[:config_path]))
helper = Argos::BuildHelper.new(options[:base_path], config)
helper.run


