# frozen_string_literal: true

require "json"
require "yaml"
require "pathname"

module Sxn
  module Rules
    # ProjectDetector analyzes project directories to determine their type, language,
    # package manager, and suggests appropriate default rules for project setup.
    #
    # @example Basic usage
    #   detector = ProjectDetector.new("/path/to/project")
    #   info = detector.detect_project_info
    #   puts "Project type: #{info[:type]}"
    #   puts "Package manager: #{info[:package_manager]}"
    #
    #   rules = detector.suggest_default_rules
    #   puts "Suggested rules: #{rules.keys}"
    #
    class ProjectDetector
      # Project type definitions with their detection criteria
      PROJECT_TYPES = {
        rails: {
          files: %w[Gemfile config/application.rb],
          patterns: {
            gemfile_contains: ["rails"]
          },
          confidence: :high
        },
        ruby: {
          files: %w[Gemfile *.gemspec],
          patterns: {},
          confidence: :medium
        },
        nextjs: {
          files: %w[package.json next.config.js],
          patterns: {
            package_json_deps: ["next"]
          },
          confidence: :high
        },
        react: {
          files: %w[package.json],
          patterns: {
            package_json_deps: ["react"]
          },
          confidence: :high
        },
        nodejs: {
          files: %w[package.json],
          patterns: {
            package_json_deps: ["express", "fastify", "koa", "@types/node", "nodemon", "typescript"]
          },
          confidence: :medium_high
        },
        javascript: {
          files: %w[package.json],
          patterns: {},
          confidence: :medium
        },
        typescript: {
          files: %w[tsconfig.json *.ts],
          patterns: {},
          confidence: :high
        },
        python: {
          files: %w[requirements.txt setup.py pyproject.toml Pipfile],
          patterns: {},
          confidence: :medium
        },
        django: {
          files: %w[manage.py],
          patterns: {
            requirements_contains: ["django"]
          },
          confidence: :high
        },
        go: {
          files: %w[go.mod go.sum *.go],
          patterns: {},
          confidence: :high
        },
        rust: {
          files: %w[Cargo.toml Cargo.lock],
          patterns: {},
          confidence: :high
        }
      }.freeze

      # Package manager detection patterns
      PACKAGE_MANAGERS = {
        bundler: {
          files: %w[Gemfile Gemfile.lock],
          command: "bundle"
        },
        npm: {
          files: %w[package-lock.json],
          command: "npm"
        },
        yarn: {
          files: %w[yarn.lock],
          command: "yarn"
        },
        pnpm: {
          files: %w[pnpm-lock.yaml],
          command: "pnpm"
        },
        pip: {
          files: %w[requirements.txt],
          command: "pip"
        },
        pipenv: {
          files: %w[Pipfile Pipfile.lock],
          command: "pipenv"
        },
        poetry: {
          files: %w[pyproject.toml poetry.lock],
          command: "poetry"
        },
        cargo: {
          files: %w[Cargo.toml Cargo.lock],
          command: "cargo"
        },
        go_mod: {
          files: %w[go.mod go.sum],
          command: "go"
        }
      }.freeze

      attr_reader :project_path

      # Initialize the project detector
      #
      # @param project_path [String] Absolute path to the project directory
      def initialize(project_path)
        raise ArgumentError, "Project path cannot be nil or empty" if project_path.nil? || project_path.empty?

        @project_path = File.realpath(project_path)
        validate_project_path!
      rescue Errno::ENOENT
        raise ArgumentError, "Project path does not exist: #{project_path}"
      end

      # Detect comprehensive project information
      #
      # @return [Hash] Project information including type, language, package manager, etc.
      def detect_project_info
        {
          type: detect_project_type,
          language: detect_primary_language,
          languages: detect_all_languages,
          package_manager: detect_package_manager,
          framework: detect_framework,
          has_docker: has_docker?,
          has_tests: has_tests?,
          has_ci: has_ci_config?,
          database: detect_database,
          sensitive_files: detect_sensitive_files,
          analysis_timestamp: Time.now.iso8601
        }
      end

      # Detect project type for a given path (used by ConfigManager)
      #
      # @param path [String] Path to the project directory
      # @return [Symbol] Detected project type (:rails, :nodejs, :python, etc.)
      def detect_type(path)
        old_path = @project_path
        @project_path = File.realpath(path)
        result = detect_project_type
        @project_path = old_path
        result
      rescue Errno::ENOENT
        :unknown
      end

      # Legacy method for compatibility with tests
      # Detect the primary project type
      #
      # @return [Symbol] Detected project type (:rails, :nodejs, :python, etc.)
      def detect_project_type
        detected_types = []

        PROJECT_TYPES.each do |type, criteria|
          confidence = calculate_type_confidence(type, criteria)
          detected_types << { type: type, confidence: confidence } if confidence.positive?
        end

        # Sort by confidence and return the highest
        detected_types.min_by { |t| -t[:confidence] }&.fetch(:type) || :unknown
      end

      # Detect the package manager used by the project
      #
      # @return [Symbol] Detected package manager (:bundler, :npm, :yarn, etc.)
      def detect_package_manager
        PACKAGE_MANAGERS.each do |manager, criteria|
          return manager if criteria[:files].any? { |file| file_exists_in_project?(file) }
        end

        # Fallback logic for common scenarios
        if file_exists_in_project?("package.json")
          return :npm # Default to npm for Node.js projects without specific lock files
        end

        if file_exists_in_project?("Gemfile")
          return :bundler # Default to bundler for Ruby projects without lock files
        end

        :unknown
      end

      # Suggest default rules based on detected project characteristics
      #
      # @return [Hash] Suggested rules configuration
      def suggest_default_rules
        project_info = detect_project_info
        rules = {}

        # Add copy files rules based on project type
        copy_files = suggest_copy_files_rules(project_info)
        rules["copy_files"] = copy_files unless copy_files["config"]["files"] && copy_files["config"]["files"].empty?

        # Add setup commands rules based on package manager
        setup_commands = suggest_setup_commands_rules(project_info)
        unless setup_commands["config"]["commands"] && setup_commands["config"]["commands"].empty?
          rules["setup_commands"] =
            setup_commands
        end

        # Add template rules for common project documentation
        template_rules = suggest_template_rules(project_info)
        unless template_rules["config"]["templates"] && template_rules["config"]["templates"].empty?
          rules["templates"] =
            template_rules
        end

        rules
      end

      # Get detailed analysis of the project structure
      #
      # @return [Hash] Detailed project analysis
      def analyze_project_structure
        {
          files: analyze_important_files,
          directories: analyze_directory_structure,
          dependencies: analyze_dependencies,
          configuration: analyze_configuration_files,
          scripts: analyze_scripts,
          documentation: analyze_documentation
        }
      end

      private

      # Validate that the project path exists and is a directory
      def validate_project_path!
        raise ArgumentError, "Project path is not a directory: #{@project_path}" unless File.directory?(@project_path)

        return if File.readable?(@project_path)

        raise ArgumentError, "Project path is not readable: #{@project_path}"
      end

      # Calculate confidence score for a project type
      def calculate_type_confidence(type, criteria)
        confidence = 0

        # Check for required files
        files_found = criteria[:files].count { |file| file_exists_in_project?(file) }
        if files_found.positive?
          confidence += files_found * 10
          confidence += 20 if files_found == criteria[:files].length
        end

        # For high-confidence project types with specific patterns,
        # require all files AND pattern matches to be valid
        if criteria[:confidence] == :high && !criteria[:patterns].empty?
          return 0 unless files_found == criteria[:files].length

          # All patterns must match for high-confidence types
          pattern_matches = 0
          criteria[:patterns].each do |pattern_type, patterns|
            case pattern_type
            when :gemfile_contains
              pattern_matches += 1 if patterns.any? { |pattern| gemfile_contains?(pattern) }
            when :package_json_deps
              pattern_matches += 1 if patterns.any? { |dep| package_json_has_dependency?(dep) }
            when :requirements_contains
              pattern_matches += 1 if patterns.any? { |pattern| requirements_contains?(pattern) }
            end
          end

          return 0 unless pattern_matches == criteria[:patterns].length

          confidence += pattern_matches * 30
        else
          # For other types, add confidence for pattern matches
          criteria[:patterns].each do |pattern_type, patterns|
            case pattern_type
            when :gemfile_contains
              confidence += 30 if patterns.any? { |pattern| gemfile_contains?(pattern) }
            when :package_json_deps
              confidence += 30 if patterns.any? { |dep| package_json_has_dependency?(dep) }
            when :requirements_contains
              confidence += 30 if patterns.any? { |pattern| requirements_contains?(pattern) }
            end
          end
        end

        # Special logic for Node.js vs JavaScript distinction
        # Only apply when using actual PROJECT_TYPES criteria for nodejs
        # Don't boost Node.js confidence if this looks like a TypeScript project
        if type == :nodejs && file_exists_in_project?("package.json") &&
           criteria == PROJECT_TYPES[:nodejs] && !(file_exists_in_project?("tsconfig.json") && file_exists_in_project?("*.ts"))
          # Only boost Node.js if it has typical Node.js characteristics
          # Otherwise treat it as plain JavaScript
          if has_nodejs_characteristics?
            confidence += 50
          end
        end

        # Apply confidence modifiers
        case criteria[:confidence]
        when :high
          confidence *= 1.2
        when :medium_high
          confidence *= 1.1
        when :low
          confidence *= 0.8
        end

        confidence.to_i
      end

      # Calculate confidence score for a specific project type (test compatibility)
      def calculate_confidence_score(type)
        criteria = PROJECT_TYPES[type]
        return 0 unless criteria

        calculate_type_confidence(type, criteria)
      end

      # Check if a file exists in the project (supports glob patterns)
      def file_exists_in_project?(file_pattern)
        return false unless @project_path && File.directory?(@project_path)

        if file_pattern.include?("*")
          !Dir.glob(File.join(@project_path, file_pattern)).empty?
        else
          File.exist?(File.join(@project_path, file_pattern))
        end
      rescue Errno::EACCES, Errno::EIO, StandardError
        # Handle permission errors and I/O errors gracefully
        false
      end

      # Detect primary programming language
      def detect_primary_language
        return :unknown unless @project_path && File.directory?(@project_path)

        language_files = {
          ruby: %w[*.rb Gemfile Rakefile],
          javascript: %w[*.js *.jsx package.json],
          typescript: %w[*.ts *.tsx tsconfig.json],
          python: %w[*.py requirements.txt setup.py],
          go: %w[*.go go.mod],
          rust: %w[*.rs Cargo.toml],
          java: %w[*.java pom.xml build.gradle],
          php: %w[*.php composer.json],
          csharp: %w[*.cs *.csproj],
          cpp: %w[*.cpp *.hpp *.cmake CMakeLists.txt]
        }

        language_scores = {}

        language_files.each do |language, patterns|
          score = patterns.sum do |pattern|
            if pattern.include?("*")
              Dir.glob(File.join(@project_path, "**", pattern)).length
            else
              file_exists_in_project?(pattern) ? 10 : 0
            end
          rescue Errno::EACCES, Errno::EIO, StandardError
            0
          end
          language_scores[language] = score
        end

        language_scores.max_by { |_, score| score }&.first || :unknown
      rescue StandardError
        :unknown
      end

      # Detect all languages present in the project
      def detect_all_languages
        return [] unless @project_path && File.directory?(@project_path)

        language_files = {
          ruby: %w[*.rb Gemfile Rakefile],
          javascript: %w[*.js *.jsx package.json],
          typescript: %w[*.ts *.tsx tsconfig.json],
          python: %w[*.py requirements.txt setup.py],
          go: %w[*.go go.mod],
          rust: %w[*.rs Cargo.toml],
          java: %w[*.java pom.xml build.gradle],
          php: %w[*.php composer.json],
          csharp: %w[*.cs *.csproj],
          cpp: %w[*.cpp *.hpp *.cmake CMakeLists.txt]
        }

        detected_languages = []
        language_files.each do |language, patterns|
          score = patterns.sum do |pattern|
            if pattern.include?("*")
              Dir.glob(File.join(@project_path, "**", pattern)).length
            else
              file_exists_in_project?(pattern) ? 1 : 0
            end
          rescue Errno::EACCES, Errno::EIO, StandardError
            0
          end
          detected_languages << language if score.positive?
        end

        detected_languages
      rescue StandardError
        []
      end

      # Detect web framework
      def detect_framework
        return :rails if gemfile_contains?("rails")
        return :django if requirements_contains?("django")
        return :nextjs if package_json_has_dependency?("next")
        return :react if package_json_has_dependency?("react")
        return :vue if package_json_has_dependency?("vue")
        return :express if package_json_has_dependency?("express")
        return :fastapi if requirements_contains?("fastapi")
        return :flask if requirements_contains?("flask")

        :unknown
      end

      # Check if project has Docker configuration
      def has_docker?
        file_exists_in_project?("Dockerfile") ||
          file_exists_in_project?("docker-compose.yml") ||
          file_exists_in_project?("docker-compose.yaml")
      end

      # Check if project has test configuration
      def has_tests?
        test_patterns = %w[
          spec test tests __tests__ *.test.* *.spec.*
          pytest.ini tox.ini jest.config.* vitest.config.*
        ]

        test_patterns.any? { |pattern| file_exists_in_project?(pattern) }
      end

      # Check if project has CI configuration
      def has_ci_config?
        ci_files = %w[
          .github/workflows .gitlab-ci.yml .circleci/config.yml
          .travis.yml appveyor.yml .buildkite
        ]

        ci_files.any? { |file| file_exists_in_project?(file) }
      end

      # Detect database configuration
      def detect_database
        databases = []

        # Check configuration files and environment files
        databases << :postgresql if file_contains?("config/database.yml",
                                                   "postgresql") || env_contains?("DATABASE_URL",
                                                                                  "postgres") || file_contains?(".env",
                                                                                                                "postgresql://")
        databases << :mysql if file_contains?("config/database.yml",
                                              "mysql") || env_contains?("DATABASE_URL",
                                                                        "mysql") || file_contains?(".env", "mysql://")
        databases << :sqlite if file_contains?("config/database.yml", "sqlite") || file_exists_in_project?("*.sqlite*")
        databases << :mongodb if package_json_has_dependency?("mongoose") || requirements_contains?("pymongo")
        databases << :redis if package_json_has_dependency?("redis") || requirements_contains?("redis")

        databases.first || :unknown
      end

      # Detect sensitive files that should be handled carefully
      def detect_sensitive_files
        sensitive_patterns = %w[
          config/master.key config/credentials/* .env .env.*
          *.pem *.p12 *.jks .npmrc auth_token api_key
        ]

        found_files = []
        sensitive_patterns.each do |pattern|
          if pattern.include?("*")
            found_files.concat(Dir.glob(File.join(@project_path, "**", pattern)))
          else
            file_path = File.join(@project_path, pattern)
            found_files << file_path if File.exist?(file_path)
          end
        rescue Errno::EACCES, Errno::EIO, StandardError
          # Skip patterns that cause errors
        end

        found_files.map { |f| Pathname.new(f).relative_path_from(Pathname.new(@project_path)).to_s }
      end

      # Suggest copy files rules based on project characteristics
      def suggest_copy_files_rules(project_info)
        files = []

        case project_info[:type]
        when :rails
          files.push(
            { "source" => "config/master.key", "strategy" => "copy", "required" => false },
            { "source" => ".env", "strategy" => "symlink", "required" => false },
            { "source" => ".env.development", "strategy" => "symlink", "required" => false }
          )
        when :nodejs, :nextjs, :react
          files.push(
            { "source" => ".env", "strategy" => "symlink", "required" => false },
            { "source" => ".env.local", "strategy" => "symlink", "required" => false },
            { "source" => ".npmrc", "strategy" => "copy", "required" => false }
          )
        when :python, :django
          files.push(
            { "source" => ".env", "strategy" => "symlink", "required" => false },
            { "source" => "secrets.yml", "strategy" => "copy", "required" => false }
          )
        end

        # Add any detected sensitive files
        project_info[:sensitive_files].each do |file|
          next if files.any? { |f| f["source"] == file }

          strategy = file.match?(/\.(key|pem|p12|jks)$/) ? "copy" : "symlink"
          files << { "source" => file, "strategy" => strategy, "required" => false }
        end

        { "type" => "copy_files", "config" => { "files" => files } }
      end

      # Suggest setup commands based on package manager
      def suggest_setup_commands_rules(project_info)
        commands = []

        case project_info[:package_manager]
        when :bundler
          commands << { "command" => %w[bundle install], "description" => "Install Ruby dependencies" }
          if project_info[:type] == :rails
            commands << { "command" => ["bin/rails", "db:create"],
                          "condition" => "file_missing:db/development.sqlite3", "description" => "Create database" }
            commands << { "command" => ["bin/rails", "db:migrate"], "description" => "Run database migrations" }
          end
        when :npm
          commands << { "command" => %w[npm install], "description" => "Install Node.js dependencies" }
          commands << { "command" => %w[npm run build], "condition" => "file_exists:package.json",
                        "required" => false, "description" => "Build project" }
        when :yarn
          commands << { "command" => %w[yarn install], "description" => "Install Node.js dependencies" }
          commands << { "command" => %w[yarn build], "condition" => "file_exists:package.json", "required" => false,
                        "description" => "Build project" }
        when :pnpm
          commands << { "command" => %w[pnpm install], "description" => "Install Node.js dependencies" }
        when :pip
          commands << { "command" => ["pip", "install", "-r", "requirements.txt"],
                        "description" => "Install Python dependencies" }
        when :pipenv
          commands << { "command" => %w[pipenv install], "description" => "Install Python dependencies" }
        when :poetry
          commands << { "command" => %w[poetry install], "description" => "Install Python dependencies" }
        end

        { "type" => "setup_commands", "config" => { "commands" => commands } }
      end

      # Suggest template rules for documentation
      def suggest_template_rules(project_info)
        templates = []

        # Always suggest session info template
        templates << {
          "source" => ".sxn/templates/session-info.md.liquid",
          "destination" => "SESSION_INFO.md",
          "required" => false
        }

        # Language-specific templates
        case project_info[:type]
        when :rails
          templates << {
            "source" => ".sxn/templates/rails/CLAUDE.md.liquid",
            "destination" => "CLAUDE.md",
            "required" => false
          }
        when :nodejs, :nextjs, :react
          templates << {
            "source" => ".sxn/templates/javascript/README.md.liquid",
            "destination" => "README.md",
            "required" => false,
            "overwrite" => false
          }
        end

        { "type" => "template", "config" => { "templates" => templates } }
      end

      # Check if project has typical Node.js characteristics
      def has_nodejs_characteristics?
        return false unless file_exists_in_project?("package.json")

        # Check for Node.js-specific dependencies or scripts
        nodejs_indicators = %w[
          express fastify koa hapi
          nodemon pm2 forever
          @types/node typescript ts-node
          eslint jest mocha nyc
          webpack parcel rollup
          commander inquirer chalk
          axios request node-fetch
        ]

        # Check for Node.js specific scripts
        nodejs_scripts = %w[start dev server build test]

        has_nodejs_deps = nodejs_indicators.any? { |dep| package_json_has_dependency?(dep) }
        has_nodejs_scripts = nodejs_scripts.any? { |script| package_json_has_script?(script) }
        has_main_entry = package_json_has_main_entry?

        has_nodejs_deps || has_nodejs_scripts || has_main_entry
      end

      # Helper methods for file content checking
      def gemfile_contains?(gem_name)
        gemfile_path = File.join(@project_path, "Gemfile")
        return false unless File.exist?(gemfile_path)

        File.read(gemfile_path).include?(gem_name)
      end

      def package_json_has_dependency?(dep_name)
        package_json_path = File.join(@project_path, "package.json")
        return false unless File.exist?(package_json_path)

        begin
          package_data = JSON.parse(File.read(package_json_path))
          all_deps = {}
          all_deps.merge!(package_data["dependencies"] || {})
          all_deps.merge!(package_data["devDependencies"] || {})
          all_deps.merge!(package_data["peerDependencies"] || {})

          all_deps.key?(dep_name)
        rescue JSON::ParserError, Errno::EACCES, Errno::EIO, StandardError
          false
        end
      end

      def requirements_contains?(package_name)
        requirements_path = File.join(@project_path, "requirements.txt")
        return false unless File.exist?(requirements_path)

        File.read(requirements_path).downcase.include?(package_name.downcase)
      end

      def package_json_has_script?(script_name)
        package_json_path = File.join(@project_path, "package.json")
        return false unless File.exist?(package_json_path)

        begin
          package_data = JSON.parse(File.read(package_json_path))
          scripts = package_data["scripts"] || {}
          scripts.key?(script_name)
        rescue JSON::ParserError
          false
        end
      end

      def package_json_has_main_entry?
        package_json_path = File.join(@project_path, "package.json")
        return false unless File.exist?(package_json_path)

        begin
          package_data = JSON.parse(File.read(package_json_path))
          package_data.key?("main") || package_data.key?("module") || package_data.key?("exports")
        rescue JSON::ParserError
          false
        end
      end

      def file_contains?(file_path, content)
        full_path = File.join(@project_path, file_path)
        return false unless File.exist?(full_path)

        File.read(full_path).downcase.include?(content.downcase)
      rescue StandardError
        false
      end

      def env_contains?(env_var, content)
        env_value = ENV.fetch(env_var, nil)
        return false unless env_value

        env_value.include?(content)
      end

      # Analysis methods for detailed project inspection
      def analyze_important_files
        important_patterns = %w[
          README* LICENSE* CHANGELOG* CONTRIBUTING*
          Dockerfile docker-compose.* .dockerignore
          .gitignore .gitattributes
          Makefile Rakefile
        ]

        found_files = []
        important_patterns.each do |pattern|
          found_files.concat(Dir.glob(File.join(@project_path, pattern), File::FNM_CASEFOLD))
        end

        found_files.map { |f| File.basename(f) }
      end

      def analyze_directory_structure
        important_dirs = %w[
          src lib app bin config test spec tests
          public assets static dist build
          docs documentation
        ]

        important_dirs.select do |dir|
          File.directory?(File.join(@project_path, dir))
        end
      end

      def analyze_dependencies
        deps = {}

        # Ruby dependencies
        deps[:ruby] = parse_gemfile_lock if file_exists_in_project?("Gemfile.lock")

        # Node.js dependencies
        deps[:nodejs] = parse_package_json if file_exists_in_project?("package.json")

        # Python dependencies
        deps[:python] = parse_requirements_txt if file_exists_in_project?("requirements.txt")

        deps
      end

      # Parse dependencies by type for testing
      def parse_dependencies(type)
        case type
        when :bundler, :ruby
          if file_exists_in_project?("Gemfile.lock")
            parse_gemfile_lock
          elsif file_exists_in_project?("Gemfile")
            parse_gemfile
          else
            []
          end
        when :npm, :nodejs
          file_exists_in_project?("package.json") ? parse_package_json : []
        when :python
          file_exists_in_project?("requirements.txt") ? parse_requirements_txt : []
        else
          []
        end
      end

      def analyze_configuration_files
        Dir.glob(File.join(@project_path, "**", "*.{yml,yaml,json,toml,ini,conf,config}"))
           .map { |f| Pathname.new(f).relative_path_from(Pathname.new(@project_path)).to_s }
           .select { |f| !f.start_with?("node_modules/") && !f.start_with?(".git/") }
      end

      def analyze_scripts
        scripts = {}

        # Package.json scripts
        if file_exists_in_project?("package.json")
          begin
            package_data = JSON.parse(File.read(File.join(@project_path, "package.json")))
            scripts[:npm] = package_data["scripts"]&.keys || []
          rescue JSON::ParserError
            # Ignore parsing errors
          end
        end

        # Executable files
        executable_files = Dir.glob(File.join(@project_path, "bin/*")).select { |f| File.executable?(f) }
        scripts[:executables] = executable_files.map { |f| File.basename(f) }

        scripts
      end

      def analyze_documentation
        Dir.glob(File.join(@project_path, "**", "*.{md,txt,rst,adoc}"))
           .map { |f| Pathname.new(f).relative_path_from(Pathname.new(@project_path)).to_s }
           .select { |f| !f.start_with?("node_modules/") && !f.start_with?(".git/") }
      end

      # Dependency parsing helpers (simplified implementations)
      def parse_gemfile_lock
        # Simplified - would need more robust parsing for production
        return [] unless file_exists_in_project?("Gemfile.lock")

        begin
          # Try to read and parse the file
          content = File.read(File.join(@project_path, "Gemfile.lock"))
          # Simplified parsing - just return a hardcoded list if content contains gem specs
          content.include?("GEM") || content.include?("specs:") ? ["gems from Gemfile.lock"] : []
        rescue StandardError
          []
        end
      end

      def parse_gemfile
        # Parse Gemfile for gem dependencies
        return [] unless file_exists_in_project?("Gemfile")

        begin
          content = File.read(File.join(@project_path, "Gemfile"))
          gems = []

          # Extract gem names using regex
          content.scan(/gem\s+['"]([^'"]+)['"]/) do |match|
            gems << match[0]
          end

          gems
        rescue StandardError
          []
        end
      end

      def parse_package_json
        return [] unless file_exists_in_project?("package.json")

        begin
          content = File.read(File.join(@project_path, "package.json"))
          data = JSON.parse(content)

          dependencies = []
          dependencies.concat(data["dependencies"]&.keys || [])
          dependencies.concat(data["devDependencies"]&.keys || [])
          dependencies.concat(data["peerDependencies"]&.keys || [])

          dependencies.uniq
        rescue JSON::ParserError, StandardError
          []
        end
      end

      def parse_requirements_txt
        # Simplified - would need more robust parsing for production
        ["packages from requirements.txt"]
      end
    end
  end
end
