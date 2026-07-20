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
    %w[
      ACTIVE_RESUME_USER
      ACTIVE_RESUME_NAME
      ACTIVE_RESUME_GENERATE_BRIEF
      FREECONVERT_API_KEY
      FREECONVERT_BUILD_BEFORE_CONVERT
      FREECONVERT_OUTPUT_FILENAME
      FREECONVERT_OUTPUT_PATH
      FREECONVERT_PACKAGE_AFTER_CONVERT
      FREECONVERT_SOURCE_PATH
      FREECONVERT_SOURCE_URL
      RESUME_SKIP_PDF_COPY
    ].each { |name| ENV.delete(name) }
  end
end
