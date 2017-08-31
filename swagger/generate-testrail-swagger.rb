require 'net/http'
require 'uri'
require 'json'
require 'date'
require 'digest'

unless ARGV.size == 1
  puts "This script expects you to provide the base URL"
  puts " e.g. ruby #{__FILE__} https://example.testrail.net/index.php?/api/v2"
  puts "Received these instead: #{ARGV}"
  puts
  puts "You must also specify the following environment variables:"
  puts "  TESTRAIL_API_USER - the username of an account associated with the URL you provided"
  puts "  TESTRAIL_API_KEY - the auth key (or the actual password, if you have no regard for security) for this user"
  exit
end

def make_uri(method = nil)
  full_url = ARGV[0]
  full_url += "/#{method}" unless method.nil?
  URI.parse(full_url)
end

def get_testrail(method)
  uri = make_uri(method)
  request = Net::HTTP::Get.new(uri)
  request.basic_auth(ENV['TESTRAIL_API_USER'], ENV['TESTRAIL_API_KEY'])
  request.content_type = "application/json"

  req_options = {
    use_ssl: uri.scheme == "https",
  }

  response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
    http.request(request)
  end

  JSON.parse(response.body)
end

# field data types by testrail field type_id
#  1 string
#  2 integer
#  3 text
#  4 url (assumed string)
#  5 checkbox (assumed bool)
#  6 dropdown (assumed int)
#  7 user (assumed int)
#  8 date (assumed string)
#  9 milestone (assumed int)
# 10 step
# 11 step result (assumed int array)
# 12 multi-select (assumed int array)
def type_info(testrail_type_id)
  case testrail_type_id
  when 1, 3, 4, 8 then <<-EOYAML
        type: string
    EOYAML
  when 5 then <<-EOYAML
        type: boolean
    EOYAML
  when 2, 6, 7, 9 then <<-EOYAML
        type: integer
        format: int32
    EOYAML
  when 10 then <<-EOYAML
        type: array
        items:
          $ref: '#/definitions/Step'
    EOYAML
  when 11, 12 then <<-EOYAML
        type: array
        items:
          type: integer
          format: int32
    EOYAML
  end
end


base_uri = make_uri

output = <<EOYAML
swagger: '2.0'
info:
  title: TestRail API
  description: Integrate automated tests, submit test results and automate various aspects of TestRail
  version: "1.0.0"
# the domain of the service
host: #{base_uri.host}
# array of all schemes that your API supports
schemes:
  - #{base_uri.scheme}
# will be prefixed to all paths
basePath: #{base_uri.path}?#{base_uri.query}
produces:
  - application/json
securityDefinitions:
  UserSecurity:
    type: basic

security:
  - UserSecurity: []

