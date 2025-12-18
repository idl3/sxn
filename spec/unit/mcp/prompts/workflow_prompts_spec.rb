# frozen_string_literal: true

require "spec_helper"
require "sxn/mcp"

RSpec.describe "Sxn::MCP::Prompts::WorkflowPrompts" do
  describe Sxn::MCP::Prompts::NewSession do
    describe "class configuration" do
      it "has the correct prompt name" do
        expect(described_class.name_value).to eq("new-session")
      end

      it "has a description" do
        expect(described_class.description_value).to eq("Guided workflow for creating a new development session")
      end

      it "defines task_description argument" do
        args = described_class.arguments_value
        task_desc_arg = args.find { |a| a.name == "task_description" }

        expect(task_desc_arg).not_to be_nil
        expect(task_desc_arg.description).to eq("Brief description of what you're working on")
        expect(task_desc_arg.required).to be false
      end

      it "defines projects argument" do
        args = described_class.arguments_value
        projects_arg = args.find { |a| a.name == "projects" }

        expect(projects_arg).not_to be_nil
        expect(projects_arg.description).to eq("Comma-separated list of projects to include")
        expect(projects_arg.required).to be false
      end

      it "has two arguments defined" do
        expect(described_class.arguments_value.length).to eq(2)
      end
    end

    describe ".template" do
      context "with all arguments provided" do
        it "includes task description in the output" do
          result = described_class.template({
                                              "task_description" => "Add user authentication",
                                              "projects" => "backend, frontend"
                                            })

          expect(result).to include("Add user authentication")
          expect(result).to include("backend, frontend")
        end

        it "handles symbol keys" do
          result = described_class.template({
                                              task_description: "Fix bug in API",
                                              projects: "api-service"
                                            })

          expect(result).to include("Fix bug in API")
          expect(result).to include("api-service")
        end

        it "handles mixed string and symbol keys" do
          result = described_class.template({
                                              "task_description" => "Refactor database layer",
                                              projects: "backend"
                                            })

          expect(result).to include("Refactor database layer")
          expect(result).to include("backend")
        end
      end

      context "with partial arguments" do
        it "handles only task_description provided" do
          result = described_class.template({
                                              "task_description" => "Build new feature"
                                            })

          expect(result).to include("Build new feature")
          expect(result).to include("Not specified")
        end

        it "handles only projects provided" do
          result = described_class.template({
                                              "projects" => "web, mobile"
                                            })

          expect(result).to include("Not provided")
          expect(result).to include("web, mobile")
        end
      end

      context "with no arguments" do
        it "handles empty hash" do
          result = described_class.template({})

          expect(result).to include("Not provided")
          expect(result).to include("Not specified")
        end

        it "handles nil arguments" do
          result = described_class.template

          expect(result).to include("Not provided")
          expect(result).to include("Not specified")
        end
      end

      context "with comma-separated projects" do
        it "formats single project" do
          result = described_class.template({
                                              "projects" => "backend"
                                            })

          expect(result).to include("backend")
        end

        it "formats multiple projects" do
          result = described_class.template({
                                              "projects" => "backend,frontend,mobile"
                                            })

          expect(result).to include("backend, frontend, mobile")
        end

        it "trims whitespace from project names" do
          result = described_class.template({
                                              "projects" => " backend , frontend , mobile "
                                            })

          expect(result).to include("backend, frontend, mobile")
        end

        it "handles projects with extra spaces" do
          result = described_class.template({
                                              "projects" => "backend  ,  frontend"
                                            })

          expect(result).to include("backend, frontend")
        end
      end

      context "with nil values" do
        it "handles nil task_description" do
          result = described_class.template({
                                              "task_description" => nil,
                                              "projects" => "backend"
                                            })

          expect(result).to include("Not provided")
          expect(result).to include("backend")
        end

        it "handles nil projects" do
          result = described_class.template({
                                              "task_description" => "Test task",
                                              "projects" => nil
                                            })

          expect(result).to include("Test task")
          expect(result).to include("Not specified")
        end
      end

      context "with empty strings" do
        it "treats empty task_description as provided but empty" do
          result = described_class.template({
                                              "task_description" => "",
                                              "projects" => "backend"
                                            })

          expect(result).not_to include("Not provided")
          expect(result).to include("backend")
        end

        it "treats empty projects as empty string" do
          result = described_class.template({
                                              "task_description" => "Test",
                                              "projects" => ""
                                            })

          expect(result).to include("Test")
          # Empty string splits to empty array which joins to empty string
          expect(result).to include("Requested projects: \n")
        end
      end

      context "prompt structure" do
        let(:result) { described_class.template({ "task_description" => "Test", "projects" => "test-project" }) }

        it "includes the main heading" do
          expect(result).to include("# Create a New Development Session")
        end

        it "includes task information section" do
          expect(result).to include("## Task Information")
        end

        it "includes steps to complete section" do
          expect(result).to include("## Steps to Complete")
        end

        it "includes guidelines section" do
          expect(result).to include("## Guidelines")
        end

        it "mentions sxn_sessions_create" do
          expect(result).to include("sxn_sessions_create")
        end

        it "mentions sxn_worktrees_add" do
          expect(result).to include("sxn_worktrees_add")
        end

        it "mentions sxn_sessions_swap" do
          expect(result).to include("sxn_sessions_swap")
        end
      end

      context "with server_context parameter" do
        it "accepts and ignores server_context" do
          result = described_class.template(
            { "task_description" => "Test" },
            _server_context: { some: "context" }
          )

          expect(result).to include("Test")
        end
      end
    end
  end

  describe Sxn::MCP::Prompts::MultiRepoSetup do
    describe "class configuration" do
      it "has the correct prompt name" do
        expect(described_class.name_value).to eq("multi-repo-setup")
      end

      it "has a description" do
        expect(described_class.description_value).to eq("Set up a multi-repository development environment")
      end

      it "defines feature_name argument as required" do
        args = described_class.arguments_value
        feature_name_arg = args.find { |a| a.name == "feature_name" }

        expect(feature_name_arg).not_to be_nil
        expect(feature_name_arg.description).to eq("Name of the feature being developed across repos")
        expect(feature_name_arg.required).to be true
      end

      it "defines repos argument as optional" do
        args = described_class.arguments_value
        repos_arg = args.find { |a| a.name == "repos" }

        expect(repos_arg).not_to be_nil
        expect(repos_arg.description).to eq("Comma-separated list of repository names to include")
        expect(repos_arg.required).to be false
      end

      it "has two arguments defined" do
        expect(described_class.arguments_value.length).to eq(2)
      end
    end

    describe ".template" do
      context "with all arguments provided" do
        it "includes feature name in the output" do
          result = described_class.template({
                                              "feature_name" => "User Authentication",
                                              "repos" => "backend, frontend"
                                            })

          expect(result).to include("User Authentication")
          expect(result).to include("backend")
          expect(result).to include("frontend")
        end

        it "handles symbol keys" do
          result = described_class.template({
                                              feature_name: "Payment System",
                                              repos: "payment-service, api"
                                            })

          expect(result).to include("Payment System")
          expect(result).to include("payment-service")
          expect(result).to include("api")
        end

        it "handles mixed string and symbol keys" do
          result = described_class.template({
                                              "feature_name" => "Search Feature",
                                              repos: "search, indexer"
                                            })

          expect(result).to include("Search Feature")
          expect(result).to include("search")
          expect(result).to include("indexer")
        end
      end

      context "with feature_name only" do
        it "shows message about using sxn_projects_list" do
          result = described_class.template({
                                              "feature_name" => "New Feature"
                                            })

          expect(result).to include("New Feature")
          expect(result).to include("Will use sxn_projects_list to find available projects")
        end

        it "handles symbol key for feature_name" do
          result = described_class.template({
                                              feature_name: "API Refactor"
                                            })

          expect(result).to include("API Refactor")
          expect(result).to include("Will use sxn_projects_list")
        end
      end

      context "with comma-separated repos" do
        it "formats single repo" do
          result = described_class.template({
                                              "feature_name" => "Test",
                                              "repos" => "backend"
                                            })

          expect(result).to include("- backend")
        end

        it "formats multiple repos" do
          result = described_class.template({
                                              "feature_name" => "Test",
                                              "repos" => "backend,frontend,mobile"
                                            })

          expect(result).to include("- backend")
          expect(result).to include("- frontend")
          expect(result).to include("- mobile")
        end

        it "trims whitespace from repo names" do
          result = described_class.template({
                                              "feature_name" => "Test",
                                              "repos" => " backend , frontend , mobile "
                                            })

          expect(result).to include("- backend")
          expect(result).to include("- frontend")
          expect(result).to include("- mobile")
        end

        it "handles repos with extra spaces" do
          result = described_class.template({
                                              "feature_name" => "Test",
                                              "repos" => "backend  ,  frontend"
                                            })

          expect(result).to include("- backend")
          expect(result).to include("- frontend")
        end
      end

      context "with nil repos" do
        it "shows default message when repos is nil" do
          result = described_class.template({
                                              "feature_name" => "Test",
                                              "repos" => nil
                                            })

          expect(result).to include("Will use sxn_projects_list")
        end
      end

      context "with empty string repos" do
        it "shows default message when repos is empty string" do
          result = described_class.template({
                                              "feature_name" => "Test",
                                              "repos" => ""
                                            })

          expect(result).to include("Will use sxn_projects_list")
        end
      end

      context "feature name formatting" do
        it "converts feature name to lowercase session name" do
          result = described_class.template({
                                              "feature_name" => "User Authentication"
                                            })

          expect(result).to include("Name: user-authentication")
        end

        it "replaces spaces with hyphens" do
          result = described_class.template({
                                              "feature_name" => "Multi Word Feature Name"
                                            })

          expect(result).to include("Name: multi-word-feature-name")
        end

        it "handles multiple consecutive spaces" do
          result = described_class.template({
                                              "feature_name" => "Feature  With   Spaces"
                                            })

          expect(result).to include("Name: feature-with-spaces")
        end

        it "preserves existing hyphens" do
          result = described_class.template({
                                              "feature_name" => "user-auth-feature"
                                            })

          expect(result).to include("Name: user-auth-feature")
        end

        it "handles mixed case with special spacing" do
          result = described_class.template({
                                              "feature_name" => "API V2 Integration"
                                            })

          expect(result).to include("Name: api-v2-integration")
        end
      end

      context "prompt structure" do
        let(:result) { described_class.template({ "feature_name" => "Test Feature", "repos" => "test-repo" }) }

        it "includes the main heading" do
          expect(result).to include("# Multi-Repository Development Setup")
        end

        it "includes the feature name with bold formatting" do
          expect(result).to include("**Test Feature**")
        end

        it "includes repositories to include section" do
          expect(result).to include("## Repositories to Include")
        end

        it "includes setup process section" do
          expect(result).to include("## Setup Process")
        end

        it "includes best practices section" do
          expect(result).to include("## Best Practices")
        end

        it "mentions sxn_projects_list" do
          expect(result).to include("sxn_projects_list")
        end

        it "mentions sxn_sessions_create" do
          expect(result).to include("sxn_sessions_create")
        end

        it "mentions sxn_worktrees_add" do
          expect(result).to include("sxn_worktrees_add")
        end

        it "mentions sxn_rules_apply" do
          expect(result).to include("sxn_rules_apply")
        end

        it "mentions sxn_sessions_swap" do
          expect(result).to include("sxn_sessions_swap")
        end
      end

      context "with server_context parameter" do
        it "accepts and ignores server_context" do
          result = described_class.template(
            { "feature_name" => "Test" },
            _server_context: { some: "context" }
          )

          expect(result).to include("Test")
        end
      end

      context "edge cases" do
        it "handles feature_name with only spaces" do
          result = described_class.template({
                                              "feature_name" => "   "
                                            })

          # All spaces get replaced with single hyphen then collapsed
          expect(result).to include("Name: -")
        end

        it "handles single word feature name" do
          result = described_class.template({
                                              "feature_name" => "Authentication"
                                            })

          expect(result).to include("Name: authentication")
        end

        it "handles feature name with tabs and newlines" do
          result = described_class.template({
                                              "feature_name" => "Feature\tWith\nWhitespace"
                                            })

          # \s+ matches all whitespace including tabs and newlines
          expect(result).to include("Name: feature-with-whitespace")
        end

        it "handles single repo in list" do
          result = described_class.template({
                                              "feature_name" => "Test",
                                              "repos" => "single-repo"
                                            })

          expect(result).to include("- single-repo")
          expect(result).not_to include("Will use sxn_projects_list")
        end

        it "handles repos with trailing comma" do
          result = described_class.template({
                                              "feature_name" => "Test",
                                              "repos" => "backend,frontend,"
                                            })

          expect(result).to include("- backend")
          expect(result).to include("- frontend")
          # Empty string after trailing comma gets stripped and filtered
        end
      end
    end
  end

  describe "MCP::Prompt integration" do
    it "NewSession inherits from MCP::Prompt" do
      expect(Sxn::MCP::Prompts::NewSession.ancestors).to include(MCP::Prompt)
    end

    it "MultiRepoSetup inherits from MCP::Prompt" do
      expect(Sxn::MCP::Prompts::MultiRepoSetup.ancestors).to include(MCP::Prompt)
    end

    it "NewSession can be converted to hash" do
      hash = Sxn::MCP::Prompts::NewSession.to_h
      expect(hash).to include(:name, :description)
      expect(hash[:name]).to eq("new-session")
    end

    it "MultiRepoSetup can be converted to hash" do
      hash = Sxn::MCP::Prompts::MultiRepoSetup.to_h
      expect(hash).to include(:name, :description)
      expect(hash[:name]).to eq("multi-repo-setup")
    end
  end
end
