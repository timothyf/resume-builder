#!/usr/bin/env ruby

require_relative 'lib/pdf_conversion'

configuration = PdfConversion::Configuration.new(project_root: __dir__)
PdfConversion::Runner.new(configuration).run
puts "Resume saved in directory: #{File.dirname(configuration.pdf_source_path)}"
