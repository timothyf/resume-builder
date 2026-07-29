#!/usr/bin/env ruby

require 'optparse'

module ListResumes
  module_function

  def resumes_for_user(project_root:, user:)
    data_root = File.join(project_root, 'data', user)
    return [] unless Dir.exist?(data_root)

    resumes = []

    legacy_pattern = File.join(data_root, 'resume*.yml')
    Dir.glob(legacy_pattern).sort.each do |path|
      name = File.basename(path, '.yml')
      resumes << {
        name: name,
        structure: 'legacy',
        path: relative_path(project_root, path)
      }
    end

    structured_pattern = File.join(data_root, 'resumes', 'resume*', 'resume.yml')
    Dir.glob(structured_pattern).sort.each do |path|
      name = File.basename(File.dirname(path))
      resumes << {
        name: name,
        structure: 'structured',
        path: relative_path(project_root, path)
      }
    end

    resumes.sort_by { |entry| [entry[:name], entry[:structure]] }
  end

  def relative_path(project_root, absolute_path)
    absolute_path.delete_prefix(project_root + File::SEPARATOR)
  end

  def detect_user(project_root:, explicit_user:, env:)
    active_resume_path = File.join(project_root, 'data', 'active_resume.yml')
    active_user = nil
    if File.file?(active_resume_path)
      begin
        require 'yaml'
        active = YAML.safe_load_file(active_resume_path, aliases: true)
        active_user = active['user'] if active.is_a?(Hash)
      rescue Psych::SyntaxError
        active_user = nil
      end
    end

    user = explicit_user || env.fetch('ACTIVE_RESUME_USER', '').strip
    user = active_user.to_s.strip if user.empty?
    user
  end

  def run(argv:, env: ENV, stdout: $stdout, stderr: $stderr)
    options = {
      user: nil,
      format: 'text'
    }

    parser = OptionParser.new do |opts|
      opts.banner = 'Usage: ./list_resumes.bash [--user USER] [--format text|json]'

      opts.on('--user USER', 'List resumes for USER. Defaults to ACTIVE_RESUME_USER or active_resume.yml user.') do |value|
        options[:user] = value
      end

      opts.on('--format FORMAT', 'Output format: text (default) or json.') do |value|
        options[:format] = value
      end

      opts.on('-h', '--help', 'Show this help.') do
        stdout.puts opts
        return 0
      end
    end

    parser.parse!(argv)

    unless argv.empty?
      stderr.puts parser
      return 1
    end

    project_root = env.fetch('RESUME_PROJECT_ROOT', File.expand_path('..', __dir__))
    project_root = File.expand_path(project_root)
    user = detect_user(project_root: project_root, explicit_user: options[:user], env: env)

    if user.empty?
      stderr.puts 'Could not determine user. Pass --user USER or set ACTIVE_RESUME_USER or data/active_resume.yml user.'
      return 1
    end

    unless user.match?(/\A[a-zA-Z0-9_-]+\z/)
      stderr.puts 'User may contain only letters, numbers, underscores, and hyphens.'
      return 1
    end

    resumes = resumes_for_user(project_root: project_root, user: user)

    case options[:format]
    when 'json'
      require 'json'
      stdout.puts JSON.pretty_generate({ user: user, resumes: resumes })
    when 'text'
      if resumes.empty?
        stdout.puts "No resumes found for #{user}."
        return 0
      end

      stdout.puts "Resumes for #{user}:"
      resumes.each do |entry|
        stdout.puts "- #{entry.fetch(:name)} [#{entry.fetch(:structure)}] -> #{entry.fetch(:path)}"
      end
    else
      stderr.puts "Invalid --format value '#{options[:format]}'. Use text or json."
      return 1
    end

    0
  end
end

if __FILE__ == $PROGRAM_NAME
  exit(ListResumes.run(argv: ARGV.dup))
end