paths:

  /get_case/{case_id}:
    get:
      summary: Returns an existing test case.
      parameters:
        - name: case_id
          in: path
          description: The ID of the test case
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
        - Readonly
        - Cases
      responses:
        200:
          description: A test case
          schema:
            $ref: '#/definitions/Case'
        400:
          description: Invalid or unknown test case
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_cases/{project_id}:
    get:
      summary: Returns a list of test cases for a test suite or specific section in a test suite.
      parameters:
        - name: project_id
          in: path
          description: The ID of the project
          required: true
          type: integer
          format: int32
        - name: suite_id
          in: query
          description: The ID of the test suite (optional if the project is operating in single suite mode)
          required: false
          type: integer
          format: int32
        - name: created_after
          in: query
          description: Only return test cases created after this date (as UNIX timestamp).
          required: false
          type: integer
          format: int32
        - name: created_before
          in: query
          description: Only return test cases created before this date (as UNIX timestamp).
          required: false
          type: integer
          format: int32
        - name: created_by
          in: query
          description: A comma-separated list of creators (user IDs) to filter by.
          required: false
          type: string
        - name: milestone_id
          in: query
          description: A comma-separated list of milestone IDs to filter by (not available if the milestone field is disabled for the project).
          required: false
          type: string
        - name: priority_id
          in: query
          description: A comma-separated list of priority IDs to filter by.
          required: false
          type: string
        - name: template_id
          in: query
          description: A comma-separated list of template IDs to filter by (requires TestRail 5.2 or later)
          required: false
          type: string
        - name: type_id
          in: query
          description: A comma-separated list of case type IDs to filter by.
          required: false
          type: string
        - name: updated_after
          in: query
          description: Only return test cases updated after this date (as UNIX timestamp).
          required: false
          type: integer
          format: int32
        - name: updated_before
          in: query
          description: Only return test cases updated before this date (as UNIX timestamp).
          required: false
          type: integer
          format: int32
        - name: updated_by
          in: query
          description: A comma-separated list of user IDs who updated test cases, to filter by
          required: false
          type: string
      tags:
        - TestRail
        - Cases
        - Readonly
      responses:
        200:
          description: Test cases
          schema:
            type: array
            items:
              $ref: '#/definitions/Case'
        400:
          description: Invalid or unknown project, suite or section
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /add_case/{section_id}:
    post:
      summary: Creates a new test case.
      parameters:
        - name: section_id
          in: path
          description: The ID of the section the test case should be added to
          required: true
          type: integer
          format: int32
        - name: case
          in: body
          required: true
          schema:
            $ref: '#/definitions/Case'
      tags:
        - TestRail
        - Cases
      responses:
        200:
          description: Success, the test case was created and is returned as part of the response
          schema:
            $ref: '#/definitions/Case'
        400:
          description: Invalid or unknown test case
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /update_case/{case_id}:
    post:
      summary: Updates an existing test case (partial updates are supported, i.e. you can submit and update specific fields only).
      parameters:
        - name: case_id
          in: path
          description: The ID of the test case
          required: true
          type: integer
          format: int32
        - name: case
          in: body
          required: true
          schema:
            $ref: '#/definitions/Case'
      tags:
        - TestRail
        - Cases
      responses:
        200:
          description: Success, the test case was updated and is returned as part of the response
          schema:
            $ref: '#/definitions/Case'
        400:
          description: Invalid or unknown test case
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /delete_case/{case_id}:
    post:
      summary: Deletes an existing test case.
      description: |
        Please note: Deleting a test case cannot be undone and also permanently deletes all test results in active test runs (i.e. test runs that haven't been closed (archived) yet).
      parameters:
        - name: case_id
          in: path
          description: The ID of the test case
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
        - Cases
      responses:
        200:
          description: Success, the test case was deleted
        400:
          description: Invalid or unknown test case
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_case_fields:
    get:
      summary: Returns a list of available test case custom fields.
      tags:
        - TestRail
        - Cases
        - Readonly
      responses:
        200:
          description: Success, the available custom fields are returned as part of the response
          schema:
            type: array
            items:
              $ref: '#/definitions/FieldDefinition'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_case_types:
    get:
      summary: Returns a list of available case types.
      tags:
        - TestRail
        - Cases
        - Readonly
      responses:
        200:
          description: Success, the case types are returned as part of the response
          schema:
            type: array
            items:
              $ref: '#/definitions/CaseType'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_priorities:
    get:
      summary: Returns a list of available priorities.
      tags:
        - TestRail
        - Cases
        - Readonly
      responses:
        200:
          description: Success, the priorities are returned as part of the response
          schema:
            type: array
            items:
              $ref: '#/definitions/Priority'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_statuses:
    get:
      summary: Returns a list of available test statuses.
      tags:
        - TestRail
        - Readonly
      responses:
        200:
          description: Success, the available statuses are returned as part of the response
          schema:
            type: array
            items:
              $ref: '#/definitions/Status'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_templates:
    get:
      summary: Returns a list of available templates (requires TestRail 5.2 or later).
      tags:
        - TestRail
      responses:
        200:
          description: Success, the templates are returned as part of the response
          schema:
            type: array
            items:
              $ref: '#/definitions/Template'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_result_fields:
    get:
      summary: Returns a list of available test result custom fields.
      tags:
        - TestRail
        - Readonly
      responses:
        200:
          description: Success, the available custom fields are returned as part of the response
          schema:
            type: array
            items:
              $ref: '#/definitions/FieldDefinition'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_configs/{project_id}:
    get:
      summary: Returns a list of available configurations, grouped by configuration groups (requires TestRail 3.1 or later).
      parameters:
        - name: project_id
          in: path
          description: The ID of the project
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
        - Configurations
        - Readonly
      responses:
        200:
          description: Success, the configurations are returned as part of the response
          schema:
            type: array
            items:
              $ref: '#/definitions/TestrunConfigurationGroup'
        400:
          description: Invalid or unknown project, suite or section
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /add_config_group/{project_id}:
    post:
      summary: Creates a new configuration group (requires TestRail 5.2 or later).
      parameters:
        - name: project_id
          in: path
          description: The ID of the project the configuration group should be added to
          required: true
          type: integer
          format: int32
        - name: config_group
          in: body
          required: true
          schema:
            $ref: '#/definitions/TestrunConfigurationGroup'
      tags:
        - TestRail
        - Configurations
      responses:
        200:
          description: Success, the configuration group was created and is returned as part of the response
          schema:
            type: object
        400:
          description: Invalid or unknown test case
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No permissions to add configuration groups or no access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /add_config/{config_group_id}:
    post:
      summary: Creates a new configuration (requires TestRail 5.2 or later).
      parameters:
        - name: config_group_id
          in: path
          description: The ID of the configuration group the configuration should be added to
          required: true
          type: integer
          format: int32
        - name: config
          in: body
          required: true
          schema:
            $ref: '#/definitions/TestrunConfiguration'
      tags:
        - TestRail
        - Configurations
      responses:
        200:
          description: Success, the configuration was created and is returned as part of the response
          schema:
            type: object
        400:
          description: Invalid or unknown test case
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No permissions to add configuration groups or no access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /update_config_group/{config_group_id}:
    post:
      summary: Updates an existing configuration group (requires TestRail 5.2 or later).
      parameters:
        - name: config_group_id
          in: path
          description: The ID of the configuration group
          required: true
          type: integer
          format: int32
        - name: config_group
          in: body
          required: true
          schema:
            $ref: '#/definitions/TestrunConfigurationGroup'
      tags:
        - TestRail
        - Configurations
      responses:
        200:
          description: Success, the configuration group was updated and is returned as part of the response
          schema:
            type: object
        400:
          description: Invalid or unknown test case
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No permissions to add configuration groups or no access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /update_config/{config_id}:
    post:
      summary: Updates an existing configuration (requires TestRail 5.2 or later).
      parameters:
        - name: config_id
          in: path
          description: The ID of the configuration
          required: true
          type: integer
          format: int32
        - name: config
          in: body
          required: true
          schema:
            $ref: '#/definitions/TestrunConfiguration'
      tags:
        - TestRail
        - Configurations
      responses:
        200:
          description: Success, the configuration was updated and is returned as part of the response
          schema:
            type: object
        400:
          description: Invalid or unknown test case
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No permissions to add configuration groups or no access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /delete_config_group/{config_group_id}:
    post:
      summary: Deletes an existing configuration group (requires TestRail 5.2 or later).
      parameters:
        - name: config_group_id
          in: path
          description: The ID of the configuration group
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
        - Configurations
      responses:
        200:
          description: Success, the configuration group and all its configurations were deleted
          schema:
            type: object
        400:
          description: Invalid or unknown test case
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No permissions to add configuration groups or no access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /delete_config/{config_id}:
    post:
      summary: Deletes an existing configuration (requires TestRail 5.2 or later).
      parameters:
        - name: config_id
          in: path
          description: The ID of the configuration
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
        - Configurations
      responses:
        200:
          description: Success, the configuration was deleted
          schema:
            type: object
        400:
          description: Invalid or unknown test case
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No permissions to add configuration groups or no access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_milestone/{milestone_id}:
    get:
      summary: Returns an existing milestone.
      parameters:
        - name: milestone_id
          in: path
          description: The ID of the milestone
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
        - Milestones
        - Readonly
      responses:
        200:
          description: A milestone
          schema:
            $ref: '#/definitions/Milestone'
        400:
          description: Invalid or unknown milestone
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_milestones/{project_id}:
    get:
      summary: Returns the list of milestones for a project.
      parameters:
        - name: project_id
          in: path
          description: The ID of the test case
          required: true
          type: integer
          format: int32
        - name: is_completed
          in: query
          type: boolean
          required: false
          description: 1 to return completed milestones only. 0 to return open (active/upcoming) milestones only (available since TestRail 4.0).
        - name: is_started
          in: query
          type: boolean
          required: false
          description: 1 to return started milestones only. 0 to return upcoming milestones only (available since TestRail 5.3).
      tags:
        - TestRail
        - Milestones
        - Readonly
      responses:
        200:
          description: Success, the milestones are returned as part of the response.
          schema:
            type: array
            items:
              $ref: '#/definitions/Milestone'
        400:
          description: Invalid or unknown project
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /add_milestone/{project_id}:
    post:
      summary: Creates a new milestone.
      parameters:
        - name: project_id
          in: path
          description: The ID of the project the milestone should be added to
          required: true
          type: integer
          format: int32
        - name: milestone
          in: body
          required: true
          schema:
            $ref: '#/definitions/Milestone'
      tags:
        - TestRail
        - Milestones
      responses:
        200:
          description: Success, the milestone was created and is returned as part of the response
          schema:
            $ref: '#/definitions/Milestone'
        400:
          description: Invalid or unknown test case
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /update_milestone/{milestone_id}:
    post:
      summary: Updates an existing milestone (partial updates are supported, i.e. you can submit and update specific fields only).
      parameters:
        - name: milestone_id
          in: path
          description: The ID of the milestone
          required: true
          type: integer
          format: int32
        - name: milestone
          in: body
          required: true
          schema:
            $ref: '#/definitions/Milestone'
      tags:
        - TestRail
        - Milestones
      responses:
        200:
          description: Success, the milestone was updated and is returned as part of the response
          schema:
            $ref: '#/definitions/Case'
        400:
          description: Invalid or unknown milestone
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /delete_milestone/{milestone_id}:
    post:
      summary: Deletes an existing milestone.
      description: Deleting a milestone cannot be undone.
      parameters:
        - name: milestone_id
          in: path
          description: The ID of the milestone
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
        - Milestones
      responses:
        200:
          description: Success, the milestone was deleted
        400:
          description: Invalid or unknown milestone
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_plan/{plan_id}:
    get:
      summary: Returns an existing test plan.
      parameters:
        - name: plan_id
          in: path
          description: The ID of the test plan
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
        - Testruns
        - Readonly
      responses:
        200:
          description: A test plan
          schema:
            $ref: '#/definitions/TestplanDetailInfo'
        400:
          description: Invalid or unknown test plan
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_plans/{project_id}:
    get:
      summary: Returns the list of test plans for a project.
      parameters:
        - name: project_id
          in: path
          description: The ID of the project
          required: true
          type: integer
          format: int32
        - name: created_after
          in: query
          description: Only return test plans created after this date (as UNIX timestamp).
          required: false
          type: integer
          format: int32
        - name: created_before
          in: query
          description: Only return test plans created before this date (as UNIX timestamp).
          required: false
          type: integer
          format: int32
        - name: created_by
          in: query
          description: A comma-separated list of creators (user IDs) to filter by.
          required: false
          type: string
        - name: is_completed
          in: query
          type: boolean
          required: false
          description: 1 to return completed test plans only. 0 to return active test plans only.
        - name: limit
          in: query
          description: Limit the result to :limit test plans.
          required: false
          type: integer
          format: int32
        - name: offset
          in: query
          description: Use :offset to skip records.
          required: false
          type: integer
          format: int32
        - name: milestone_id
          in: query
          description: A comma-separated list of milestone IDs to filter by.
          required: false
          type: string
      tags:
        - TestRail
        - Testruns
        - Readonly
      responses:
        200:
          description: Success, the test plans are returned as part of the response.
          schema:
            type: array
            items:
              $ref: '#/definitions/TestplanInfo'
        400:
          description: Invalid or unknown project
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /add_plan/{project_id}:
    post:
      summary: Creates a new test plan.
      parameters:
        - name: project_id
          in: path
          description: The ID of the project the test plan should be added to
          required: true
          type: integer
          format: int32
        - name: plan
          in: body
          required: true
          schema:
            $ref: '#/definitions/Testplan'
      tags:
        - TestRail
        - Testruns
      responses:
        200:
          description: Success, the test plan was created and is returned as part of the response
          schema:
            $ref: '#/definitions/Testplan'
        400:
          description: Invalid or unknown project
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /update_plan/{plan_id}:
    post:
      summary: Updates an existing test plan (partial updates are supported, i.e. you can submit and update specific fields only).
      parameters:
        - name: plan_id
          in: path
          description: The ID of the test plan
          required: true
          type: integer
          format: int32
        - name: plan
          in: body
          required: true
          schema:
            $ref: '#/definitions/Testplan'
      tags:
        - TestRail
        - Testruns
      responses:
        200:
          description: Success, the test plan was updated and is returned as part of the response
          schema:
            $ref: '#/definitions/Testplan'
        400:
          description: Invalid or unknown test plan
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /close_plan/{plan_id}:
    post:
      summary: Updates an existing test plan (partial updates are supported, i.e. you can submit and update specific fields only).
      description: Closing a test plan cannot be undone.
      parameters:
        - name: plan_id
          in: path
          description: The ID of the test plan
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
        - Testruns
      responses:
        200:
          description: Success, the test plan and all its test runs were closed (archived). The test plan and its test runs are returned as part of the response.
          schema:
            $ref: '#/definitions/Testplan'
        400:
          description: Invalid or unknown test plan
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /delete_plan/{plan_id}:
    post:
      summary: Deletes an existing test plan.
      description: Deleting a test plan cannot be undone and also permanently deletes all test runs & results of the test plan.
      parameters:
        - name: plan_id
          in: path
          description: The ID of the test plan
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
        - Testruns
      responses:
        200:
          description: Success, the test plan was deleted
        400:
          description: Invalid or unknown test plan
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /add_plan_entry/{plan_id}:
    post:
      summary: Adds one or more new test runs to a test plan.
      parameters:
        - name: plan_id
          in: path
          description: The ID of the plan the test runs should be added to
          required: true
          type: integer
          format: int32
        - name: entry
          in: body
          required: true
          schema:
            $ref: '#/definitions/TestrunEntry'
      tags:
        - TestRail
        - Testruns
      responses:
        200:
          description: Success, the test plan entry was added and is returned as part of the response
          schema:
            $ref: '#/definitions/TestrunEntry'
        400:
          description: Invalid or unknown test plan
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /update_plan_entry/{plan_id}/{entry_id}:
    post:
      summary: Updates an existing test plan (partial updates are supported, i.e. you can submit and update specific fields only).
      parameters:
        - name: plan_id
          in: path
          description: The ID of the test plan
          required: true
          type: integer
          format: int32
        - name: entry_id
          in: path
          description: "The ID of the test plan entry (note: not the test run ID)"
          required: true
          type: integer
          format: int32
        - name: entry
          in: body
          required: true
          schema:
            $ref: '#/definitions/TestrunEntry'
      tags:
        - TestRail
        - Testruns
      responses:
        200:
          description: Success, the test plan entry was updated and is returned as part of the response
          schema:
            $ref: '#/definitions/TestrunEntry'
        400:
          description: Invalid or unknown test plan
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /delete_plan_entry/{plan_id}/{entry_id}:
    post:
      summary: Deletes one or more existing test runs from a plan.
      description: Deleting a test run from a plan cannot be undone and also permanently deletes all related test results.
      parameters:
        - name: plan_id
          in: path
          description: The ID of the test plan
          required: true
          type: integer
          format: int32
        - name: entry_id
          in: path
          description: "The ID of the test plan entry (note: not the test run ID)"
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
        - Testruns
      responses:
        200:
          description: Success, the test run(s) were removed from the test plan
        400:
          description: Invalid or unknown test plan
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_run/{run_id}:
    get:
      summary: Returns an existing test run.
      parameters:
        - name: run_id
          in: path
          description: The ID of the test run
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
        - Testruns
        - Readonly
      responses:
        200:
          description: A test run
          schema:
            $ref: '#/definitions/TestrunInfo'
        400:
          description: Invalid or unknown test run
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_runs/{project_id}:
    get:
      summary: Returns the list of test runs for a project.
      parameters:
        - name: project_id
          in: path
          description: The ID of the project
          required: true
          type: integer
          format: int32
        - name: created_after
          in: query
          description: Only return test runs created after this date (as UNIX timestamp).
          required: false
          type: integer
          format: int32
        - name: created_before
          in: query
          description: Only return test runs created before this date (as UNIX timestamp).
          required: false
          type: integer
          format: int32
        - name: created_by
          in: query
          description: A comma-separated list of creators (user IDs) to filter by.
          required: false
          type: string
        - name: is_completed
          in: query
          type: boolean
          required: false
          description: 1 to return completed test runs only. 0 to return active test runs only.
        - name: limit
          in: query
          description: Limit the result to :limit test runs.
          required: false
          type: integer
          format: int32
        - name: offset
          in: query
          description: Use :offset to skip records.
          required: false
          type: integer
          format: int32
        - name: milestone_id
          in: query
          description: A comma-separated list of milestone IDs to filter by.
          required: false
          type: string
        - name: suite_id
          in: query
          description: A comma-separated list of test suite IDs to filter by.
          required: false
          type: string
      tags:
        - TestRail
        - Testruns
        - Readonly
      responses:
        200:
          description: Success, the test runs are returned as part of the response.
          schema:
            type: array
            items:
              $ref: '#/definitions/TestrunInfo'
        400:
          description: Invalid or unknown project
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /add_run/{project_id}:
    post:
      summary: Creates a new test run.
      parameters:
        - name: project_id
          in: path
          description: The ID of the project the test run should be added to
          required: true
          type: integer
          format: int32
        - name: run
          in: body
          required: true
          schema:
            $ref: '#/definitions/Testrun'
      tags:
        - TestRail
        - Testruns
      responses:
        200:
          description: Success, the test run was created and is returned as part of the response
          schema:
            $ref: '#/definitions/Testrun'
        400:
          description: Invalid or unknown project
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /update_run/{run_id}:
    post:
      summary: Updates an existing test run (partial updates are supported, i.e. you can submit and update specific fields only).
      parameters:
        - name: run_id
          in: path
          description: The ID of the test run
          required: true
          type: integer
          format: int32
        - name: run
          in: body
          required: true
          schema:
            $ref: '#/definitions/Testrun'
      tags:
        - TestRail
        - Testruns
      responses:
        200:
          description: Success, the test run was updated and is returned as part of the response
          schema:
            $ref: '#/definitions/Testrun'
        400:
          description: Invalid or unknown test run
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /close_run/{run_id}:
    post:
      summary: Updates an existing test run (partial updates are supported, i.e. you can submit and update specific fields only).
      description: Closing a test run cannot be undone.
      parameters:
        - name: run_id
          in: path
          description: The ID of the test run
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
        - Testruns
      responses:
        200:
          description: Success, the test run and all its test runs were closed (archived). The test run and its test runs are returned as part of the response.
          schema:
            $ref: '#/definitions/Testrun'
        400:
          description: Invalid or unknown test run
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /delete_run/{run_id}:
    post:
      summary: Deletes an existing test run.
      description: Deleting a test run cannot be undone and also permanently deletes all test runs & results of the test run.
      parameters:
        - name: run_id
          in: path
          description: The ID of the test run
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
        - Testruns
      responses:
        200:
          description: Success, the test run was deleted
        400:
          description: Invalid or unknown test run
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_project/{project_id}:
    get:
      summary: Returns an existing project.
      parameters:
        - name: project_id
          in: path
          description: The ID of the project
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
        - Readonly
      responses:
        200:
          description: A project
          schema:
            $ref: '#/definitions/Project'
        400:
          description: Invalid or unknown project
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_projects:
    get:
      summary: Returns the list of projects for a project.
      parameters:
        - name: is_completed
          in: query
          type: boolean
          required: false
          description: 1 to return completed projects only. 0 to return active projects only.
      tags:
        - TestRail
        - Readonly
      responses:
        200:
          description: Success, the projects are returned as part of the response.
          schema:
            type: array
            items:
              $ref: '#/definitions/Project'
        400:
          description: Invalid or unknown project
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /add_project:
    post:
      summary: Creates a new project.
      parameters:
        - name: project
          in: body
          required: true
          schema:
            $ref: '#/definitions/Project'
      tags:
        - TestRail
      responses:
        200:
          description: Success, the project was created and is returned as part of the response
          schema:
            $ref: '#/definitions/Project'
        400:
          description: Invalid or unknown project
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /update_project/{project_id}:
    post:
      summary: Updates an existing project (partial updates are supported, i.e. you can submit and update specific fields only).
      parameters:
        - name: project_id
          in: path
          description: The ID of the project
          required: true
          type: integer
          format: int32
        - name: project
          in: body
          required: true
          schema:
            $ref: '#/definitions/Project'
      tags:
        - TestRail
      responses:
        200:
          description: Success, the project was updated and is returned as part of the response
          schema:
            $ref: '#/definitions/Project'
        400:
          description: Invalid or unknown project
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /delete_project/{project_id}:
    post:
      summary: Deletes an existing project.
      description:  Deleting a project cannot be undone and also permanently deletes all test suites & cases, test runs & results and everything else that is part of the project.
      parameters:
        - name: project_id
          in: path
          description: The ID of the test run
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
      responses:
        200:
          description: Success, the test run was deleted
        400:
          description: Invalid or unknown test run
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_section/{section_id}:
    get:
      summary: Returns an existing section.
      parameters:
        - name: section_id
          in: path
          description: The ID of the section
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
        - Cases
        - Readonly
      responses:
        200:
          description: A section
          schema:
            $ref: '#/definitions/SectionInfo'
        400:
          description: Invalid or unknown section
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_sections/{project_id}:
    get:
      summary: Returns the list of sections for a project.
      parameters:
        - name: project_id
          in: path
          description: The ID of the test case
          required: true
          type: integer
          format: int32
        - name: suite_id
          in: query
          description: The ID of the test suite (optional if the project is operating in single suite mode)
          required: false
          type: integer
          format: int32
      tags:
        - TestRail
        - Cases
        - Readonly
      responses:
        200:
          description: Success, the sections are returned as part of the response.
          schema:
            type: array
            items:
              $ref: '#/definitions/SectionInfo'
        400:
          description: Invalid or unknown project
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /add_section/{project_id}:
    post:
      summary: Creates a new section.
      parameters:
        - name: project_id
          in: path
          description: The ID of the project the section should be added to
          required: true
          type: integer
          format: int32
        - name: section
          in: body
          required: true
          schema:
            $ref: '#/definitions/Section'
      tags:
        - TestRail
        - Cases
      responses:
        200:
          description: Success, the section was created and is returned as part of the response
          schema:
            $ref: '#/definitions/Section'
        400:
          description: Invalid or unknown test case
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /update_section/{section_id}:
    post:
      summary: Updates an existing section (partial updates are supported, i.e. you can submit and update specific fields only).
      parameters:
        - name: section_id
          in: path
          description: The ID of the section
          required: true
          type: integer
          format: int32
        - name: section
          in: body
          required: true
          schema:
            $ref: '#/definitions/Section'
      tags:
        - TestRail
        - Cases
      responses:
        200:
          description: Success, the section was updated and is returned as part of the response
          schema:
            $ref: '#/definitions/Case'
        400:
          description: Invalid or unknown section
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /delete_section/{section_id}:
    post:
      summary: Deletes an existing section.
      description: Deleting a section cannot be undone.
      parameters:
        - name: section_id
          in: path
          description: The ID of the section
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
        - Cases
      responses:
        200:
          description: Success, the section was deleted
        400:
          description: Invalid or unknown section
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_user/{user_id}:
    get:
      summary: Returns an existing user.
      parameters:
        - name: user_id
          in: path
          description: The ID of the user
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
        - Readonly
      responses:
        200:
          description: A user
          schema:
            $ref: '#/definitions/User'
        400:
          description: Invalid or unknown user
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_user_by_email:
    get:
      summary: Returns an existing user.
      parameters:
        - name: email
          in: query
          description: The email address to get the user for
          required: true
          type: string
      tags:
        - TestRail
        - Readonly
      responses:
        200:
          description: A user
          schema:
            $ref: '#/definitions/User'
        400:
          description: Invalid or unknown user
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_users:
    get:
      summary: Returns a list of users
      tags:
        - TestRail
        - Readonly
      responses:
        200:
          description: Users
          schema:
            type: array
            items:
              $ref: '#/definitions/User'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_suite/{suite_id}:
    get:
      summary: Returns an existing test suite.
      parameters:
        - name: suite_id
          in: path
          description: The ID of the test suite
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
        - Cases
        - Readonly
      responses:
        200:
          description: A test suite
          schema:
            $ref: '#/definitions/Suite'
        400:
          description: Invalid or unknown test suite
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_suites/{project_id}:
    get:
      summary: Returns the list of test suites for a project.
      parameters:
        - name: project_id
          in: path
          description: The ID of the test case
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
        - Suites
        - Readonly
      responses:
        200:
          description: Success, the test suites are returned as part of the response.
          schema:
            type: array
            items:
              $ref: '#/definitions/Suite'
        400:
          description: Invalid or unknown project
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /add_suite/{project_id}:
    post:
      summary: Creates a new test suite.
      parameters:
        - name: project_id
          in: path
          description: The ID of the project the test suite should be added to
          required: true
          type: integer
          format: int32
        - name: suite
          in: body
          required: true
          schema:
            $ref: '#/definitions/Suite'
      tags:
        - TestRail
        - Suites
      responses:
        200:
          description: Success, the test suite was created and is returned as part of the response
          schema:
            $ref: '#/definitions/Suite'
        400:
          description: Invalid or unknown test case
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /update_suite/{suite_id}:
    post:
      summary: Updates an existing test suite (partial updates are supported, i.e. you can submit and update specific fields only).
      parameters:
        - name: suite_id
          in: path
          description: The ID of the test suite
          required: true
          type: integer
          format: int32
        - name: suite
          in: body
          required: true
          schema:
            $ref: '#/definitions/Suite'
      tags:
        - TestRail
        - Suites
      responses:
        200:
          description: Success, the test suite was updated and is returned as part of the response
          schema:
            $ref: '#/definitions/Case'
        400:
          description: Invalid or unknown test suite
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /delete_suite/{suite_id}:
    post:
      summary: Deletes an existing test suite.
      description: Deleting a test suite cannot be undone.
      parameters:
        - name: suite_id
          in: path
          description: The ID of the test suite
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
        - Suites
      responses:
        200:
          description: Success, the test suite was deleted
        400:
          description: Invalid or unknown test suite
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_test/{test_id}:
    get:
      summary: Returns an existing test.
      parameters:
        - name: test_id
          in: path
          description: The ID of the test
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
        - Testresults
        - Readonly
      responses:
        200:
          description: A test
          schema:
            $ref: '#/definitions/Test'
        400:
          description: Invalid or unknown test
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_tests/{run_id}:
    get:
      summary: Returns a list of tests for a test run.
      parameters:
        - name: run_id
          in: path
          description: The ID of the test run
          required: true
          type: integer
          format: int32
        - name: status_id
          in: query
          description: A comma-separated list of status IDs to filter by.
          required: false
          type: string
      tags:
        - TestRail
        - Testresults
        - Readonly
      responses:
        200:
          description: Test cases
          schema:
            type: array
            items:
              $ref: '#/definitions/Test'
        400:
          description: Invalid or unknown project, suite or section
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_results/{test_id}:
    get:
      summary: Returns a list of test results for a test.
      parameters:
        - name: test_id
          in: path
          description: The ID of the test
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
        - Testresults
        - Readonly
      responses:
        200:
          description: Success, the test results are returned as part of the response
          schema:
            type: array
            items:
              $ref: '#/definitions/Testresult'
        400:
          description: Invalid or unknown test
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_results_for_case/{run_id}/{case_id}:
    get:
      summary: Returns a list of test results for a test.
      parameters:
        - name: run_id
          in: path
          description: The ID of the test run
          required: true
          type: integer
          format: int32
        - name: case_id
          in: path
          description: The ID of the test case
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
        - Testresults
        - Readonly
      responses:
        200:
          description: Success, the test results are returned as part of the response
          schema:
            type: array
            items:
              $ref: '#/definitions/Testresult'
        400:
          description: Invalid or unknown test
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /get_results_for_run/{run_id}:
    get:
      summary: Returns a list of test results for a test run.
      parameters:
        - name: run_id
          in: path
          description: The ID of the test run
          required: true
          type: integer
          format: int32
      tags:
        - TestRail
        - Testresults
        - Readonly
      responses:
        200:
          description: Success, the test results are returned as part of the response
          schema:
            type: array
            items:
              $ref: '#/definitions/Testresult'
        400:
          description: Invalid or unknown test
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /add_result/{test_id}:
    post:
      summary: Adds a new test result, comment or assigns a test.
      description: It's recommended to use add_results instead if you plan to add results for multiple tests.
      parameters:
        - name: test_id
          in: path
          description: The ID of the test the result should be added to
          required: true
          type: integer
          format: int32
        - name: result
          in: body
          required: true
          schema:
            $ref: '#/definitions/Testresult'
      tags:
        - TestRail
        - Testresults
      responses:
        200:
          description: Success, the test result was created and is returned as part of the response
          schema:
            $ref: '#/definitions/Testresult'
        400:
          description: Invalid or unknown test
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No permissions to add test results or no access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /add_result_for_case/{run_id}/{case_id}:
    post:
      summary: Adds a new test result, comment or assigns a test (for a test run and case combination).
      description: |
        It's recommended to use add_results_for_cases instead if you plan to add results for multiple test cases.
        The difference to add_result is that this method expects a test run + test case instead of a test. In TestRail,
        tests are part of a test run and the test cases are part of the related test suite. So, when you create a new
        test run, TestRail creates a test for each test case found in the test suite of the run. You can therefore
        think of a test as an “instance” of a test case which can have test results, comments and a test status.
        Please also see TestRail's getting started guide for more details about the differences between test cases and
        tests.
      parameters:
        - name: run_id
          in: path
          description: The ID of the test run
          required: true
          type: integer
          format: int32
        - name: case_id
          in: path
          description: The ID of the test case
          required: true
          type: integer
          format: int32
        - name: result
          in: body
          required: true
          schema:
            $ref: '#/definitions/Testresult'
      tags:
        - TestRail
        - Testresults
      responses:
        200:
          description: Success, the test result was created and is returned as part of the response
          schema:
            $ref: '#/definitions/Testresult'
        400:
          description: Invalid or unknown test
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No permissions to add test results or no access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /add_results/{test_id}:
    post:
      summary: Adds one or more new test results, comments or assigns one or more tests.
      description: Ideal for test automation to bulk-add multiple test results in one step.
      parameters:
        - name: test_id
          in: path
          description: The ID of the test the result should be added to
          required: true
          type: integer
          format: int32
        - name: result
          in: body
          required: true
          schema:
            properties:
              results:
                type: array
                items:
                   $ref: '#/definitions/Testresult'
      tags:
        - TestRail
        - Testresults
      responses:
        200:
          description: Success, the test results are returned as part of the response
          schema:
            type: array
            items:
              $ref: '#/definitions/Testresult'
        400:
          description: Invalid or unknown test
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No permissions to add test results or no access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'

  /add_results_for_cases/{run_id}/{case_id}:
    post:
      summary: Adds one or more new test results, comments or assigns one or more tests.
      description: Ideal for test automation to bulk-add multiple test results in one step.
      parameters:
        - name: run_id
          in: path
          description: The ID of the test run
          required: true
          type: integer
          format: int32
        - name: case_id
          in: path
          description: The ID of the test case
          required: true
          type: integer
          format: int32
        - name: result
          in: body
          required: true
          schema:
            properties:
              results:
                type: array
                items:
                   $ref: '#/definitions/Testresult'
      tags:
        - TestRail
        - Testresults
      responses:
        200:
          description: Success, the test results are returned as part of the response
          schema:
            type: array
            items:
              $ref: '#/definitions/Testresult'
        400:
          description: Invalid or unknown test
          schema:
            $ref: '#/definitions/Error'
        403:
          description: No permissions to add test results or no access to the project
          schema:
            $ref: '#/definitions/Error'
        default:
          description: Unexpected error
          schema:
            $ref: '#/definitions/Error'


definitions:

  CustomCaseFields:
    type: object
    properties:
EOYAML


#########################################################
#
#     DYNAMIC SECTION
#
#########################################################


def field_definitions(method)
  fields = get_testrail(method)
  fields_abc = fields.sort_by { |f| f["system_name"] }
  ret = fields_abc.each_with_object([]) do |f, acc|
    acc << "      #{f["system_name"]}:"
    acc << "        description: #{f["description"]}" unless f["description"].nil? || f["description"].empty?
    acc << type_info(f["type_id"]).rstrip
  end
  ret << ""
  ret.join("\n")
end

output += field_definitions("get_case_fields")

output += <<EOYAML

  CustomResultFields:
    type: object
    properties:
EOYAML

output += field_definitions("get_result_fields")

output += <<EOYAML

  Step:
    type: object
    properties:
      content:
        type: string
      expected:
        type: string

  Case:
    type: object
    allOf:
      - $ref: '#/definitions/CaseBase'
      - $ref: '#/definitions/CustomCaseFields'
      - type: object
        properties:
          id:
            type: integer
            format: int32
            description: The unique ID of the test case
          created_by:
            type: integer
            format: int32
            description: The ID of the user who created the test case
          created_on:
            type: integer
            format: int32
            description: The date/time when the test case was created (as UNIX timestamp)
          suite_id:
            type: integer
            format: int32
            description: The ID of the suite the test case belongs to
          section_id:
            type: integer
            format: int32
            description: The ID of the section the test case belongs to
          template_id:
            type: integer
            format: int32
            description: The ID of the template (field layout) the test case uses (requires TestRail 5.2 or later)
          updated_by:
            type: integer
            format: int32
            description: The ID of the user who last updated the test case
          updated_on:
            type: integer
            format: int32
            description: The date/time when the test case was last updated (as UNIX timestamp)

  Test:
    type: object
    allOf:
      - $ref: '#/definitions/CaseBase'
      - $ref: '#/definitions/CustomCaseFields'
      - type: object
        properties:
          id:
            type: integer
            format: int32
            description: The unique ID of the test
          case_id:
            type: integer
            format: int32
            description: The unique ID of the test case
          run_id:
            type: integer
            format: int32
            description: The unique ID of the test case
          status_id:
            type: integer
            format: int32
            description: The unique ID of the test case
          assignedto_id:
            type: integer
            format: int32
            description: The ID of the user the test is assigned to

  CaseBase:
    type: object
    properties:
      estimate:
        type: string
        description: The estimate, e.g. "30s" or "1m 45s"
      estimate_forecast:
        type: string
        description: The estimate forecast, e.g. "30s" or "1m 45s"
      milestone_id:
        type: integer
        format: int32
        description: The ID of the priority that is linked to the test case
      priority_id:
        type: integer
        format: int32
        description: The ID of the template (field layout) the test case uses (requires TestRail 5.2 or later)
      refs:
        type: string
        description: A comma-separated list of references/requirements
      title:
        type: string
        description: The title of the test case
      type_id:
        type: integer
        format: int32
        description: The ID of the test case type that is linked to the test case

  CaseType:
    type: object
    properties:
      id:
        type: integer
        format: int32
        description: The case type ID
      is_default:
        type: boolean
      name:
        type: string

  Priority:
    type: object
    properties:
      id:
        type: integer
        format: int32
      is_default:
        type: boolean
      priority:
        type: integer
        format: int32
      name:
        type: string
      shortname:
        type: string

  Status:
    type: object
    properties:
      color_bright:
        type: integer
        format: int32
      color_dark:
        type: integer
        format: int32
      color_medium:
        type: integer
        format: int32
      id:
        type: integer
        format: int32
      is_final:
        type: boolean
      is_system:
        type: boolean
      is_untested:
        type: boolean
      priority:
        type: integer
        format: int32
      label:
        type: string
      name:
        type: string

  FieldDefinition:
    type: object
    properties:
      configs:
        description: Configuration and options per project
        type: array
        items:
           $ref: '#/definitions/FieldConfig'
      description:
        type: string
      display_order:
        type: integer
        format: int32
      id:
        type: integer
        format: int32
      include_all:
        type: boolean
      is_active:
        type: boolean
      label:
        type: string
      name:
        type: string
      system_name:
        type: string
      type_id:
        description: Field type [1=String, Integer, Text, URL, Checkbox, Dropdown, User, Date, Milestone, Steps, Multi-select]
        type: integer
        format: int32
      template_ids:
        type: array
        items:
          type: integer
          format: int32

  FieldConfig:
    type: object
    properties:
      context:
        type: object
        properties:
          is_global:
            type: boolean
          project_ids:
            type: array
            items:
              type: integer
              format: int32
      id:
        type: string
      options:
        type: object
        properties:
          default_value:
            type: string
          format:
            type: string
          is_required:
            type: string
          items:
            type: string
            description: An array of comma-separated pairs (id, name) separated by newlines
          rows:
            type: integer
            format: int32
          has_actual:
            type: boolean
          has_expected:
            type: boolean

  Template:
    type: object
    properties:
      id:
        type: integer
        format: int32
      is_default:
        type: boolean
      name:
        type: string

  TestrunConfigurationGroup:
    type: object
    properties:
      configs:
        type: array
        items:
         $ref: '#/definitions/TestrunConfiguration'
      project_id:
        type: integer
        format: int32
      id:
        type: integer
        format: int32
      name:
        type: string

  TestrunConfiguration:
    type: object
    properties:
      group_id:
        type: integer
        format: int32
      id:
        type: integer
        format: int32
      name:
        type: string

  Milestone:
    type: object
    allOf:
      - $ref: '#/definitions/MilestoneBase'
      - type: object
        properties:
          milestones:
            type: array
            items:
              $ref: '#/definitions/MilestoneBase'
            description: The sub milestones that belong to the milestone (if any); only available with get_milestone (available since TestRail 5.3)

  MilestoneBase:
    type: object
    properties:
      completed_on:
        type: integer
        format: int32
        description: The date/time when the milestone was marked as completed (as UNIX timestamp)
      description:
        type: string
        description: The description of the milestone
      due_on:
        type: integer
        format: int32
        description: The due date/time of the milestone (as UNIX timestamp)
      id:
        type: integer
        format: int32
        description: The unique ID of the milestone
      is_completed:
        type: boolean
        description: True if the milestone is marked as completed and false otherwise
      is_started:
        type: boolean
        description: True if the milestone is marked as started and false otherwise (available since TestRail 5.3)
      name:
        type: string
        description: The name of the milestone
      parent_id:
        type: integer
        format: int32
        description: The ID of the parent milestone the milestone belongs to (if any) (available since TestRail 5.3)
      project_id:
        type: integer
        format: int32
        description: The ID of the project the milestone belongs to
      start_on:
        type: integer
        format: int32
        description: The scheduled start date/time of the milestone (as UNIX timestamp) (available since TestRail 5.3)
      started_on:
        type: integer
        format: int32
        description: The date/time when the milestone was started (as UNIX timestamp) (available since TestRail 5.3)
      url:
        type: string
        description: The address/URL of the milestone in the user interface

  ResultSummary:
    type: object
    properties:
      blocked_count:
        type: integer
        format: int32
        description: The amount of tests in the test plan marked as blocked
      custom_status1_count:
        type: integer
        format: int32
        description: The amount of tests in the test plan with the respective custom status
      custom_status2_count:
        type: integer
        format: int32
        description: The amount of tests in the test plan with the respective custom status
      custom_status3_count:
        type: integer
        format: int32
        description: The amount of tests in the test plan with the respective custom status
      custom_status4_count:
        type: integer
        format: int32
        description: The amount of tests in the test plan with the respective custom status
      custom_status5_count:
        type: integer
        format: int32
        description: The amount of tests in the test plan with the respective custom status
      custom_status6_count:
        type: integer
        format: int32
        description: The amount of tests in the test plan with the respective custom status
      custom_status7_count:
        type: integer
        format: int32
        description: The amount of tests in the test plan with the respective custom status
      failed_count:
        type: integer
        format: int32
        description: The amount of tests in the test plan marked as failed
      passed_count:
        type: integer
        format: int32
        description: The amount of tests in the test plan marked as passed
      retest_count:
        type: integer
        format: int32
        description: The amount of tests in the test plan marked as retest
      untested_count:
        type: integer
        format: int32
        description: The amount of tests in the test plan marked as untested

  TestplanInfo:
    type: object
    allOf:
      - $ref: '#/definitions/TestplanBase'
      - $ref: '#/definitions/ResultSummary'

  TestplanDetailInfo:
    type: object
    allOf:
      - $ref: '#/definitions/TestplanBase'
      - $ref: '#/definitions/ResultSummary'
      - type: object
        properties:
          entries:
            type: array
            items:
               $ref: '#/definitions/TestrunEntryInfo'

  Testplan:
    type: object
    allOf:
      - $ref: '#/definitions/TestplanBase'
      - type: object
        properties:
          entries:
            type: array
            items:
               $ref: '#/definitions/TestrunEntry'

  TestplanBase:
    type: object
    properties:
      assignedto_id:
        type: integer
        format: int32
        description: The ID of the user the entire test plan is assigned to
      completed_on:
        type: integer
        format: int32
        description: The date/time when the test plan was closed (as UNIX timestamp)
      created_by:
        type: integer
        format: int32
        description: The ID of the user who created the test plan
      created_on:
        type: integer
        format: int32
        description: The date/time when the test plan was created (as UNIX timestamp)
      description:
        type: string
        description: The description of the test plan
      id:
        type: integer
        format: int32
        description: The unique ID of the test plan
      is_completed:
        type: boolean
        description: True if the test plan was closed and false otherwise
      milestone_id:
        type: integer
        format: int32
        description: The ID of the milestone this test plan belongs to
      name:
        type: string
        description: The name of the test plan
      project_id:
        type: integer
        format: int32
        description: The ID of the project this test plan belongs to
      url:
        type: string
        description: The address/URL of the test plan in the user interface

  TestrunEntry:
    type: object
    allOf:
      - $ref: '#/definitions/TestrunEntryBase'
      - type: object
        properties:
          runs:
            type: array
            items:
               $ref: '#/definitions/Testrun'

  TestrunEntryInfo:
    type: object
    allOf:
      - $ref: '#/definitions/TestrunEntryBase'
      - type: object
        properties:
          runs:
            type: array
            items:
               $ref: '#/definitions/TestrunInfo'

  TestrunEntryBase:
    type: object
    properties:
      id:
        type: string
        description: The ID of the test run entry
      name:
        type: string
        description: The name of the test run entry
      config_ids:
        type: array
        items:
          type: integer
          format: int32
        description: An array of configuration IDs used for the test runs of the test plan entry (requires TestRail 3.1 or later)F
      suite_id:
        type: integer
        format: int32
        description: The ID of the test suite this test plan is derived from
      assignedto_id:
        type: integer
        format: int32
        description: The ID of the user the entire test plan is assigned to
      include_all:
        type: boolean
        description: True for including all test cases of the test suite and false for a custom case selection
      case_ids:
        type: array
        items:
          type: integer
          format: int32
        description: The array of IDs of the cases of the test plan entry

  TestrunInfo:
    type: object
    allOf:
      - $ref: '#/definitions/Testrun'
      - $ref: '#/definitions/ResultSummary'

  Testrun:
    type: object
    properties:
      assignedto_id:
        type: integer
        format: int32
        description: The ID of the user the entire test run is assigned to
      case_ids:
        type: array
        items:
          type: integer
          format: int32
        description: The array of IDs of the cases of the test run
      completed_on:
        type: integer
        format: int32
        description: The date/time when the test run was closed (as UNIX timestamp)
      config:
        type: string
        description: The configuration of the test run as string (if part of a test plan)
      config_ids:
        type: array
        items:
          type: integer
          format: int32
        description: The array of IDs of the configurations of the test run (if part of a test plan)
      created_by:
        type: integer
        format: int32
        description: The ID of the user who created the test run
      created_on:
        type: integer
        format: int32
        description: The date/time when the test run was created (as UNIX timestamp)
      description:
        type: string
        description: The description of the test run
      id:
        type: integer
        format: int32
        description: The unique ID of the test run
      include_all:
        type: boolean
        description: True if the test run includes all test cases and false otherwise
      is_completed:
        type: boolean
        description: True if the test run was closed and false otherwise
      milestone_id:
        type: integer
        format: int32
        description: The ID of the milestone this test run belongs to
      plan_id:
        type: integer
        format: int32
        description: The ID of the test plan this test run belongs to
      name:
        type: string
        description: The name of the test run
      project_id:
        type: integer
        format: int32
        description: The ID of the project this test run belongs to
      suite_id:
        type: integer
        format: int32
        description: The ID of the test suite this test run is derived from
      url:
        type: string
        description: The address/URL of the test run in the user interface

  Project:
    type: object
    properties:
      announcement:
        type: string
        description: The description/announcement of the project
      priority:
        type: integer
        format: int32
        description: The date/time when the project was marked as completed (as UNIX timestamp)
      id:
        type: integer
        format: int32
        description: The unique ID of the project
      is_completed:
        type: boolean
        description: True if the project is marked as completed and false otherwise
      name:
        type: string
        description: The name of the project
      show_announcement:
        type: boolean
        description: True to show the announcement/description and false otherwise
      suite_mode:
        type: integer
        format: int32
        description: The suite mode of the project (1 for single suite mode, 2 for single suite + baselines, 3 for multiple suites) (added with TestRail 4.0)
      url:
        type: string
        description: The address/URL of the project in the user interface

  SectionInfo:
    type: object
    allOf:
      - $ref: '#/definitions/Section'
      - type: object
        properties:
          depth:
            type: integer
            format: int32
            description: The level in the section hierarchy of the test suite

  Section:
    type: object
    properties:
      description:
        type: string
        description: The description of the section (added with TestRail 4.0)
      display_order:
        type: integer
        format: int32
        description: The order in the test suite
      id:
        type: integer
        format: int32
        description: The unique ID of the section
      parent_id:
        type: integer
        format: int32
        description: The ID of the parent section in the test suite
      name:
        type: string
        description: The name of the section
      suite_id:
        type: integer
        format: int32
        description: The ID of the test suite this section belongs to

  User:
    type: object
    properties:
      email:
        type: string
        description: The email address of the user as configured in TestRail
      id:
        type: integer
        format: int32
        description: The unique ID of the user
      is_active:
        type: boolean
        description: True if the user is active and false otherwise
      name:
        type: string
        description: The full name of the

  Suite:
    type: object
    properties:
      completed_on:
        type: integer
        format: int32
        description: The date/time when the test suite was closed (as UNIX timestamp)
      description:
        type: string
        description: The description of the test suite
      id:
        type: integer
        format: int32
        description: The unique ID of the test suite
      is_baseline:
        type: boolean
        description: True if the test suite is a baseline test suite and false otherwise (added with TestRail 4.0)
      is_completed:
        type: boolean
        description: True if the test suite is marked as completed/archived and false otherwise (added with TestRail 4.0)
      is_master:
        type: boolean
        description: True if the test suite is a master test suite and false otherwise (added with TestRail 4.0)
      name:
        type: string
        description: The name of the test suite
      project_id:
        type: integer
        format: int32
        description: The ID of the project this test suite belongs to
      url:
        type: string
        description: The address/URL of the test suite in the user interface

  Testresult:
    type: object
    allOf:
      - $ref: '#/definitions/ResultBase'
      - $ref: '#/definitions/CustomResultFields'

  ResultBase:
    type: object
    properties:
      assignedto_id:
        type: integer
        format: int32
        description: The ID of the assignee (user) of the test result
      comment:
        type: string
        description: The comment or error message of the test result
      created_by:
        type: integer
        format: int32
        description: The ID of the user who created the test result
      created_on:
        type: integer
        format: int32
        description: The date/time when the test result was created (as UNIX timestamp)
      defects:
        type: string
        description: A comma-separated list of defects linked to the test result
      elapsed:
        type: string
        description: The amount of time it took to execute the test (e.g. "1m" or "2m 30s")
      id:
        type: integer
        format: int32
        description: The unique ID of the test
      status_id:
        type: integer
        format: int32
        description: The status of the test result, e.g. passed or failed, also see get_statuses
      test_id:
        type: integer
        format: int32
        description: The ID of the test this test result belongs to
      version:
        type: string
        description: The (build) version the test was executed against

  Error:
    type: object
    properties:
      error:
        type: string
        format: int32

externalDocs:
  description: "Official TestRail API (v2) Documentation"
  url: "http://docs.gurock.com/testrail-api2/start"
EOYAML

puts "# dyanamically generated by #{__FILE__} on #{Date.today}"
puts "# checksum #{Digest::SHA1.hexdigest output}"
puts output
