#!/usr/bin/env ruby

require 'optparse'
require_relative '../lib/resume_creator'

options = {
  force: false
}

parser = OptionParser.new do |opts|
  opts.banner = 'Usage: ./create_resume.bash RESUME_NAME [--from EXISTING_RESUME] [--user USER] [--force]'

  opts.on('--from RESUME', 'Duplicate files from an existing resume. Accepts resume_name or user/resume_name.') do |value|
    options[:from] = value
  end

  opts.on('--user USER', 'Create the resume for USER. Defaults to data/active_resume.yml user.') do |value|
    options[:user] = value
  end

  opts.on('--force', 'Overwrite generated target files if they already exist.') do
    options[:force] = true
  end

  opts.on('-h', '--help', 'Show this help.') do
    puts opts
    exit
  end
end

parser.parse!
name = ARGV.shift

if name.nil? || !ARGV.empty?
  warn parser
  exit 1
end

begin
  result = ResumeCreator.new(project_root: File.expand_path('..', __dir__)).create!(
    name: name,
    user: options[:user],
    from: options[:from],
    force: options[:force]
  )

  puts "Created #{result.fetch(:user)}/#{File.basename(result.fetch(:resume), '.yml')}:"
  puts "  - #{result.fetch(:resume)}"
  puts "  - #{result.fetch(:jobs)}"
  puts "  - #{result.fetch(:summary)}"
  puts "Updated #{result.fetch(:support)}."
rescue ResumeCreator::Error => e
  warn "Could not create resume: #{e.message}"
  exit 1
end
