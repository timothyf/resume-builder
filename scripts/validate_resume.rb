#!/usr/bin/env ruby

require_relative '../lib/resume_data_validator'

begin
  validator = ResumeDataValidator.new(project_root: File.expand_path('..', __dir__))
  validator.validate!
  puts "Resume data is valid (#{validator.user}/#{validator.resume_name})."
rescue ResumeDataValidator::ValidationError => e
  warn e.message
  exit 1
end
