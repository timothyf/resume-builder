#!/usr/bin/env ruby

require 'optparse'

options = {}
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: ruby generatePdf.rb [--resume-user USER] [--resume-name NAME]'

  opts.on('--resume-user USER', 'Generate the PDF for USER.') do |value|
    options[:user] = value
  end

  opts.on('--resume-name NAME', 'Generate the PDF for NAME.') do |value|
    options[:name] = value
  end

  opts.on('-h', '--help', 'Show this help.') do
    puts opts
    exit
  end
end

begin
  parser.parse!(ARGV)
  raise OptionParser::InvalidOption, ARGV.join(' ') unless ARGV.empty?
rescue OptionParser::ParseError => e
  warn e.message
  warn parser
  exit 1
end

ENV['ACTIVE_RESUME_USER'] = options[:user] if options[:user]
ENV['ACTIVE_RESUME_NAME'] = options[:name] if options[:name]

require_relative 'lib/pdf_conversion'

configuration = PdfConversion::Configuration.new(project_root: __dir__)
PdfConversion::Runner.new(configuration).run
puts "Resume saved in directory: #{File.dirname(configuration.pdf_source_path)}"
