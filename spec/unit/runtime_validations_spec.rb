# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::RuntimeValidations do
  describe ".validate_thor_arguments" do
    context "with argument count validation" do
      it "validates correct argument count" do
        validations = { args: { count: 1..2 } }
        expect do
          described_class.validate_thor_arguments("test_command", ["arg1"], {}, validations)
        end.not_to raise_error
      end

      it "raises error for incorrect argument count" do
        validations = { args: { count: 1..2 } }
        expect do
          described_class.validate_thor_arguments("test_command", ["arg1", "arg2", "arg3"], {}, validations)
        end.to raise_error(ArgumentError, /expects 1..2 arguments, got 3/)
      end

      it "handles single count value" do
        validations = { args: { count: 1..1 } }
        expect do
          described_class.validate_thor_arguments("test_command", ["arg1"], {}, validations)
        end.not_to raise_error
      end

      it "handles no count validation" do
        validations = { args: {} }
        expect do
          described_class.validate_thor_arguments("test_command", ["arg1", "arg2", "arg3"], {}, validations)
        end.not_to raise_error
      end
    end

    context "with argument type validation" do
      it "validates correct argument types" do
        validations = { args: { types: [String, Integer] } }
        expect do
          described_class.validate_thor_arguments("test_command", ["string", 123], {}, validations)
        end.not_to raise_error
      end

      it "raises error for incorrect argument types" do
        validations = { args: { types: [String] } }
        expect do
          described_class.validate_thor_arguments("test_command", [123], {}, validations)
        end.to raise_error(TypeError, /argument 1 must be String/)
      end

      it "handles multiple type options" do
        validations = { args: { types: [[String, Integer]] } }
        expect do
          described_class.validate_thor_arguments("test_command", [123], {}, validations)
        end.not_to raise_error
      end

      it "uses last type for extra arguments" do
        validations = { args: { types: [String, Integer] } }
        expect do
          described_class.validate_thor_arguments("test_command", ["str", 1, 2], {}, validations)
        end.not_to raise_error
      end
    end

    context "with options validation" do
      it "validates boolean options" do
        validations = { options: { verbose: :boolean } }
        expect do
          described_class.validate_thor_arguments("test_command", [], { verbose: true }, validations)
        end.not_to raise_error
      end

      it "raises error for invalid boolean options" do
        validations = { options: { verbose: :boolean } }
        expect do
          described_class.validate_thor_arguments("test_command", [], { verbose: "yes" }, validations)
        end.to raise_error(TypeError, /option --verbose must be boolean/)
      end

      it "validates string options" do
        validations = { options: { name: :string } }
        expect do
          described_class.validate_thor_arguments("test_command", [], { name: "test" }, validations)
        end.not_to raise_error
      end

      it "raises error for invalid string options" do
        validations = { options: { name: :string } }
        expect do
          described_class.validate_thor_arguments("test_command", [], { name: 123 }, validations)
        end.to raise_error(TypeError, /option --name must be a string/)
      end

      it "validates integer options" do
        validations = { options: { count: :integer } }
        expect do
          described_class.validate_thor_arguments("test_command", [], { count: 5 }, validations)
        end.not_to raise_error
      end

      it "raises error for invalid integer options" do
        validations = { options: { count: :integer } }
        expect do
          described_class.validate_thor_arguments("test_command", [], { count: "five" }, validations)
        end.to raise_error(TypeError, /option --count must be an integer/)
      end

      it "validates array options" do
        validations = { options: { items: :array } }
        expect do
          described_class.validate_thor_arguments("test_command", [], { items: ["a", "b"] }, validations)
        end.not_to raise_error
      end

      it "raises error for invalid array options" do
        validations = { options: { items: :array } }
        expect do
          described_class.validate_thor_arguments("test_command", [], { items: "not_array" }, validations)
        end.to raise_error(TypeError, /option --items must be an array/)
      end

      it "allows nil options" do
        validations = { options: { name: :string } }
        expect do
          described_class.validate_thor_arguments("test_command", [], { name: nil }, validations)
        end.not_to raise_error
      end

      it "ignores unvalidated options" do
        validations = { options: { name: :string } }
        expect do
          described_class.validate_thor_arguments("test_command", [], { other: 123 }, validations)
        end.not_to raise_error
      end
    end

    context "with no validations" do
      it "returns true for any input" do
        result = described_class.validate_thor_arguments("test_command", ["any", "args"], { any: "options" }, {})
        expect(result).to be true
      end
    end
  end

  describe ".validate_and_coerce_type" do
    context "coercing to String" do
      it "converts values to string" do
        result = described_class.validate_and_coerce_type(123, String)
        expect(result).to eq("123")
      end

      it "keeps strings as strings" do
        result = described_class.validate_and_coerce_type("test", String)
        expect(result).to eq("test")
      end
    end

    context "coercing to Integer" do
      it "converts numeric strings to integer" do
        result = described_class.validate_and_coerce_type("123", Integer)
        expect(result).to eq(123)
      end

      it "keeps integers as integers" do
        result = described_class.validate_and_coerce_type(456, Integer)
        expect(result).to eq(456)
      end

      it "raises error for non-numeric strings" do
        expect do
          described_class.validate_and_coerce_type("abc", Integer, "test_context")
        end.to raise_error(TypeError, /Cannot coerce String to Integer in test_context/)
      end
    end

    context "coercing to Float" do
      it "converts numeric strings to float" do
        result = described_class.validate_and_coerce_type("123.45", Float)
        expect(result).to eq(123.45)
      end

      it "converts integers to float" do
        result = described_class.validate_and_coerce_type(123, Float)
        expect(result).to eq(123.0)
      end

      it "raises error for non-numeric strings" do
        expect do
          described_class.validate_and_coerce_type("abc", Float, "test_context")
        end.to raise_error(TypeError, /Cannot coerce String to Float in test_context/)
      end
    end

    context "coercing to Boolean" do
      it "converts truthy values to true" do
        expect(described_class.validate_and_coerce_type("yes", TrueClass)).to be true
        expect(described_class.validate_and_coerce_type(1, FalseClass)).to be true
      end

      it "converts falsy values to false" do
        expect(described_class.validate_and_coerce_type(nil, TrueClass)).to be false
        expect(described_class.validate_and_coerce_type(false, FalseClass)).to be false
      end

      it "handles Boolean type name" do
        # Create a mock class with name "Boolean"
        boolean_class = Class.new do
          def self.name
            "Boolean"
          end
        end
        expect(described_class.validate_and_coerce_type("yes", boolean_class)).to be true
      end
    end

    context "coercing to Array" do
      it "converts values to array" do
        result = described_class.validate_and_coerce_type("test", Array)
        expect(result).to eq(["test"])
      end

      it "keeps arrays as arrays" do
        result = described_class.validate_and_coerce_type([1, 2, 3], Array)
        expect(result).to eq([1, 2, 3])
      end
    end

    context "coercing to Hash" do
      it "keeps hashes as hashes" do
        result = described_class.validate_and_coerce_type({ a: 1 }, Hash)
        expect(result).to eq({ a: 1 })
      end

      it "converts non-hashes to empty hash" do
        result = described_class.validate_and_coerce_type("not_a_hash", Hash)
        expect(result).to eq({})
      end

      it "converts nil to empty hash" do
        result = described_class.validate_and_coerce_type(nil, Hash)
        expect(result).to eq({})
      end
    end

    context "with unknown types" do
      it "returns value unchanged" do
        custom_class = Class.new
        value = custom_class.new
        result = described_class.validate_and_coerce_type(value, custom_class.class)
        expect(result).to eq(value)
      end
    end
  end

  describe ".validate_template_variables" do
    context "with valid hash input" do
      it "returns all required categories" do
        variables = { session: { name: "test" }, project: { name: "proj" } }
        result = described_class.validate_template_variables(variables)
        
        expect(result).to have_key(:session)
        expect(result).to have_key(:project)
        expect(result).to have_key(:git)
        expect(result).to have_key(:user)
        expect(result).to have_key(:environment)
        expect(result).to have_key(:timestamp)
        expect(result).to have_key(:custom)
      end

      it "preserves existing values" do
        variables = { 
          session: { name: "test" },
          custom: { key: "value" }
        }
        result = described_class.validate_template_variables(variables)
        
        expect(result[:session]).to eq({ name: "test" })
        expect(result[:custom]).to eq({ key: "value" })
      end

      it "adds missing categories as empty hashes" do
        variables = { session: { name: "test" } }
        result = described_class.validate_template_variables(variables)
        
        expect(result[:project]).to eq({})
        expect(result[:git]).to eq({})
      end
    end

    context "with invalid input" do
      it "returns empty hash for non-hash input" do
        result = described_class.validate_template_variables("not a hash")
        
        # When input is not a hash, the method returns {} early
        expect(result).to eq({})
      end

      it "returns empty hash for nil input" do
        result = described_class.validate_template_variables(nil)
        
        # When input is nil, the method returns {} early
        expect(result).to eq({})
      end

      it "converts non-hash values to empty hashes" do
        variables = { 
          session: "not a hash",
          project: nil,
          git: 123
        }
        result = described_class.validate_template_variables(variables)
        
        expect(result[:session]).to eq({})
        expect(result[:project]).to eq({})
        expect(result[:git]).to eq({})
      end
    end
  end
end