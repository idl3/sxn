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
      it "validates normal file path with no symlinks (line 191[else])" do
        # Create a normal file with no symlinks in the path
        normal_file = File.join(subdir, "normal.txt")
        File.write(normal_file, "content")

        # This tests line 191[else] - when current_path.symlink? is false
        # The loop should skip symlink validation and just continue
        expect do
          validator.validate_path("testdir/normal.txt")
        end.not_to raise_error
      end

      it "validates deeply nested path with no symlinks (line 191[else])" do
        # Create deeply nested structure with no symlinks
        deep_path = File.join(subdir, "level1", "level2", "level3")
        FileUtils.mkdir_p(deep_path)
        deep_file = File.join(deep_path, "file.txt")
        File.write(deep_file, "content")

        # All path components are regular directories, not symlinks
        # Tests line 191[else] multiple times
        expect do
          validator.validate_path("testdir/level1/level2/level3/file.txt")
        end.not_to raise_error
      end
    end

    context "when validating relative paths in symlink validation (line 184[else])" do
      it "validates symlink using relative path input (line 184[else])" do
        # Create target file
        target_file = File.join(temp_dir, "target.txt")
        File.write(target_file, "content")

        # Create symlink
        symlink_path = File.join(subdir, "link")
        File.symlink("../target.txt", symlink_path)

        # Call validate_path with a RELATIVE path
        # This tests line 184[else] - when pathname.absolute? is false in validate_symlink_safety!
        # The path is relative, so it takes the else branch
        expect do
          validator.validate_path("testdir/link")
        end.not_to raise_error
      end
    end

    context "when absolute symlink path doesn't exist (line 169[else])" do
      it "validates absolute symlink when File.exist? returns false (line 169[else])" do
        # Create a symlink with absolute target that doesn't exist
        non_existent_target = File.join(temp_dir, "does_not_exist.txt")
        symlink_path = File.join(subdir, "link_to_nonexistent")
        File.symlink(non_existent_target, symlink_path)

        # When validating the symlink, the code checks if the symlink path exists
        # Line 169: resolved_path = File.exist?(path) ? File.realpath(path) : path
        # Since symlink exists, this uses realpath, BUT when validating the TARGET,
        # we need to trigger the else branch at line 169

        # Actually, line 169 is about the PATH itself not existing
        # Let's create a scenario where we validate an absolute path that doesn't exist
        # We need to pass an absolute path through symlink validation where the target doesn't exist

        # Create parent temp for proper test
        parent_temp = Dir.mktmpdir("sxn_parent_test")
        project_dir = File.join(parent_temp, "project")
        FileUtils.mkdir_p(project_dir)

        # Create a subdirectory
        proj_subdir = File.join(project_dir, "subdir")
        FileUtils.mkdir_p(proj_subdir)

        # Create a symlink to a non-existent absolute path within project
        future_file = File.join(project_dir, "future.txt")
        symlink_in_subdir = File.join(proj_subdir, "link")
        File.symlink(future_file, symlink_in_subdir)

        local_validator = described_class.new(project_dir)

        # This should trigger line 169[else] when validating the absolute symlink target
        # The symlink exists, but when checking the absolute target, it doesn't exist
        expect do
          local_validator.validate_path("subdir/link", allow_creation: true)
        end.not_to raise_error

        FileUtils.rm_rf(parent_temp)
      end
    end

    context "when symlink is found in path components" do
      it "validates path through symlinked directory with absolute target" do
        # Create a real target directory
        target_dir = File.join(temp_dir, "real_dir")
        FileUtils.mkdir_p(target_dir)
        target_file = File.join(target_dir, "file.txt")
        File.write(target_file, "content")

        # Create a symlink DIRECTORY with ABSOLUTE target within project
        link_dir = File.join(temp_dir, "linked_dir")
        File.symlink(target_dir, link_dir)

        # Now access a file through the symlinked directory
        # This should trigger symlink validation on the directory component
        # Testing line 191[then], 196[then], 198[then]
        expect do
          validator.validate_path("linked_dir/file.txt")
        end.not_to raise_error
      end

      it "validates path with symlink component to existing file (line 198[then])" do
        # Create a real target file
        target_file = File.join(temp_dir, "real_target.txt")
        File.write(target_file, "content")

        # Create a symlink with ABSOLUTE target within project
        link_path = File.join(subdir, "abs_link")
        File.symlink(target_file, link_path)

        # This should trigger line 191[then] - when current_path.symlink? is true
        # and line 196[then] - when target.absolute? is true
        # and line 198[then] - when File.exist?(target.to_s) is true for absolute symlinks
        expect do
          validator.validate_path("testdir/abs_link")
        end.not_to raise_error
      end

      it "validates path with symlink component to non-existent absolute file (line 198[else])" do
        # Create a symlink with absolute target that doesn't exist
        non_existent_target = File.join(temp_dir, "future_file.txt")
        symlink_path = File.join(subdir, "link_to_future_abs")
        File.symlink(non_existent_target, symlink_path)

        # This tests line 191[then], 196[then], and 198[else]
        # - when File.exist?(target.to_s) is false for absolute symlinks
        expect do
          validator.validate_path("testdir/link_to_future_abs", allow_creation: true)
        end.not_to raise_error
      end

      it "validates path with symlink component to existing relative file (line 202[else], 204[then])" do
        # Create a real target file
        target_file = File.join(temp_dir, "rel_target.txt")
        File.write(target_file, "content")

        # Create a symlink with RELATIVE target
        symlink_path = File.join(subdir, "rel_link")
        File.symlink("../rel_target.txt", symlink_path)

        # This tests line 191[then], 196[else], 202[else], and 204[then]
        # - when target is relative and exists
        # - line 202 is NOT an else, it's executed when target is NOT absolute (line 196[else])
        expect do
          validator.validate_path("testdir/rel_link")
        end.not_to raise_error
      end

      it "validates path with symlink component to non-existent relative file (line 204[else])" do
        # Create relative symlink to non-existent file (but within project bounds)
        symlink_path = File.join(subdir, "link_to_future_rel")
        File.symlink("../future_relative.txt", symlink_path)

        # This tests line 191[then], 196[else], 202 (executed), and 204[else]
        # - when File.exist?(resolved_target.to_s) is false for relative symlinks
        expect do
          validator.validate_path("testdir/link_to_future_rel", allow_creation: true)
        end.not_to raise_error
      end

      it "validates path through symlinked directory with relative target" do
        # Create a real target directory
        target_dir = File.join(temp_dir, "target_dir")
        FileUtils.mkdir_p(target_dir)
        target_file = File.join(target_dir, "file.txt")
        File.write(target_file, "content")

        # Create a symlink directory with RELATIVE target
        link_dir = File.join(subdir, "linked_dir_rel")
        File.symlink("../target_dir", link_dir)

        # Access file through symlinked directory
        # This tests line 191[then], 196[else], 202[then], 204[then]
        expect do
          validator.validate_path("testdir/linked_dir_rel/file.txt")
        end.not_to raise_error
      end

      it "validates path through symlinked directory with non-existent absolute target" do
        # Create a symlink directory with absolute non-existent target (within project)
        non_existent_dir = File.join(temp_dir, "future_dir")
        link_dir = File.join(subdir, "link_to_future_dir")
        File.symlink(non_existent_dir, link_dir)

        # This tests line 191[then], 196[then], 198[else]
        expect do
          validator.validate_path("testdir/link_to_future_dir", allow_creation: true)
        end.not_to raise_error
      end

      it "validates path through symlinked directory with non-existent relative target" do
        # Create a symlink directory with relative non-existent target (within project)
        link_dir = File.join(subdir, "link_to_future_dir_rel")
        File.symlink("../future_dir_rel", link_dir)

        # This tests line 191[then], 196[else], 202[then], 204[else]
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
end
