#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$script_dir/scripts/run_bundle.bash" exec ruby <<'RUBY'
require 'yaml'

active_resume_path = File.expand_path('data/active_resume.yml', __dir__)
active_resume = YAML.load_file(active_resume_path) || {}

configured_user = active_resume['user']
configured_name = active_resume['name']
configured_generate_brief = active_resume.fetch('generate_brief', true)

configured_theme = 'theme-default'
if configured_user && configured_name
  resume_path = File.expand_path("data/#{configured_user}/#{configured_name}.yml", __dir__)
  if File.exist?(resume_path)
    resume_yaml = YAML.load_file(resume_path) || {}
    resume_theme = resume_yaml['theme']
    configured_theme = resume_theme if resume_theme && !resume_theme.to_s.strip.empty?
  end
end

effective_user = ENV.fetch('ACTIVE_RESUME_USER', '').strip
if effective_user.empty?
  effective_user = configured_user
end

effective_name = ENV.fetch('ACTIVE_RESUME_NAME', '').strip
if effective_name.empty?
  effective_name = configured_name
end

effective_generate_brief_raw = ENV.fetch('ACTIVE_RESUME_GENERATE_BRIEF', '').strip
if effective_generate_brief_raw.empty?
  effective_generate_brief = configured_generate_brief
else
  effective_generate_brief = effective_generate_brief_raw
end

effective_theme = ENV.fetch('ACTIVE_RESUME_THEME', '').strip
if effective_theme.empty?
  effective_theme = configured_theme
end

puts 'Configured (data/active_resume.yml):'
puts "  user: #{configured_user}"
puts "  name: #{configured_name}"
puts "  generate_brief: #{configured_generate_brief}"
puts "  theme: #{configured_theme}"
puts
puts 'Effective (after env overrides):'
puts "  user: #{effective_user}"
puts "  name: #{effective_name}"
puts "  generate_brief: #{effective_generate_brief}"
puts "  theme: #{effective_theme}"
RUBY
