#!/usr/bin/env ruby

require_relative '../lib/resume_support_matrix'

begin
  project_root = ENV.fetch('RESUME_PROJECT_ROOT', File.expand_path('..', __dir__))
  matrix = ResumeSupportMatrix.new(project_root: project_root)
  matrix.validate!
  puts "Supported resume data is valid (#{matrix.supported.length} supported, #{matrix.archived.length} archived)."
rescue ResumeSupportMatrix::ValidationError => e
  warn e.message
  exit 1
end
