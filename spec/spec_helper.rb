require 'pathname'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'resume_selection'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  config.before do
    ENV.delete('ACTIVE_RESUME_USER')
    ENV.delete('ACTIVE_RESUME_NAME')
    ENV.delete('ACTIVE_RESUME_GENERATE_BRIEF')
  end
end
