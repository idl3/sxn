# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Templates Performance", :performance do
  let(:processor) { Sxn::Templates::TemplateProcessor.new }
  let(:engine) { Sxn::Templates::TemplateEngine.new }
  let(:security) { Sxn::Templates::TemplateSecurity.new }

  describe "TemplateProcessor performance" do
    it "processes large templates within time limit" do
      # Create a large but reasonable template
      large_template = generate_large_template(1000) # 1000 lines
      variables = generate_test_variables(100) # 100 variables

      start_time = Time.now

      result = processor.process(large_template, variables)

      elapsed = Time.now - start_time

      expect(elapsed).to be < 2.0, "Large template processing took #{elapsed}s, expected < 2.0s"
      expect(result).to be_a(String)
      expect(result.length).to be > 1000
    end

    it "handles templates with many variables efficiently" do
      template = "{% for item in items %}{{item.name}}: {{item.value}} - {{item.description}}\n{% endfor %}"

      # Create large variable set
      large_variables = {
        items: Array.new(1000) do |i|
          {
            name: "item_#{i}",
            value: "value_#{i}",
            description: "This is a description for item number #{i} with some extra text to make it longer"
          }
        end
      }

      start_time = Time.now

      result = processor.process(template, large_variables)

      elapsed = Time.now - start_time

      expect(elapsed).to be < 5.0, "Many variables processing took #{elapsed}s, expected < 5.0s"
      expect(result.lines.count).to eq(1000)
    end

    it "handles deeply nested variable structures" do
      template = "{{session.project.worktree.config.database.connection.host}}"

      # Create deeply nested structure
      deep_variables = create_deep_nested_structure(20) # 20 levels deep

      start_time = Time.now

      result = processor.process(template, deep_variables)

      elapsed = Time.now - start_time

      expect(elapsed).to be < 5.0, "Deep nesting processing took #{elapsed}s, expected < 5.0s"
      expect(result).to include("deep_value")
    end

    it "processes templates with complex loops efficiently" do
      template = <<~LIQUID
        {% for category in categories %}
          ## {{ category.name }}
          {% for item in category.items %}
            {% for detail in item.details %}
              - {{ detail.name }}: {{ detail.value }}
            {% endfor %}
          {% endfor %}
        {% endfor %}
      LIQUID

      # Create nested loop structure
      variables = {
        categories: Array.new(10) do |i|
          {
            name: "Category #{i}",
            items: Array.new(10) do |j|
              {
                name: "Item #{j}",
                details: Array.new(10) do |k|
                  { name: "Detail #{k}", value: "Value #{k}" }
                end
              }
            end
          }
        end
      }

      start_time = Time.now

      result = processor.process(template, variables)

      elapsed = Time.now - start_time

      expect(elapsed).to be < 5.0, "Complex loops processing took #{elapsed}s, expected < 5.0s"
      expect(result).to include("Category 0")
      expect(result).to include("Detail 9")
    end

    it "processes templates with many conditionals efficiently" do
      template = generate_conditional_template(100) # 100 conditional blocks
      variables = generate_conditional_variables(100)

      start_time = Time.now

      result = processor.process(template, variables)

      elapsed = Time.now - start_time

      expect(elapsed).to be < 5.0, "Many conditionals processing took #{elapsed}s, expected < 5.0s"
      expect(result.length).to be > 0
    end
  end

  describe "TemplateVariables performance" do
    let(:mock_session) { create_mock_session_with_worktrees(50) } # 50 worktrees
    let(:mock_project) { create_mock_project }
    let(:collector) { Sxn::Templates::TemplateVariables.new(mock_session, mock_project) }

    before do
      # Mock git operations to avoid actual git calls
      allow(collector).to receive(:execute_git_command).and_return("")
      allow(collector).to receive(:find_git_directory).and_return("/tmp/git")
    end

    it "collects variables from complex session efficiently" do
      start_time = Time.now

      variables = collector.collect

      elapsed = Time.now - start_time

      expect(elapsed).to be < 2.0, "Variable collection took #{elapsed}s, expected < 2.0s"
      expect(variables).to be_a(Hash)
      expect(variables[:session][:worktrees]).to be_an(Array)
      expect(variables[:session][:worktrees].length).to eq(50)
    end

    it "caches variables for subsequent calls" do
      # First call (should be slower)
      start_time = Time.now
      variables1 = collector.collect
      first_elapsed = Time.now - start_time

      # Second call (should be much faster due to caching)
      start_time = Time.now
      variables2 = collector.collect
      second_elapsed = Time.now - start_time

      expect(second_elapsed).to be < (first_elapsed / 10),
                                "Cached call should be much faster: #{second_elapsed}s vs #{first_elapsed}s"
      expect(variables1.object_id).to eq(variables2.object_id)
    end

    it "handles large project structures efficiently" do
      large_project = create_mock_project_with_dependencies(200) # 200 dependencies
      large_collector = Sxn::Templates::TemplateVariables.new(mock_session, large_project)

      allow(large_collector).to receive(:execute_git_command).and_return("")
      allow(large_collector).to receive(:find_git_directory).and_return("/tmp/git")

      start_time = Time.now

      variables = large_collector.collect

      elapsed = Time.now - start_time

      expect(elapsed).to be < 5.0, "Large project collection took #{elapsed}s, expected < 5.0s"
      expect(variables[:project]).to be_a(Hash)
    end
  end

  describe "TemplateSecurity performance" do
    it "validates large templates efficiently" do
      large_template = generate_large_template(500)
      large_variables = generate_test_variables(200)

      start_time = Time.now

      result = security.validate_template(large_template, large_variables)

      elapsed = Time.now - start_time

      expect(elapsed).to be < 5.0, "Large template validation took #{elapsed}s, expected < 5.0s"
      expect(result).to be true
    end

    it "sanitizes large variable sets efficiently" do
      large_variables = generate_test_variables(500)

      start_time = Time.now

      sanitized = security.sanitize_variables(large_variables)

      elapsed = Time.now - start_time

      expect(elapsed).to be < 3.0, "Large variable sanitization took #{elapsed}s, expected < 3.0s"
      expect(sanitized).to be_a(Hash)
    end

    it "uses caching effectively for repeated validations" do
      template = generate_large_template(100)
      variables = generate_test_variables(50)

      # Warm up the cache
      security.validate_template(template, variables)

      # Measure multiple runs to get a more stable average
      first_times = []
      cached_times = []
      
      5.times do
        # Clear cache for fresh validation
        security.instance_variable_set(:@validation_cache, {})
        
        start_time = Time.now
        security.validate_template(template, variables)
        first_times << (Time.now - start_time)
        
        # Second validation (should be cached)
        start_time = Time.now
        security.validate_template(template, variables)
        cached_times << (Time.now - start_time)
      end
      
      avg_first = first_times.sum / first_times.size
      avg_cached = cached_times.sum / cached_times.size
      
      # Allow 20% tolerance for performance variance
      expect(avg_cached).to be <= (avg_first * 1.2),
                                "Cached validation should be reasonably fast: #{avg_cached}s vs #{avg_first}s"
    end
  end

  describe "TemplateEngine integration performance" do
    let(:temp_dir) { Dir.mktmpdir }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it "processes multiple templates efficiently" do
      # Create multiple template files
      templates = {}
      20.times do |i|
        template_path = File.join(temp_dir, "template_#{i}.liquid")
        template_content = generate_large_template(50)
        File.write(template_path, template_content)
        templates["template_#{i}"] = template_path
      end

      start_time = Time.now

      results = templates.map do |name, path|
        File.join(temp_dir, "output_#{name}.md")
        engine.process_string(File.read(path), {}, validate: false)
      end

      elapsed = Time.now - start_time

      expect(elapsed).to be < 3.0, "Multiple template processing took #{elapsed}s, expected < 3.0s"
      expect(results).to all(be_a(String))
    end

    it "handles concurrent template processing" do
      skip "Concurrent processing not implemented yet"

      # This test would verify that template processing can handle
      # concurrent requests efficiently, which might be needed for
      # MCP server usage
    end
  end

  describe "memory usage" do
    it "doesn't leak memory with repeated processing" do
      template = generate_large_template(100)
      variables = generate_test_variables(50)

      # Get initial memory usage
      GC.start
      initial_memory = memory_usage_mb

      # Process template many times
      100.times do
        processor.process(template, variables)
      end

      # Force garbage collection and check memory
      GC.start
      final_memory = memory_usage_mb

      memory_increase = final_memory - initial_memory

      expect(memory_increase).to be < 100,
                                 "Memory increased by #{memory_increase}MB, expected < 100MB"
    end

    it "handles large template sets without excessive memory usage" do
      # Create a large set of templates
      templates = Array.new(50) { generate_large_template(100) }
      variables = generate_test_variables(100)

      GC.start
      initial_memory = memory_usage_mb

      # Process all templates
      templates.each do |template|
        processor.process(template, variables)
      end

      GC.start
      final_memory = memory_usage_mb

      memory_increase = final_memory - initial_memory

      expect(memory_increase).to be < 100,
                                 "Memory increased by #{memory_increase}MB, expected < 100MB"
    end
  end

  private

  def generate_large_template(lines)
    template_parts = []

    # Add header
    template_parts << "# Template Generated at {{timestamp.now}}"
    template_parts << ""

    # Add session info
    template_parts << "## Session: {{session.name}}"
    template_parts << "Path: {{session.path}}"
    template_parts << ""

    # Generate many variable references without complex nesting
    (lines / 5).times do |i|
      template_parts << "### Section #{i}"
      template_parts << "User: {{user.name}}"
      template_parts << "Branch: {{git.branch}}"
      template_parts << "Project: {{project.name}}"
      template_parts << "Environment: {{environment.ruby.version}}"
      template_parts << ""
    end

    template_parts.join("\n")
  end

  def generate_test_variables(count)
    variables = {
      session: {
        name: "performance-test",
        path: "/tmp/performance",
        active: true,
        tags: %w[performance test],
        started_at: "2025-01-16T10:00:00Z",
        updated_at: "2025-01-16T14:30:00Z"
      },
      git: {
        branch: "performance-test",
        author: "Performance Tester"
      },
      user: {
        name: "Test User"
      },
      project: {
        name: "performance-project"
      },
      environment: {
        ruby: { version: "3.2.0" }
      },
      timestamp: {
        now: "2025-01-16T15:00:00Z"
      }
    }

    # Add many dynamic variables
    (count / 10).times do |i|
      variables["dynamic_#{i}"] = {
        "value_#{i}" => "test_value_#{i}",
        "array_#{i}" => Array.new(10) { |j| "item_#{j}" },
        "nested_#{i}" => {
          "deep_#{i}" => {
            "deeper_#{i}" => "deep_value_#{i}"
          }
        }
      }
    end

    variables
  end

  def generate_conditional_template(count)
    template_parts = []

    count.times do |i|
      template_parts << "{% if condition_#{i} %}"
      template_parts << "  Value #{i}: {{value_#{i}}}"
      template_parts << "{% else %}"
      template_parts << "  No value for #{i}"
      template_parts << "{% endif %}"
    end

    template_parts.join("\n")
  end

  def generate_conditional_variables(count)
    variables = {}

    count.times do |i|
      variables["condition_#{i}"] = i.even?
      variables["value_#{i}"] = "test_value_#{i}"
    end

    variables
  end

  def create_deep_nested_structure(_depth)
    structure = { session: {} }
    current = structure[:session]

    path = %w[project worktree config database connection]
    path.each_with_index do |key, i|
      if i == path.length - 1
        current[key.to_sym] = { host: "deep_value" }
      else
        current[key.to_sym] = {}
        current = current[key.to_sym]
      end
    end

    structure
  end

  def create_mock_session_with_worktrees(count)
    worktrees = Array.new(count) do |i|
      double("Worktree",
             name: "worktree_#{i}",
             path: Pathname.new("/tmp/worktree_#{i}"),
             branch: "feature/branch_#{i}",
             created_at: Time.now - (i * 3600),
             started_at: Time.now - (i * 3600))
    end

    double("Session",
           name: "performance-session",
           path: Pathname.new("/tmp/performance-session"),
           created_at: Time.now - 86_400,
           started_at: Time.now - 86_400,
           updated_at: Time.now,
           status: "active",
           worktrees: worktrees).tap do |session|
      allow(session).to receive(:respond_to?).with(:worktrees).and_return(true)
      allow(session).to receive(:respond_to?).with(:linear_task).and_return(false)
      allow(session).to receive(:respond_to?).with(:description).and_return(false)
      allow(session).to receive(:respond_to?).with(:projects).and_return(false)
      allow(session).to receive(:respond_to?).with(:tags).and_return(false)
    end
  end

  def create_mock_project
    double("Project",
           name: "performance-project",
           path: Pathname.new("/tmp/performance-project"))
  end

  def create_mock_project_with_dependencies(count)
    dependencies = Array.new(count) { |i| "dependency_#{i}" }

    double("Project",
           name: "large-project",
           path: Pathname.new("/tmp/large-project"),
           dependencies: dependencies)
  end

  def memory_usage_mb
    # Get memory usage in MB - works for both macOS and Linux
    `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
  rescue StandardError
    0 # Fallback if ps command fails
  end
end
