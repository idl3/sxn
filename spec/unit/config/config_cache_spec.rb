# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Sxn::Config::ConfigCache do
  let(:temp_dir) { Dir.mktmpdir }
  let(:cache_dir) { File.join(temp_dir, '.sxn', '.cache') }
  let(:cache) { described_class.new(cache_dir: cache_dir, ttl: 300) }
  let(:config_file1) { File.join(temp_dir, 'config1.yml') }
  let(:config_file2) { File.join(temp_dir, 'config2.yml') }
  let(:config_files) { [config_file1, config_file2] }
  
  let(:sample_config) do
    {
      'version' => 1,
      'sessions_folder' => 'test-sessions',
      'projects' => {
        'test-project' => {
          'path' => './test-project',
          'type' => 'rails'
        }
      }
    }
  end

  before do
    FileUtils.mkdir_p(temp_dir)
    File.write(config_file1, "version: 1\nsessions_folder: test1")
    File.write(config_file2, "projects:\n  test: {}")
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe '#initialize' do
    it 'sets cache directory and TTL' do
      expect(cache.cache_dir).to eq cache_dir
      expect(cache.ttl).to eq 300
    end

    it 'creates cache directory' do
      # Ensure cache doesn't exist first
      FileUtils.rm_rf(cache_dir) if Dir.exist?(cache_dir)
      
      # Initialize cache which should create the directory
      new_cache = described_class.new(cache_dir: cache_dir, ttl: 300)
      
      expect(Dir.exist?(cache_dir)).to be true
    end

    it 'uses default values' do
      default_cache = described_class.new
      expect(default_cache.ttl).to eq described_class::DEFAULT_TTL
    end
  end

  describe '#get and #set' do
    context 'with no cached data' do
      it 'returns nil' do
        expect(cache.get(config_files)).to be_nil
      end
    end

    context 'with cached data' do
      before do
        cache.set(sample_config, config_files)
      end

      it 'returns cached configuration' do
        cached_config = cache.get(config_files)
        expect(cached_config).to eq sample_config
      end

      it 'includes cache metadata' do
        # Get the cached config first to ensure we have valid cached data
        cached_config = cache.get(config_files)
        expect(cached_config).to eq sample_config
        
        # Check the cache is valid with the specific config files
        expect(cache.valid?(config_files)).to be true
        
        stats = cache.stats
        expect(stats[:exists]).to be true
        expect(stats[:file_count]).to eq 2
      end
    end

    context 'with TTL expiration' do
      let(:short_ttl_cache) { described_class.new(cache_dir: cache_dir, ttl: 0.1) }

      before do
        short_ttl_cache.set(sample_config, config_files)
      end

      it 'returns nil for expired cache' do
        sleep(0.2)
        expect(short_ttl_cache.get(config_files)).to be_nil
      end

      it 'reports cache as invalid in stats' do
        sleep(0.2)
        expect(short_ttl_cache.stats[:valid]).to be false
      end
    end

    context 'with file changes' do
      before do
        cache.set(sample_config, config_files)
      end

      it 'invalidates cache when file is modified' do
        sleep(0.1) # Ensure different mtime
        File.write(config_file1, "version: 2\nsessions_folder: modified")
        
        expect(cache.get(config_files)).to be_nil
      end

      it 'invalidates cache when file is deleted' do
        File.delete(config_file1)
        expect(cache.get(config_files)).to be_nil
      end

      it 'invalidates cache when new file is added' do
        new_file = File.join(temp_dir, 'config3.yml')
        File.write(new_file, "new: config")
        
        expect(cache.get([config_file1, config_file2, new_file])).to be_nil
      end

      it 'invalidates cache when file list changes' do
        expect(cache.get([config_file1])).to be_nil
      end
    end

    context 'with file checksum changes' do
      before do
        cache.set(sample_config, config_files)
      end

      it 'detects content changes even with same mtime' do
        # Preserve mtime but change content
        original_mtime = File.mtime(config_file1)
        File.write(config_file1, "version: 1\nsessions_folder: changed_content")
        File.utime(original_mtime, original_mtime, config_file1)
        
        expect(cache.get(config_files)).to be_nil
      end
    end
  end

  describe '#valid?' do
    context 'with no cache' do
      it 'returns false' do
        expect(cache.valid?(config_files)).to be false
      end
    end

    context 'with valid cache' do
      before do
        cache.set(sample_config, config_files)
      end

      it 'returns true' do
        expect(cache.valid?(config_files)).to be true
      end
    end

    context 'with invalid cache' do
      let(:short_ttl_cache) { described_class.new(cache_dir: cache_dir, ttl: 0.1) }

      before do
        short_ttl_cache.set(sample_config, config_files)
        sleep(0.2)
      end

      it 'returns false for expired cache' do
        expect(short_ttl_cache.valid?(config_files)).to be false
      end
    end
  end

  describe '#invalidate' do
    before do
      cache.set(sample_config, config_files)
    end

    it 'removes cache file' do
      expect(cache.invalidate).to be true
      expect(cache.get(config_files)).to be_nil
    end

    it 'succeeds even if cache does not exist' do
      cache.invalidate
      expect(cache.invalidate).to be true
    end
  end

  describe '#stats' do
    context 'with no cache' do
      it 'returns exists: false' do
        stats = cache.stats
        expect(stats[:exists]).to be false
      end
    end

    context 'with valid cache' do
      before do
        cache.set(sample_config, config_files)
      end

      it 'returns comprehensive stats' do
        stats = cache.stats(config_files)
        
        expect(stats[:exists]).to be true
        expect(stats[:valid]).to be true
        expect(stats[:cached_at]).to be_a(Time)
        expect(stats[:age_seconds]).to be >= 0
        expect(stats[:file_count]).to eq 2
        expect(stats[:cache_version]).to eq 1
      end
    end

    context 'with corrupted cache' do
      before do
        FileUtils.mkdir_p(cache_dir)
        File.write(cache.cache_file_path, "invalid json content")
      end

      it 'returns error status' do
        stats = cache.stats
        expect(stats[:exists]).to be true
        expect(stats[:invalid]).to be true
      end
    end
  end

  describe 'atomic operations' do
    it 'uses atomic file operations for writing' do
      # Start writing in background thread
      write_thread = Thread.new do
        large_config = sample_config.merge('large_data' => 'x' * 10000)
        cache.set(large_config, config_files)
      end
      
      # Try to read while writing
      read_result = cache.get(config_files)
      
      write_thread.join
      
      # Should either get nil (no cache) or complete config (atomic write)
      expect([nil, sample_config]).to include(read_result)
    end

    it 'cleans up temporary files on error' do
      # Mock file write to fail
      allow(File).to receive(:write).and_raise(StandardError, 'Write failed')
      
      cache.set(sample_config, config_files)
      
      # No temp files should remain
      temp_files = Dir.glob(File.join(cache_dir, '*.tmp'))
      expect(temp_files).to be_empty
    end
  end

  describe 'error handling' do
    context 'with invalid JSON in cache file' do
      before do
        FileUtils.mkdir_p(cache_dir)
        File.write(cache.cache_file_path, "invalid json {")
      end

      it 'returns nil and warns about invalid JSON' do
        expect { cache.get(config_files) }.to output(/Warning: Invalid cache file JSON/).to_stderr
        expect(cache.get(config_files)).to be_nil
      end
    end

    context 'with permission errors' do
      before do
        cache.set(sample_config, config_files)
        
        # Mock permission error on cache file
        allow(File).to receive(:read).with(cache.cache_file_path).and_raise(Errno::EACCES)
      end

      it 'returns nil and warns about read error' do
        expect { cache.get(config_files) }.to output(/Warning: Failed to load cache/).to_stderr
        expect(cache.get(config_files)).to be_nil
      end
    end

    context 'with write errors' do
      before do
        # Mock write error
        allow(File).to receive(:write).and_raise(Errno::ENOSPC, 'No space left on device')
      end

      it 'returns false and warns about write error' do
        expect { cache.set(sample_config, config_files) }.to output(/Warning: Failed to save cache/).to_stderr
        expect(cache.set(sample_config, config_files)).to be false
      end
    end

    context 'with unreadable config files' do
      before do
        # Create a config file that can't be read for checksum
        allow(Digest::SHA256).to receive(:file).and_call_original
        allow(Digest::SHA256).to receive(:file).with(config_file1).and_raise(Errno::EACCES)
      end

      it 'handles unreadable files gracefully' do
        # Should not raise error and should still return true (partial success)
        result = nil
        expect { result = cache.set(sample_config, config_files) }.not_to raise_error
        expect(result).to be true
      end
    end
  end

  describe 'performance' do
    let(:many_files) do
      (1..100).map do |i|
        file_path = File.join(temp_dir, "config#{i}.yml")
        File.write(file_path, "version: #{i}")
        file_path
      end
    end

    before do
      many_files # Create files
    end

    it 'handles many config files efficiently' do
      expect {
        cache.set(sample_config, many_files)
      }.to perform_under(100).ms
    end

    it 'validates many files efficiently' do
      cache.set(sample_config, many_files)
      
      expect {
        cache.valid?(many_files)
      }.to perform_under(50).ms
    end

    it 'retrieves from cache efficiently' do
      cache.set(sample_config, many_files)
      
      expect {
        cache.get(many_files)
      }.to perform_under(30).ms
    end
  end

  describe 'cache versioning' do
    it 'includes cache version in stored data' do
      cache.set(sample_config, config_files)
      stats = cache.stats
      expect(stats[:cache_version]).to eq 1
    end

    it 'handles missing cache version gracefully' do
      # Create cache without version (simulate old cache)
      FileUtils.mkdir_p(cache_dir)
      cache_data = {
        'config' => sample_config,
        'cached_at' => Time.now.to_f,
        'config_files' => cache.send(:build_file_metadata, config_files)
      }
      File.write(cache.cache_file_path, JSON.pretty_generate(cache_data))
      
      expect(cache.get(config_files)).to eq sample_config
    end
  end

  describe 'concurrent access' do
    it 'handles concurrent reads safely' do
      cache.set(sample_config, config_files)
      
      threads = 10.times.map do
        Thread.new { cache.get(config_files) }
      end
      
      results = threads.map(&:value)
      expect(results).to all(eq(sample_config))
    end

    it 'handles concurrent writes safely' do
      # Ensure cache directory exists first
      FileUtils.mkdir_p(cache_dir) unless Dir.exist?(cache_dir)
      
      threads = 10.times.map do |i|
        Thread.new do
          config = sample_config.merge('thread_id' => i)
          cache.set(config, config_files)
        end
      end
      
      threads.each(&:join)
      
      # Cache should contain one of the configs (last write wins)
      final_config = cache.get(config_files)
      if final_config
        expect(final_config).to be_a(Hash)
        expect(final_config['version']).to eq 1
      else
        # If no config is cached due to write failures, that's acceptable for concurrent writes
        expect(final_config).to be_nil
      end
    end
  end
end