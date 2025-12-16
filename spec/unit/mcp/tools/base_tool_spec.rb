# frozen_string_literal: true

require "spec_helper"
require "sxn/mcp"

RSpec.describe Sxn::MCP::Tools::BaseTool do
  describe "ErrorMapping" do
    describe ".wrap" do
      it "passes through successful operations" do
        result = described_class::ErrorMapping.wrap { "success" }
        expect(result).to eq("success")
      end

      it "converts SessionNotFoundError to error response" do
        result = described_class::ErrorMapping.wrap do
          raise Sxn::SessionNotFoundError, "Session 'test' not found"
        end

        expect(result).to be_a(MCP::Tool::Response)
        expect(result.error?).to be true
        expect(result.content.first[:text]).to include("not found")
        expect(result.content.first[:text]).to include("Session 'test' not found")
      end

      it "converts ProjectNotFoundError to error response" do
        result = described_class::ErrorMapping.wrap do
          raise Sxn::ProjectNotFoundError, "Project 'test' not found"
        end

        expect(result.error?).to be true
        expect(result.content.first[:text]).to include("not found")
      end

      it "converts ConfigurationError to error response with init hint" do
        result = described_class::ErrorMapping.wrap do
          raise Sxn::ConfigurationError, "Not initialized"
        end

        expect(result.error?).to be true
        expect(result.content.first[:text]).to include("sxn init")
      end

      it "converts WorktreeError to error response" do
        result = described_class::ErrorMapping.wrap do
          raise Sxn::WorktreeError, "Worktree problem"
        end

        expect(result.error?).to be true
        expect(result.content.first[:text]).to include("Worktree error")
      end

      it "converts unexpected errors to error response" do
        result = described_class::ErrorMapping.wrap do
          raise StandardError, "Something went wrong"
        end

        expect(result.error?).to be true
        expect(result.content.first[:text]).to include("Unexpected error")
      end
    end
  end

  describe ".ensure_initialized!" do
    it "returns true when config_manager is present" do
      server_context = { config_manager: double("ConfigManager") }
      expect(described_class.ensure_initialized!(server_context)).to be true
    end

    it "returns false when config_manager is nil" do
      server_context = { config_manager: nil }
      expect(described_class.ensure_initialized!(server_context)).to be false
    end
  end

  describe ".not_initialized_response" do
    it "returns an error response with init hint" do
      response = described_class.not_initialized_response
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("not initialized")
    end
  end

  describe ".text_response" do
    it "creates a text response" do
      response = described_class.text_response("Hello, world!")
      expect(response).to be_a(MCP::Tool::Response)
      expect(response.error?).to be false
      expect(response.content.first[:type]).to eq("text")
      expect(response.content.first[:text]).to eq("Hello, world!")
    end
  end

  describe ".json_response" do
    it "creates a JSON response" do
      data = { foo: "bar", count: 42 }
      response = described_class.json_response(data)

      expect(response).to be_a(MCP::Tool::Response)
      expect(response.error?).to be false
      expect(response.content.first[:type]).to eq("text")
      expect(JSON.parse(response.content.first[:text])).to include("foo" => "bar", "count" => 42)
    end

    it "includes summary when provided" do
      data = { foo: "bar" }
      response = described_class.json_response(data, summary: "Here's the data:")

      expect(response.content.length).to eq(2)
      expect(response.content.first[:text]).to eq("Here's the data:")
    end
  end

  describe ".error_response" do
    it "creates an error response" do
      response = described_class.error_response("Something went wrong")
      expect(response.error?).to be true
      expect(response.content.first[:text]).to eq("Something went wrong")
    end
  end
end
