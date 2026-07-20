#!/usr/bin/env ruby

require_relative '../lib/resume_support_matrix'

begin
  matrix = ResumeSupportMatrix.new(project_root: File.expand_path('..', __dir__))
  matrix.validate!
  puts "Supported resume data is valid (#{matrix.supported.length} supported, #{matrix.archived.length} archived)."
rescue ResumeSupportMatrix::ValidationError => e
  warn e.message
  exit 1
end
