Feature: Rules System
  As a developer using sxn
  I want to apply project setup rules automatically
  So that new sessions are configured correctly with minimal manual effort

  Background:
    Given I have a Rails project with sensitive files
    And I have a session directory for testing

  Scenario: Applying basic copy files rule
    Given I have a rule configuration with file copying
    When I apply the rules using the rules engine
    Then the sensitive files should be copied to the session
    And the files should have secure permissions
    And the rule execution should be successful

  Scenario: Applying setup commands rule
    Given I have a rule configuration with setup commands
    When I apply the rules using the rules engine
    Then the commands should be executed in the session directory
    And the command output should be captured
    And the rule execution should be successful

  Scenario: Applying template processing rule
    Given I have a rule configuration with template processing
    And I have a session info template
    When I apply the rules using the rules engine
    Then the template should be processed with session variables
    And the output file should be created
    And the rule execution should be successful

  Scenario: Rules with dependencies execute in correct order
    Given I have a rule configuration with dependencies
    When I apply the rules using the rules engine
    Then the rules should execute in dependency order
    And all dependent rules should complete before dependents
    And the rule execution should be successful

  Scenario: Rule failure triggers rollback
    Given I have a rule configuration with a failing rule
    When I apply the rules using the rules engine
    Then the rule execution should fail
    And successful rules should be rolled back
    And the session should be clean

  Scenario: Project detection suggests appropriate rules
    Given I have a Rails project structure
    When I use the project detector
    Then it should detect the project as Rails
    And it should suggest Rails-specific rules
    And the suggested rules should be valid

  Scenario: Parallel execution of independent rules
    Given I have multiple independent rule configurations
    When I apply the rules with parallel execution enabled
    Then the rules should execute concurrently
    And all rules should complete successfully
    And the execution time should be optimized

  Scenario: Continue on failure option
    Given I have a rule configuration with continue on failure
    And one rule is configured to fail
    When I apply the rules using the rules engine
    Then the failing rule should be skipped
    And subsequent rules should still execute
    And the overall execution should continue

  Scenario: Sensitive file encryption
    Given I have a rule configuration with encryption enabled
    When I apply the rules using the rules engine
    Then the sensitive files should be encrypted
    And the files should have secure permissions
    And the encryption metadata should be tracked

  Scenario: Conditional command execution
    Given I have a rule configuration with conditional commands
    When I apply the rules using the rules engine
    Then commands should only execute when conditions are met
    And skipped commands should be logged
    And the rule execution should be successful