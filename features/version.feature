Feature: Version command
  As a developer
  I want to check the version of sxn
  So that I know which version I'm using

  Scenario: Show version
    When I run `sxn version`
    Then the exit status should be 0
    And the output should contain "sxn 0.1.0"

  Scenario: Show version with help
    When I run `sxn help version`
    Then the exit status should be 0
    And the output should contain "Show version information"