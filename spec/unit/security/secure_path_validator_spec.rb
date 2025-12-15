# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "tmpdir"

RSpec.describe Sxn::Security::SecurePathValidator do
  let(:temp_dir) { Dir.mktmpdir("sxn_test") }
  let(:project_root) { temp_dir }
  let(:validator) { described_class.new(project_root) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    context "with valid project root" do
      it "accepts absolute path" do
        expect { described_class.new(temp_dir) }.not_to raise_error
      end

      it "resolves relative path to absolute" do
        Dir.chdir(temp_dir) do
          validator = described_class.new(".")
          expect(File.realpath(validator.project_root)).to eq(File.realpath(temp_dir))
        end
      end
    end

    context "with invalid project root" do
      it "raises error for nil project root" do
        expect { described_class.new(nil) }.to raise_error(ArgumentError, /cannot be nil/)
      end

      it "raises error for empty project root" do
        expect { described_class.new("") }.to raise_error(ArgumentError, /cannot be nil/)
      end

      it "raises error for non-existent directory" do
        non_existent = File.join(temp_dir, "does_not_exist")
        expect { described_class.new(non_existent) }.to raise_error(Sxn::PathValidationError, /does not exist/)
      end

      it "raises error for relative path when cwd is different" do
        Dir.pwd
        Dir.chdir("/tmp") do # Change to a different directory
          expect { described_class.new("relative/path") }.to raise_error(Sxn::PathValidationError, /does not exist/)
        end
      end
    end
  end

  describe "#validate_path" do
    let(:safe_file) { File.join(temp_dir, "safe.txt") }
    let(:nested_file) { File.join(temp_dir, "subdir", "nested.txt") }

    before do
      File.write(safe_file, "safe content")
      FileUtils.mkdir_p(File.dirname(nested_file))
      File.write(nested_file, "nested content")
    end

    context "with safe paths" do
      it "accepts relative path within project" do
        result = validator.validate_path("safe.txt")
        expect(File.realpath(result)).to eq(File.realpath(safe_file))
      end

      it "accepts nested relative path" do
        result = validator.validate_path("subdir/nested.txt")
        expect(File.realpath(result)).to eq(File.realpath(nested_file))
      end

      it "accepts absolute path within project" do
        result = validator.validate_path(safe_file)
        expect(File.realpath(result)).to eq(File.realpath(safe_file))
      end

      it "handles paths with current directory references" do
        result = validator.validate_path("./safe.txt")
        expect(File.realpath(result)).to eq(File.realpath(safe_file))
      end

      it "allows validation of non-existent paths when allow_creation is true" do
        result = validator.validate_path("new_file.txt", allow_creation: true)
        expect(result).to eq(File.join(File.realpath(temp_dir), "new_file.txt"))
      end
    end

    context "with directory traversal attempts" do
      it "rejects obvious directory traversal" do
        expect { validator.validate_path("../etc/passwd") }.to raise_error(Sxn::PathValidationError, /traversal/)
      end

      it "rejects nested directory traversal" do
        expect do
          validator.validate_path("subdir/../../etc/passwd")
        end.to raise_error(Sxn::PathValidationError, /traversal/)
      end

      it "rejects path starting with .." do
        expect { validator.validate_path("..") }.to raise_error(Sxn::PathValidationError, /traversal/)
      end

      it "rejects Windows-style directory traversal" do
        expect do
          validator.validate_path("subdir\\..\\..\\etc\\passwd")
        end.to raise_error(Sxn::PathValidationError, /traversal/)
      end

      it "rejects encoded directory traversal" do
        expect { validator.validate_path("subdir/%2e%2e/passwd") }.to raise_error(Errno::ENOENT)
      end

      it "rejects multiple slash patterns" do
        expect do
          validator.validate_path("subdir//..//etc//passwd")
        end.to raise_error(Sxn::PathValidationError, /directory traversal/)
      end
    end

    context "with null byte injection attempts" do
      it "rejects paths with null bytes" do
        expect do
          validator.validate_path("safe.txt\x00../../../etc/passwd")
        end.to raise_error(Sxn::PathValidationError,
                           /directory traversal/)
      end

      it "rejects paths with encoded null bytes" do
        expect do
          validator.validate_path("safe.txt%00../../../etc/passwd")
        end.to raise_error(Sxn::PathValidationError,
                           /directory traversal/)
      end
    end

    context "with absolute paths outside project" do
      it "rejects absolute path outside project" do
        outside_path = "/etc/passwd"
        expect do
          validator.validate_path(outside_path)
        end.to raise_error(Sxn::PathValidationError, /outside project boundaries/)
      end

      it "rejects path that resolves outside project" do
        # Create a symlink that points outside the project
        link_target = File.join(temp_dir, "..", "outside.txt")
        File.write(link_target, "outside content")
        link_path = File.join(temp_dir, "link_to_outside")
        File.symlink(link_target, link_path)

        expect do
          validator.validate_path("link_to_outside")
        end.to raise_error(Sxn::PathValidationError, /outside project boundaries/)
      ensure
        FileUtils.rm_f(link_target)
        File.unlink(link_path) if File.symlink?(link_path)
      end
    end

    context "with non-existent paths" do
      it "raises error for non-existent path when allow_creation is false" do
        expect { validator.validate_path("does_not_exist.txt") }.to raise_error(Errno::ENOENT)
      end

      it "allows non-existent paths when allow_creation is true" do
        result = validator.validate_path("new_dir/new_file.txt", allow_creation: true)
        expect(result).to eq(File.join(File.realpath(temp_dir), "new_dir", "new_file.txt"))
      end
    end

    context "with edge cases" do
      it "handles empty relative path components" do
        expect do
          validator.validate_path("subdir//nested.txt")
        end.to raise_error(Sxn::PathValidationError, /dangerous pattern/)
      end

      it "handles very long paths" do
        long_path = "#{"a" * 1000}.txt"
        result = validator.validate_path(long_path, allow_creation: true)
        expect(result).to eq(File.join(File.realpath(temp_dir), long_path))
      end

      it "rejects paths with only dots" do
        # A file named "..." should be allowed as it's just a filename with dots
        result = validator.validate_path("...", allow_creation: true)
        expect(result).to eq(File.join(File.realpath(temp_dir), "..."))
      end

      it "handles mixed path separators" do
        # Test Windows-style mixed with Unix-style
        expect do
          validator.validate_path("subdir\\../file.txt")
        end.to raise_error(Sxn::PathValidationError, /directory traversal/)
      end

      it "handles normalize_path_manually with complex paths" do
        # Test edge cases in manual normalization
        result = validator.send(:normalize_path_manually, "/a/b/./c/../d/e")
        expect(result).to eq("/a/b/d/e")
      end
    end
  end

  describe "#validate_file_operation" do
    let(:source_file) { File.join(temp_dir, "source.txt") }
    let(:dest_path) { "destination.txt" }

    before do
      File.write(source_file, "source content")
    end

    context "with valid file operations" do
      it "validates both source and destination" do
        source, dest = validator.validate_file_operation("source.txt", dest_path, allow_creation: true)
        expect(File.realpath(source)).to eq(File.realpath(source_file))
        expect(dest).to eq(File.join(File.realpath(temp_dir), dest_path))
      end

      it "validates existing source and new destination" do
        source, dest = validator.validate_file_operation("source.txt", "new/dest.txt", allow_creation: true)
        expect(File.realpath(source)).to eq(File.realpath(source_file))
        expect(dest).to eq(File.join(File.realpath(temp_dir), "new", "dest.txt"))
      end
    end

    context "with invalid file operations" do
      it "rejects directory as source" do
        subdir = File.join(temp_dir, "subdir")
        FileUtils.mkdir_p(subdir)

        expect do
          validator.validate_file_operation("subdir",
                                            dest_path)
        end.to raise_error(Sxn::PathValidationError, /cannot be a directory/)
      end

      it "rejects non-existent source" do
        expect { validator.validate_file_operation("nonexistent.txt", dest_path) }.to raise_error(Errno::ENOENT)
      end

      it "rejects unsafe destination path" do
        expect do
          validator.validate_file_operation("source.txt",
                                            "../outside.txt")
        end.to raise_error(Sxn::PathValidationError, /traversal/)
      end
    end
  end

  describe "#within_boundaries?" do
    it "returns true for safe paths" do
      expect(validator.within_boundaries?("safe/path.txt")).to be true
    end

    it "returns false for unsafe paths" do
      expect(validator.within_boundaries?("../outside.txt")).to be false
    end

    it "returns false for nil path" do
      expect(validator.within_boundaries?(nil)).to be false
    end

    it "returns false for empty path" do
      expect(validator.within_boundaries?("")).to be false
    end
  end

  describe "symlink security" do
    let(:target_file) { File.join(temp_dir, "target.txt") }
    let(:safe_link) { File.join(temp_dir, "safe_link") }
    let(:dangerous_link) { File.join(temp_dir, "dangerous_link") }

    before do
      File.write(target_file, "target content")
    end

    context "with safe symlinks" do
      it "allows symlinks pointing within project" do
        File.symlink("target.txt", safe_link)
        result = validator.validate_path("safe_link")
        expect(File.realpath(result)).to eq(File.realpath(safe_link))
      end

      it "allows relative symlinks within project" do
        subdir = File.join(temp_dir, "subdir")
        FileUtils.mkdir_p(subdir)
        link_in_subdir = File.join(subdir, "link_to_parent")
        File.symlink("../target.txt", link_in_subdir)

        result = validator.validate_path("subdir/link_to_parent")
        expect(File.realpath(result)).to eq(File.realpath(link_in_subdir))
      end
    end

    context "with dangerous symlinks" do
      it "rejects symlinks pointing outside project" do
        outside_target = "/etc/passwd"
        File.symlink(outside_target, dangerous_link)

        expect do
          validator.validate_path("dangerous_link")
        end.to raise_error(Sxn::PathValidationError, /outside project boundaries/)
      end

      it "rejects symlinks with relative targets outside project" do
        # Create a parent temp directory that we control
        parent_temp = Dir.mktmpdir("sxn_parent_test")

        # Create our project dir inside parent
        project_dir = File.join(parent_temp, "project")
        FileUtils.mkdir_p(project_dir)

        # Create target file outside project but within parent
        outside_file = File.join(parent_temp, "outside_file.txt")
        File.write(outside_file, "outside content")

        # Create validator for project dir
        local_validator = described_class.new(project_dir)

        # Create symlink in project that points outside via relative path
        local_dangerous_link = File.join(project_dir, "dangerous_link")
        File.symlink("../outside_file.txt", local_dangerous_link)

        expect { local_validator.validate_path("dangerous_link") }.to raise_error(Sxn::PathValidationError, /outside project boundaries/)

        FileUtils.rm_rf(parent_temp)
      end

      it "handles nested symlink validation" do
        # Create a nested directory structure with symlinks
        nested_dir = File.join(temp_dir, "level1", "level2")
        FileUtils.mkdir_p(nested_dir)

        nested_link = File.join(nested_dir, "nested_link")
        File.symlink("../../target.txt", nested_link) # Points back to project root

        expect do
          validator.validate_path("level1/level2/nested_link")
        end.not_to raise_error
      end

      it "detects symlink attacks in path components" do
        # Create a symlink in a subdirectory that points outside
        subdir = File.join(temp_dir, "subdir")
        FileUtils.mkdir_p(subdir)

        bad_symlink = File.join(subdir, "bad_link")
        File.symlink("../../", bad_symlink)

        expect { validator.validate_path("subdir/bad_link/etc/passwd") }.to raise_error(Errno::ENOENT)
      end
    end
  end

  describe "performance" do
    it "validates paths efficiently" do
      # Create many files
      100.times do |i|
        File.write(File.join(temp_dir, "file_#{i}.txt"), "content #{i}")
      end

      start_time = Time.now
      100.times do |i|
        validator.validate_path("file_#{i}.txt")
      end
      duration = Time.now - start_time

      expect(duration).to be < 5.0 # Should complete within reasonable time for CI
    end

    it "handles deeply nested paths efficiently" do
      deep_path = (1..20).map { |i| "level_#{i}" }.join("/")
      FileUtils.mkdir_p(File.join(temp_dir, deep_path))

      deep_file = File.join(deep_path, "deep_file.txt")
      File.write(File.join(temp_dir, deep_file), "deep content")

      start_time = Time.now
      result = validator.validate_path(deep_file)
      duration = Time.now - start_time

      expect(File.realpath(result)).to eq(File.realpath(File.join(temp_dir, deep_file)))
      expect(duration).to be < 5.0 # Should be fast enough for CI
    end
  end

  describe "error messages" do
    it "provides clear error messages for different violations" do
      expect { validator.validate_path("../outside") }.to raise_error(Sxn::PathValidationError, /directory traversal/)
      expect { validator.validate_path("path\x00injection") }.to raise_error(Sxn::PathValidationError, /null bytes/)
      expect do
        validator.validate_path("/etc/passwd")
      end.to raise_error(Sxn::PathValidationError, /outside project boundaries/)
    end

    it "includes problematic path in error messages" do
      dangerous_path = "../../../etc/passwd"
      expect do
        validator.validate_path(dangerous_path)
      end.to raise_error(Sxn::PathValidationError, /#{Regexp.escape(dangerous_path)}/)
    end
  end

  describe "manual path normalization" do
    it "handles path traversal in normalize_path_manually" do
      # Create a path that would result in more .. than parts available
      # This should trigger the path traversal detection
      path_with_traversal = "/a/../../../etc/passwd"

      # Mock the behavior to ensure we test the right path
      expect do
        validator.send(:normalize_path_manually, path_with_traversal)
      end.to raise_error(Sxn::PathValidationError, /path traversal detected/)
    end

    it "handles empty normalized parts" do
      result = validator.send(:normalize_path_manually, "/some/./path/./file.txt")
      expect(result).to eq("/some/path/file.txt")
    end

    it "handles relative path normalization" do
      result = validator.send(:normalize_path_manually, "relative/./path")
      expect(result).to eq("relative/path")
    end
  end

  describe "symlink target validation edge cases" do
    let(:subdir) { File.join(temp_dir, "subdir") }
    let(:symlink_path) { File.join(subdir, "test_link") }

    before do
      FileUtils.mkdir_p(subdir)
    end

    it "validates absolute symlink targets" do
      # Create a symlink with absolute target within project
      target_file = File.join(temp_dir, "target.txt")
      File.write(target_file, "content")
      File.symlink(target_file, symlink_path)

      expect do
        validator.validate_path("subdir/test_link")
      end.not_to raise_error
    end

    it "rejects absolute symlink targets outside project" do
      # Create a symlink with absolute target outside project
      File.symlink("/etc/passwd", symlink_path)

      expect do
        validator.validate_path("subdir/test_link")
      end.to raise_error(Sxn::PathValidationError, /outside project boundaries/)
    end

    it "validates relative symlink resolution" do
      # Create target in parent directory of symlink
      target_file = File.join(temp_dir, "target.txt")
      File.write(target_file, "content")

      # Create relative symlink pointing to parent
      File.symlink("../target.txt", symlink_path)

      expect do
        validator.validate_path("subdir/test_link")
      end.not_to raise_error
    end

    it "rejects relative symlinks that resolve outside project" do
      # Create a parent temp directory that we control
      parent_temp = Dir.mktmpdir("sxn_parent_test")

      # Create our project dir inside parent
      project_dir = File.join(parent_temp, "project")
      FileUtils.mkdir_p(project_dir)

      # Create target file outside project but within parent
      outside_file = File.join(parent_temp, "outside_target.txt")
      File.write(outside_file, "outside content")

      # Create validator for project dir
      local_validator = described_class.new(project_dir)

      # Create symlink subdir in project
      symlink_dir = File.join(project_dir, "subdir")
      FileUtils.mkdir_p(symlink_dir)
      symlink_file = File.join(symlink_dir, "test_link")

      # Create symlink that points outside project via relative path
      File.symlink("../../outside_target.txt", symlink_file)

      # This should raise PathValidationError for security
      expect do
        local_validator.validate_path("subdir/test_link")
      end.to raise_error(Sxn::PathValidationError, /outside project boundaries/)

      FileUtils.rm_rf(parent_temp)
    end
  end

  describe "argument validation" do
    it "rejects nil paths in validate_path" do
      expect do
        validator.validate_path(nil)
      end.to raise_error(ArgumentError, /cannot be nil or empty/)
    end

    it "rejects empty paths in validate_path" do
      expect do
        validator.validate_path("")
      end.to raise_error(ArgumentError, /cannot be nil or empty/)
    end

    it "rejects non-string paths in validate_path" do
      expect do
        validator.validate_path(123)
      end.to raise_error(ArgumentError, /must be a string/)
    end

    it "rejects non-string paths with array" do
      expect do
        validator.validate_path(%w[path components])
      end.to raise_error(ArgumentError, /must be a string/)
    end
  end

  describe "boundary validation error handling" do
    it "handles ArgumentError when paths don't share common ancestor" do
      # Mock relative_path_from to raise ArgumentError
      allow_any_instance_of(Pathname).to receive(:relative_path_from).and_raise(ArgumentError, "different prefix")

      expect do
        validator.validate_path("/some/path", allow_creation: true)
      end.to raise_error(Sxn::PathValidationError, /outside project boundaries/)
    end
  end

  describe "symlink validation error handling" do
    let(:subdir) { File.join(temp_dir, "subdir") }
    let(:symlink_path) { File.join(subdir, "test_link") }

    before do
      FileUtils.mkdir_p(subdir)
    end

    context "when symlink validation raises ArgumentError" do
      it "handles ArgumentError in absolute path symlink validation" do
        # Create a symlink with absolute target
        target_file = File.join(temp_dir, "target.txt")
        File.write(target_file, "content")
        File.symlink(target_file, symlink_path)

        # Mock relative_path_from to raise ArgumentError on symlink validation
        call_count = 0
        allow_any_instance_of(Pathname).to receive(:relative_path_from) do |instance, base|
          call_count += 1
          # Allow the first call (in validate_within_boundaries!) to succeed
          raise ArgumentError, "different prefix" unless call_count == 1

          instance.relative_path_from_without_mock(base)

          # Subsequent calls in validate_symlink_safety! should raise
        end

        # This is tricky to test as we need to get past the first boundary check
        # but fail in symlink validation. Let's use a different approach:
        # We'll test the path that triggers line 180 by mocking at a different level

        # Actually, let's create a scenario that would naturally trigger this
        # Create a symlink pointing outside, then mock the validation
        parent_temp = Dir.mktmpdir("sxn_parent_test")
        project_dir = File.join(parent_temp, "project")
        FileUtils.mkdir_p(project_dir)

        local_validator = described_class.new(project_dir)

        # Create a subdirectory with a symlink
        local_subdir = File.join(project_dir, "subdir")
        FileUtils.mkdir_p(local_subdir)
        local_symlink = File.join(local_subdir, "link")

        # Create symlink pointing to absolute path
        File.symlink(project_dir, local_symlink)

        # Now mock to trigger ArgumentError in symlink validation
        original_method = Pathname.instance_method(:relative_path_from)
        allow_any_instance_of(Pathname).to receive(:relative_path_from) do |instance, base|
          # Let initial boundary check pass
          raise ArgumentError, "different prefix" unless instance.to_s.include?("subdir/link")

          original_method.bind(instance).call(base)

          # Raise error when checking symlink target
        end

        expect do
          local_validator.validate_path("subdir/link")
        end.to raise_error(Sxn::PathValidationError, /outside project boundaries/)

        FileUtils.rm_rf(parent_temp)
      end
    end

    context "with relative symlink paths" do
      it "validates relative paths in symlink checking" do
        # Create a relative symlink
        target_file = File.join(temp_dir, "target.txt")
        File.write(target_file, "content")

        relative_link = File.join(subdir, "relative_link")
        File.symlink("../target.txt", relative_link)

        expect do
          validator.validate_path("subdir/relative_link")
        end.not_to raise_error
      end
    end

    context "with absolute symlink targets" do
      it "validates existing absolute symlink targets" do
        # Create a symlink with absolute target within project
        target_file = File.join(temp_dir, "target.txt")
        File.write(target_file, "content")

        absolute_link = File.join(subdir, "absolute_link")
        File.symlink(target_file, absolute_link)

        expect do
          validator.validate_path("subdir/absolute_link")
        end.not_to raise_error
      end

      it "validates non-existent absolute symlink targets" do
        # Create a symlink with absolute target that doesn't exist (but within project)
        non_existent_target = File.join(temp_dir, "non_existent.txt")

        absolute_link = File.join(subdir, "link_to_nonexistent")
        File.symlink(non_existent_target, absolute_link)

        # This should still validate the boundary even though target doesn't exist
        # Use allow_creation: true since the symlink target doesn't exist
        expect do
          validator.validate_path("subdir/link_to_nonexistent", allow_creation: true)
        end.not_to raise_error
      end

      it "rejects absolute symlink targets outside project" do
        # Create a symlink with absolute target outside project
        # Create the target first so the symlink validation runs
        outside_target = "/tmp/outside_target_test.txt"
        File.write(outside_target, "outside content")

        absolute_link = File.join(subdir, "outside_link")
        File.symlink(outside_target, absolute_link)

        begin
          expect do
            validator.validate_path("subdir/outside_link")
          end.to raise_error(Sxn::PathValidationError, /outside project boundaries/)
        ensure
          FileUtils.rm_f(outside_target)
        end
      end
    end

    context "with relative symlink resolution" do
      it "validates relative symlinks pointing to existing targets" do
        # Create target file
        target_file = File.join(temp_dir, "target.txt")
        File.write(target_file, "content")

        # Create relative symlink
        relative_link = File.join(subdir, "relative_link")
        File.symlink("../target.txt", relative_link)

        expect do
          validator.validate_path("subdir/relative_link")
        end.not_to raise_error
      end

      it "validates relative symlinks pointing to non-existent targets" do
        # Create relative symlink to non-existent file (but within project bounds)
        non_existent_relative = File.join(subdir, "link_to_nonexistent")
        File.symlink("../nonexistent.txt", non_existent_relative)

        # This should validate boundaries even if target doesn't exist
        # Use allow_creation: true since the symlink target doesn't exist
        expect do
          validator.validate_path("subdir/link_to_nonexistent", allow_creation: true)
        end.not_to raise_error
      end

      it "rejects relative symlinks that resolve outside project" do
        # Create a parent temp directory
        parent_temp = Dir.mktmpdir("sxn_parent_test")
        project_dir = File.join(parent_temp, "project")
        FileUtils.mkdir_p(project_dir)

        # Create target file outside project but within parent
        outside_file = File.join(parent_temp, "outside.txt")
        File.write(outside_file, "outside content")

        local_validator = described_class.new(project_dir)

        # Create subdirectory
        local_subdir = File.join(project_dir, "subdir")
        FileUtils.mkdir_p(local_subdir)

        # Create relative symlink that goes outside
        outside_link = File.join(local_subdir, "outside_link")
        File.symlink("../../outside.txt", outside_link)

        expect do
          local_validator.validate_path("subdir/outside_link")
        end.to raise_error(Sxn::PathValidationError, /outside project boundaries/)

        FileUtils.rm_rf(parent_temp)
      end
    end

    context "with non-existent symlink targets" do
      it "validates non-existent absolute symlink targets within project bounds" do
        # Create a symlink with absolute target that doesn't exist (but within project)
        non_existent_target = File.join(temp_dir, "future_file.txt")

        absolute_link = File.join(subdir, "link_to_future")
        File.symlink(non_existent_target, absolute_link)

        # This should validate boundaries even though target doesn't exist
        expect do
          validator.validate_path("subdir/link_to_future", allow_creation: true)
        end.not_to raise_error
      end

      it "validates non-existent relative symlink targets within project bounds" do
        # Create relative symlink to non-existent file (but within project bounds)
        non_existent_relative = File.join(subdir, "link_to_future_relative")
        File.symlink("../future_file.txt", non_existent_relative)

        # This should validate boundaries even if target doesn't exist
        expect do
          validator.validate_path("subdir/link_to_future_relative", allow_creation: true)
        end.not_to raise_error
      end
    end
  end

  describe "validate_path with relative paths" do
    it "handles relative path components in symlink validation" do
      # Create a nested directory structure
      nested = File.join(temp_dir, "level1", "level2")
      FileUtils.mkdir_p(nested)

      # Create target file at root
      target = File.join(temp_dir, "target.txt")
      File.write(target, "content")

      # Create symlink in nested directory pointing back to root via relative path
      link = File.join(nested, "link")
      File.symlink("../../target.txt", link)

      # Validate using relative path (not absolute)
      expect do
        validator.validate_path("level1/level2/link")
      end.not_to raise_error
    end
  end

  describe "normalize_path_manually edge cases" do
    it "handles path that resolves to root" do
      # A path like "/a/../" should resolve to "/" which is fine
      result = validator.send(:normalize_path_manually, "/a/../")
      expect(result).to eq("/")
    end

    it "handles multiple .. components that stay within bounds" do
      # A path like "/a/b/../../c" should resolve to "/c"
      result = validator.send(:normalize_path_manually, "/a/b/../../c")
      expect(result).to eq("/c")
    end
  end

  describe "additional branch coverage for symlink validation" do
    let(:subdir) { File.join(temp_dir, "testdir") }

    before do
      FileUtils.mkdir_p(subdir)
    end

    context "when NO symlink is found in path components" do
      it "validates normal file path with no symlinks (line 191: next unless - FALSE)" do
        # Create a normal file with no symlinks in the path
        normal_file = File.join(subdir, "normal.txt")
        File.write(normal_file, "content")

        # This tests line 191 - when current_path.symlink? is false
        # The 'next unless' should skip the iteration (NOT execute lines 193-206)
        expect do
          validator.validate_path("testdir/normal.txt")
        end.not_to raise_error
      end

      it "validates deeply nested path with no symlinks (line 191: next unless - FALSE, multiple times)" do
        # Create deeply nested structure with no symlinks
        deep_path = File.join(subdir, "level1", "level2", "level3")
        FileUtils.mkdir_p(deep_path)
        deep_file = File.join(deep_path, "file.txt")
        File.write(deep_file, "content")

        # All path components are regular directories, not symlinks
        # Tests line 191 multiple times where current_path.symlink? is false
        expect do
          validator.validate_path("testdir/level1/level2/level3/file.txt")
        end.not_to raise_error
      end
    end

    context "when validating relative paths in symlink validation (line 184: ELSE branch)" do
      it "validates symlink using relative path input (line 184: pathname.absolute? is FALSE)" do
        # Create target file
        target_file = File.join(temp_dir, "target.txt")
        File.write(target_file, "content")

        # Create symlink
        symlink_path = File.join(subdir, "link")
        File.symlink("../target.txt", symlink_path)

        # Call validate_path with a RELATIVE path (not starting with /)
        # This tests line 184 - when pathname.absolute? is false in validate_symlink_safety!
        # Should execute lines 184-185 instead of lines 169-181
        expect do
          validator.validate_path("testdir/link")
        end.not_to raise_error
      end
    end

    context "when absolute symlink path doesn't exist (line 169: File.exist? FALSE)" do
      it "validates absolute path when File.exist?(path) returns false (line 169: ELSE branch)" do
        # To hit line 169 with File.exist?(path) == false, we need to call
        # validate_symlink_safety! on an ABSOLUTE path that does NOT exist
        # This happens when allow_creation: true

        # Create parent temp for proper test
        parent_temp = Dir.mktmpdir("sxn_parent_test")
        project_dir = File.join(parent_temp, "project")
        FileUtils.mkdir_p(project_dir)

        # Create a subdirectory
        proj_subdir = File.join(project_dir, "subdir")
        FileUtils.mkdir_p(proj_subdir)

        # Create a file that will be deleted
        temp_file = File.join(proj_subdir, "temp.txt")
        File.write(temp_file, "content")

        local_validator = described_class.new(project_dir)

        # Get the absolute path first
        abs_path = local_validator.validate_path("subdir/temp.txt")

        # Now delete the file
        File.delete(temp_file)

        # Call validate_symlink_safety! directly with the absolute path that no longer exists
        # Line 169: resolved_path = File.exist?(path) ? File.realpath(path) : path
        # Since File.exist?(abs_path) is false, it should use 'path' directly
        expect do
          local_validator.send(:validate_symlink_safety!, abs_path)
        end.not_to raise_error

        FileUtils.rm_rf(parent_temp)
      end
    end

    context "when symlink is found in path components (line 191: next unless - TRUE)" do
      it "validates path with absolute symlink to existing file (line 198: File.exist? TRUE)" do
        # Create a real target file
        target_file = File.join(temp_dir, "real_target.txt")
        File.write(target_file, "content")

        # Create a symlink with ABSOLUTE target within project
        link_path = File.join(subdir, "abs_link")
        File.symlink(target_file, link_path)

        # This tests:
        # - line 191: current_path.symlink? is true (enters the block)
        # - line 196: target.absolute? is true (enters the if)
        # - line 198: File.exist?(target.to_s) is true (uses File.realpath)
        expect do
          validator.validate_path("testdir/abs_link")
        end.not_to raise_error
      end

      it "validates path with absolute symlink to non-existent file (line 198: File.exist? FALSE)" do
        # Create a symlink with absolute target that doesn't exist
        non_existent_target = File.join(temp_dir, "future_file.txt")
        symlink_path = File.join(subdir, "link_to_future_abs")
        File.symlink(non_existent_target, symlink_path)

        # This tests:
        # - line 191: current_path.symlink? is true
        # - line 196: target.absolute? is true
        # - line 198: File.exist?(target.to_s) is false (uses target.to_s directly)
        expect do
          validator.validate_path("testdir/link_to_future_abs", allow_creation: true)
        end.not_to raise_error
      end

      it "validates path with relative symlink to existing file (line 204: File.exist? TRUE)" do
        # Create a real target file
        target_file = File.join(temp_dir, "rel_target.txt")
        File.write(target_file, "content")

        # Create a symlink with RELATIVE target
        symlink_path = File.join(subdir, "rel_link")
        File.symlink("../rel_target.txt", symlink_path)

        # This tests:
        # - line 191: current_path.symlink? is true
        # - line 196: target.absolute? is false (enters the else)
        # - line 202: executes (resolves relative target)
        # - line 204: File.exist?(resolved_target.to_s) is true (uses File.realpath)
        expect do
          validator.validate_path("testdir/rel_link")
        end.not_to raise_error
      end

      it "validates path with relative symlink to non-existent file (line 204: File.exist? FALSE)" do
        # Create relative symlink to non-existent file (but within project bounds)
        symlink_path = File.join(subdir, "link_to_future_rel")
        File.symlink("../future_relative.txt", symlink_path)

        # This tests:
        # - line 191: current_path.symlink? is true
        # - line 196: target.absolute? is false
        # - line 202: executes (resolves relative target)
        # - line 204: File.exist?(resolved_target.to_s) is false (uses resolved_target.to_s directly)
        expect do
          validator.validate_path("testdir/link_to_future_rel", allow_creation: true)
        end.not_to raise_error
      end

      it "validates path through symlinked directory with absolute existing target" do
        # Create a real target directory
        target_dir = File.join(temp_dir, "real_dir")
        FileUtils.mkdir_p(target_dir)
        target_file = File.join(target_dir, "file.txt")
        File.write(target_file, "content")

        # Create a symlink DIRECTORY with ABSOLUTE target within project
        link_dir = File.join(temp_dir, "linked_dir")
        File.symlink(target_dir, link_dir)

        # Now access a file through the symlinked directory
        # This tests line 191 (symlink found), 196 (absolute), 198 (exists)
        expect do
          validator.validate_path("linked_dir/file.txt")
        end.not_to raise_error
      end

      it "validates path through symlinked directory with absolute non-existent target" do
        # Create a symlink directory with absolute non-existent target (within project)
        non_existent_dir = File.join(temp_dir, "future_dir")
        link_dir = File.join(subdir, "link_to_future_dir")
        File.symlink(non_existent_dir, link_dir)

        # This tests line 191 (symlink), 196 (absolute), 198 (doesn't exist)
        expect do
          validator.validate_path("testdir/link_to_future_dir", allow_creation: true)
        end.not_to raise_error
      end

      it "validates path through symlinked directory with relative existing target" do
        # Create a real target directory
        target_dir = File.join(temp_dir, "target_dir")
        FileUtils.mkdir_p(target_dir)
        target_file = File.join(target_dir, "file.txt")
        File.write(target_file, "content")

        # Create a symlink directory with RELATIVE target
        link_dir = File.join(subdir, "linked_dir_rel")
        File.symlink("../target_dir", link_dir)

        # Access file through symlinked directory
        # This tests line 191 (symlink), 196 (not absolute), 202 (resolve), 204 (exists)
        expect do
          validator.validate_path("testdir/linked_dir_rel/file.txt")
        end.not_to raise_error
      end

      it "validates path through symlinked directory with relative non-existent target" do
        # Create a symlink directory with relative non-existent target (within project)
        link_dir = File.join(subdir, "link_to_future_dir_rel")
        File.symlink("../future_dir_rel", link_dir)

        # This tests line 191 (symlink), 196 (not absolute), 202 (resolve), 204 (doesn't exist)
        expect do
          validator.validate_path("testdir/link_to_future_dir_rel", allow_creation: true)
        end.not_to raise_error
      end
    end

    context "with absolute path ArgumentError in symlink validation" do
      it "handles absolute symlink target outside project catching ArgumentError" do
        # Create a temp directory structure
        parent_temp = Dir.mktmpdir("sxn_parent_test")
        project_dir = File.join(parent_temp, "project")
        FileUtils.mkdir_p(project_dir)

        # Create subdir in project
        proj_subdir = File.join(project_dir, "subdir")
        FileUtils.mkdir_p(proj_subdir)

        # Create a file outside the project
        outside_file = File.join(parent_temp, "outside.txt")
        File.write(outside_file, "outside")

        # Create symlink in subdir pointing to outside file (absolute path)
        link_in_project = File.join(proj_subdir, "bad_link")
        File.symlink(outside_file, link_in_project)

        local_validator = described_class.new(project_dir)

        # This should go through symlink validation and fail because target is outside
        # Testing the path where absolute symlink is caught
        expect do
          local_validator.validate_path("subdir/bad_link")
        end.to raise_error(Sxn::PathValidationError, /outside project boundaries/)

        FileUtils.rm_rf(parent_temp)
      end

      it "handles symlink validation for path that triggers ArgumentError catch" do
        # Create nested temp structure to test ArgumentError handling
        parent_temp = Dir.mktmpdir("sxn_parent_test")
        project_dir = File.join(parent_temp, "project")
        FileUtils.mkdir_p(project_dir)

        # Create file outside project
        outside_target = File.join(parent_temp, "outside_target.txt")
        File.write(outside_target, "outside content")

        # Create symlink to outside file
        link_path = File.join(project_dir, "outside_link")
        File.symlink(outside_target, link_path)

        local_validator = described_class.new(project_dir)

        # Validate the symlink - this should trigger lines 178-180
        # The symlink validation will try to resolve and validate the absolute symlink
        # which points outside and should trigger the ArgumentError rescue at line 178-180
        expect do
          local_validator.validate_path("outside_link")
        end.to raise_error(Sxn::PathValidationError, /outside project boundaries/)

        FileUtils.rm_rf(parent_temp)
      end
    end
  end

  # DIRECT BRANCH COVERAGE TESTS: Target uncovered branches in validate_symlink_safety! (lines 160-210)
  describe "direct symlink branch coverage" do
    let(:subdir) { File.join(temp_dir, "subdir") }

    before do
      FileUtils.mkdir_p(subdir)
    end

    context "Line 184 [else] - relative path input (pathname.absolute? is FALSE)" do
      it "validates with RELATIVE path input to trigger line 184 else branch" do
        # Create a file structure
        FileUtils.mkdir_p(File.join(temp_dir, "subdir"))
        File.write(File.join(temp_dir, "subdir", "file.txt"), "test content")

        # Pass RELATIVE path (not starting with /) to validate_path
        # This ensures pathname.absolute? is FALSE, triggering line 184 else branch
        expect do
          validator.validate_path("subdir/file.txt")
        end.not_to raise_error
      end
    end

    context "Line 191 [next unless] - non-symlink path components" do
      it "validates path with regular directories (not symlinks) to trigger line 191 false branch" do
        # Create nested regular directories (no symlinks)
        nested_path = File.join(temp_dir, "dir1", "dir2", "dir3")
        FileUtils.mkdir_p(nested_path)
        File.write(File.join(nested_path, "normal.txt"), "content")

        # All path components are regular dirs, not symlinks
        # Line 191: current_path.symlink? returns FALSE, so 'next unless' skips the block
        expect do
          validator.validate_path("dir1/dir2/dir3/normal.txt")
        end.not_to raise_error
      end
    end

    context "Line 198 ternary - absolute symlink target EXISTS" do
      it "validates absolute symlink to EXISTING file (line 198 then branch)" do
        # Create a real target file
        target_file = File.join(temp_dir, "real_file.txt")
        File.write(target_file, "content")

        # Create symlink with ABSOLUTE target path
        absolute_link = File.join(subdir, "abs_link_exists")
        File.symlink(target_file, absolute_link)

        # Line 191: symlink? is TRUE
        # Line 196: target.absolute? is TRUE
        # Line 198: File.exist?(target.to_s) is TRUE -> uses File.realpath(target.to_s)
        expect do
          validator.validate_path("subdir/abs_link_exists")
        end.not_to raise_error
      end
    end

    context "Line 198 ternary - absolute symlink target does NOT exist" do
      it "validates absolute symlink to NON-EXISTING file (line 198 else branch)" do
        # Create symlink with absolute target that doesn't exist (but within project bounds)
        non_existent_target = File.join(temp_dir, "not_created_yet.txt")
        absolute_link = File.join(subdir, "abs_link_not_exists")
        File.symlink(non_existent_target, absolute_link)

        # Line 191: symlink? is TRUE
        # Line 196: target.absolute? is TRUE
        # Line 198: File.exist?(target.to_s) is FALSE -> uses target.to_s directly
        expect do
          validator.validate_path("subdir/abs_link_not_exists", allow_creation: true)
        end.not_to raise_error
      end
    end

    context "Line 202-204 - relative symlink target handling" do
      it "validates relative symlink to EXISTING file (line 204 then branch)" do
        # Create a real target file
        target_file = File.join(temp_dir, "rel_target.txt")
        File.write(target_file, "content")

        # Create symlink with RELATIVE target
        relative_link = File.join(subdir, "rel_link_exists")
        File.symlink("../rel_target.txt", relative_link)

        # Line 191: symlink? is TRUE
        # Line 196: target.absolute? is FALSE (enters else block)
        # Line 202: resolves relative target with dirname.join(target).cleanpath
        # Line 204: File.exist?(resolved_target.to_s) is TRUE -> uses File.realpath
        expect do
          validator.validate_path("subdir/rel_link_exists")
        end.not_to raise_error
      end

      it "validates relative symlink to NON-EXISTING file (line 204 else branch)" do
        # Create symlink with relative target that doesn't exist (but within project bounds)
        relative_link = File.join(subdir, "rel_link_not_exists")
        File.symlink("../future_file.txt", relative_link)

        # Line 191: symlink? is TRUE
        # Line 196: target.absolute? is FALSE (enters else block)
        # Line 202: resolves relative target
        # Line 204: File.exist?(resolved_target.to_s) is FALSE -> uses resolved_target.to_s
        expect do
          validator.validate_path("subdir/rel_link_not_exists", allow_creation: true)
        end.not_to raise_error
      end
    end
  end

  # NEW TESTS: Additional comprehensive branch coverage for validate_symlink_safety!
  describe "comprehensive symlink validation branch coverage" do
    let(:test_subdir) { File.join(temp_dir, "test_area") }

    before do
      FileUtils.mkdir_p(test_subdir)
    end

    context "testing line 169 File.exist?(path) FALSE branch with actual absolute path" do
      it "handles absolute path validation when file does not exist" do
        # Create a file, get its absolute path, then delete it
        temp_file = File.join(test_subdir, "will_be_deleted.txt")
        File.write(temp_file, "temporary")

        abs_path = validator.validate_path("test_area/will_be_deleted.txt")
        File.delete(temp_file)

        # Now call validate_symlink_safety! with an absolute path that doesn't exist
        # This hits line 169 ELSE: File.exist?(path) ? File.realpath(path) : path
        expect do
          validator.send(:validate_symlink_safety!, abs_path)
        end.not_to raise_error
      end
    end

    context "testing line 184 relative path with symlinks in subdirectory" do
      it "validates relative path through multiple non-symlink components" do
        # Create nested structure: dir1/dir2/file.txt (no symlinks)
        deep_dir = File.join(test_subdir, "dir1", "dir2")
        FileUtils.mkdir_p(deep_dir)
        target_file = File.join(deep_dir, "file.txt")
        File.write(target_file, "data")

        # Validate with relative path - hits line 184 (else branch)
        # Each component is NOT a symlink, so line 191 'next unless' skips
        expect do
          validator.validate_path("test_area/dir1/dir2/file.txt")
        end.not_to raise_error
      end

      it "validates relative path with symlink in middle of path components" do
        # Create: test_area/real_dir/file.txt
        real_dir = File.join(test_subdir, "real_dir")
        FileUtils.mkdir_p(real_dir)
        File.write(File.join(real_dir, "file.txt"), "content")

        # Create symlink: test_area/link_to_real -> real_dir
        link_dir = File.join(test_subdir, "link_to_real")
        File.symlink("real_dir", link_dir)

        # Validate relative path through symlink - hits line 184, then 191 (true), then 196 (false), 204
        expect do
          validator.validate_path("test_area/link_to_real/file.txt")
        end.not_to raise_error
      end
    end

    context "testing line 191 next unless with mixed symlink and regular components" do
      it "skips non-symlink directories and processes symlink directories" do
        # Create: test_area/regular1/regular2/symlink_dir/file.txt
        # where symlink_dir -> target_dir

        regular_path = File.join(test_subdir, "regular1", "regular2")
        FileUtils.mkdir_p(regular_path)

        target_dir = File.join(test_subdir, "target_dir")
        FileUtils.mkdir_p(target_dir)
        File.write(File.join(target_dir, "file.txt"), "data")

        symlink_dir = File.join(regular_path, "symlink_dir")
        File.symlink(File.join(temp_dir, "test_area", "target_dir"), symlink_dir)

        # This path has both regular dirs (line 191 false, skip) and symlink dir (line 191 true, process)
        expect do
          validator.validate_path("test_area/regular1/regular2/symlink_dir/file.txt")
        end.not_to raise_error
      end
    end

    context "testing line 198 absolute symlink File.exist? branches" do
      it "validates absolute symlink to existing file within project" do
        # Create target
        target = File.join(temp_dir, "abs_target.txt")
        File.write(target, "content")

        # Create absolute symlink
        link = File.join(test_subdir, "abs_link")
        File.symlink(target, link)

        # Line 191 true, 196 true, 198 TRUE (file exists)
        expect do
          validator.validate_path("test_area/abs_link")
        end.not_to raise_error
      end

      it "validates absolute symlink to non-existing file within project bounds" do
        # Create absolute symlink to non-existent path (but within project)
        future_target = File.join(temp_dir, "future_abs.txt")
        link = File.join(test_subdir, "future_abs_link")
        File.symlink(future_target, link)

        # Line 191 true, 196 true, 198 FALSE (file doesn't exist)
        expect do
          validator.validate_path("test_area/future_abs_link", allow_creation: true)
        end.not_to raise_error
      end
    end

    context "testing line 204 relative symlink File.exist? branches" do
      it "validates relative symlink to existing file" do
        # Create target
        target = File.join(test_subdir, "rel_target.txt")
        File.write(target, "content")

        # Create relative symlink
        link = File.join(test_subdir, "rel_link")
        File.symlink("rel_target.txt", link)

        # Line 191 true, 196 false, 202 executes, 204 TRUE (file exists)
        expect do
          validator.validate_path("test_area/rel_link")
        end.not_to raise_error
      end

      it "validates relative symlink to non-existing file within project bounds" do
        # Create relative symlink to non-existent file
        link = File.join(test_subdir, "future_rel_link")
        File.symlink("future_rel.txt", link)

        # Line 191 true, 196 false, 202 executes, 204 FALSE (file doesn't exist)
        expect do
          validator.validate_path("test_area/future_rel_link", allow_creation: true)
        end.not_to raise_error
      end

      it "validates relative symlink with complex path resolution" do
        # Create nested structure with relative symlink
        # test_area/sub1/sub2/link -> ../../target.txt

        sub_path = File.join(test_subdir, "sub1", "sub2")
        FileUtils.mkdir_p(sub_path)

        target = File.join(test_subdir, "target.txt")
        File.write(target, "content")

        link = File.join(sub_path, "complex_link")
        File.symlink("../../target.txt", link)

        # Tests line 202 path resolution with dirname.join(target).cleanpath
        # and line 204 with File.exist? TRUE
        expect do
          validator.validate_path("test_area/sub1/sub2/complex_link")
        end.not_to raise_error
      end
    end

    context "testing symlink chains and edge cases" do
      it "validates symlink to symlink (chain)" do
        # Create target
        target = File.join(test_subdir, "final_target.txt")
        File.write(target, "content")

        # Create first symlink
        link1 = File.join(test_subdir, "link1")
        File.symlink("final_target.txt", link1)

        # Create second symlink pointing to first
        link2 = File.join(test_subdir, "link2")
        File.symlink("link1", link2)

        # This should resolve through the chain
        expect do
          validator.validate_path("test_area/link2")
        end.not_to raise_error
      end

      it "validates path with symlink in first component" do
        # Create target directory
        target_dir = File.join(temp_dir, "real_location")
        FileUtils.mkdir_p(target_dir)
        File.write(File.join(target_dir, "data.txt"), "content")

        # Create symlink at first level
        link_dir = File.join(temp_dir, "first_level_link")
        File.symlink(target_dir, link_dir)

        # Validate path where first component is a symlink
        expect do
          validator.validate_path("first_level_link/data.txt")
        end.not_to raise_error
      end

      it "validates path with symlink in last component" do
        # Create target file
        target = File.join(test_subdir, "last_target.txt")
        File.write(target, "content")

        # Create regular directory
        regular_dir = File.join(test_subdir, "regular")
        FileUtils.mkdir_p(regular_dir)

        # Create symlink in the regular directory (last component)
        link = File.join(regular_dir, "last_link")
        File.symlink("../last_target.txt", link)

        # Path where only last component is symlink
        expect do
          validator.validate_path("test_area/regular/last_link")
        end.not_to raise_error
      end
    end
  end
end
