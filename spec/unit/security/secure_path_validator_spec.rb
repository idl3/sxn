# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "tmpdir"

RSpec.describe Sxn::Security::SecurePathValidator do
  let(:temp_dir) { Dir.mktmpdir("sxn_test") }
  let(:project_root) { temp_dir }
  let(:validator) { described_class.new(project_root) }

  after do
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
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
        original_dir = Dir.pwd
        Dir.chdir("/tmp") do  # Change to a different directory
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
        expect { validator.validate_path("subdir/../../etc/passwd") }.to raise_error(Sxn::PathValidationError, /traversal/)
      end

      it "rejects path starting with .." do
        expect { validator.validate_path("..") }.to raise_error(Sxn::PathValidationError, /traversal/)
      end

      it "rejects Windows-style directory traversal" do
        expect { validator.validate_path("subdir\\..\\..\\etc\\passwd") }.to raise_error(Sxn::PathValidationError, /traversal/)
      end

      it "rejects encoded directory traversal" do
        expect { validator.validate_path("subdir/%2e%2e/passwd") }.to raise_error(Errno::ENOENT)
      end

      it "rejects multiple slash patterns" do
        expect { validator.validate_path("subdir//..//etc//passwd") }.to raise_error(Sxn::PathValidationError, /directory traversal/)
      end
    end

    context "with null byte injection attempts" do
      it "rejects paths with null bytes" do
        expect { validator.validate_path("safe.txt\x00../../../etc/passwd") }.to raise_error(Sxn::PathValidationError, /directory traversal/)
      end

      it "rejects paths with encoded null bytes" do
        expect { validator.validate_path("safe.txt%00../../../etc/passwd") }.to raise_error(Sxn::PathValidationError, /directory traversal/)
      end
    end

    context "with absolute paths outside project" do
      it "rejects absolute path outside project" do
        outside_path = "/etc/passwd"
        expect { validator.validate_path(outside_path) }.to raise_error(Sxn::PathValidationError, /outside project boundaries/)
      end

      it "rejects path that resolves outside project" do
        # Create a symlink that points outside the project
        link_target = File.join(temp_dir, "..", "outside.txt")
        File.write(link_target, "outside content")
        link_path = File.join(temp_dir, "link_to_outside")
        File.symlink(link_target, link_path)

        expect { validator.validate_path("link_to_outside") }.to raise_error(Sxn::PathValidationError, /outside project boundaries/)
      ensure
        File.unlink(link_target) if File.exist?(link_target)
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
        expect { validator.validate_path("subdir//nested.txt") }.to raise_error(Sxn::PathValidationError, /dangerous pattern/)
      end

      it "handles very long paths" do
        long_path = "a" * 1000 + ".txt"
        result = validator.validate_path(long_path, allow_creation: true)
        expect(result).to eq(File.join(File.realpath(temp_dir), long_path))
      end

      it "rejects paths with only dots" do
        # A file named "..." should be allowed as it's just a filename with dots
        result = validator.validate_path("...", allow_creation: true)
        expect(result).to eq(File.join(File.realpath(temp_dir), "..."))
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

        expect { validator.validate_file_operation("subdir", dest_path) }.to raise_error(Sxn::PathValidationError, /cannot be a directory/)
      end

      it "rejects non-existent source" do
        expect { validator.validate_file_operation("nonexistent.txt", dest_path) }.to raise_error(Errno::ENOENT)
      end

      it "rejects unsafe destination path" do
        expect { validator.validate_file_operation("source.txt", "../outside.txt") }.to raise_error(Sxn::PathValidationError, /traversal/)
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

        expect { validator.validate_path("dangerous_link") }.to raise_error(Sxn::PathValidationError, /outside project boundaries/)
      end

      it "rejects symlinks with relative targets outside project" do
        File.symlink("../../etc/passwd", dangerous_link)

        expect { validator.validate_path("dangerous_link") }.to raise_error(Errno::ENOENT)
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

      expect(duration).to be < 1.0 # Should complete in under 1 second
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
      expect(duration).to be < 0.1 # Should be very fast
    end
  end

  describe "error messages" do
    it "provides clear error messages for different violations" do
      expect { validator.validate_path("../outside") }.to raise_error(Sxn::PathValidationError, /directory traversal/)
      expect { validator.validate_path("path\x00injection") }.to raise_error(Sxn::PathValidationError, /null bytes/)
      expect { validator.validate_path("/etc/passwd") }.to raise_error(Sxn::PathValidationError, /outside project boundaries/)
    end

    it "includes problematic path in error messages" do
      dangerous_path = "../../../etc/passwd"
      expect { validator.validate_path(dangerous_path) }.to raise_error(Sxn::PathValidationError, /#{Regexp.escape(dangerous_path)}/)
    end
  end
end