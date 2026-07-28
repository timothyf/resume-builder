require 'fileutils'
require 'yaml'

class ResumeCreator
  ENTRY_PATTERN = /\A[a-zA-Z0-9_-]+\z/

  class Error < StandardError; end

  def initialize(project_root:)
    @project_root = File.expand_path(project_root)
  end

  def create!(name:, user: nil, from: nil, force: false)
    @user = normalize_entry(user || active_user, 'user')
    @slug = normalize_slug(name)
    @resume_name = "resume_#{@slug}"
    @jobs_name = "jobs_#{@slug}"
    @summary_name = "summary_#{@slug}"
    @force = force

    source = from ? source_components(from) : nil

    create_directories
    write_component_files(source)
    add_support_entry

    {
      user: @user,
      resume: relative_path(resume_path),
      jobs: relative_path(jobs_path),
      summary: relative_path(summary_path),
      support: relative_path(support_path)
    }
  end

  private

  def active_user
    active = load_yaml('data/active_resume.yml')
    user = active['user'] if active.is_a?(Hash)
    return user if user.is_a?(String) && !user.strip.empty?

    raise Error, 'Could not determine user. Pass --user USER or create data/active_resume.yml.'
  end

  def source_components(source_name)
    source_user, source_resume_name = parse_source(source_name)
    source_resume_path = data_path(source_user, "#{source_resume_name}.yml")
    raise Error, "Source resume does not exist: #{relative_path(source_resume_path)}" unless File.file?(source_resume_path)

    source_resume = load_yaml_path(source_resume_path)
    raise Error, "Source resume must be a YAML mapping: #{relative_path(source_resume_path)}" unless source_resume.is_a?(Hash)

    source_jobs_name = source_resume['jobs_filename']
    source_summary_name = source_resume.dig('summary', 'file')

    unless source_jobs_name.is_a?(String) && !source_jobs_name.strip.empty?
      raise Error, "Source resume is missing jobs_filename: #{relative_path(source_resume_path)}"
    end
    unless source_summary_name.is_a?(String) && !source_summary_name.strip.empty?
      raise Error, "Source resume is missing summary.file: #{relative_path(source_resume_path)}"
    end

    {
      resume: source_resume,
      jobs: load_existing_yaml(data_path(source_user, "#{source_jobs_name}.yml"), 'Source jobs file'),
      summary: load_existing_yaml(data_path(source_user, 'summaries', "#{source_summary_name}.yml"), 'Source summary file')
    }
  end

  def parse_source(source_name)
    parts = source_name.split('/', 2)
    if parts.length == 2
      [normalize_entry(parts[0], 'source user'), normalize_resume_name(parts[1])]
    else
      [@user, normalize_resume_name(source_name)]
    end
  end

  def write_component_files(source)
    ensure_writable!(resume_path)
    ensure_writable!(jobs_path)
    ensure_writable!(summary_path)

    if source
      resume = source.fetch(:resume).dup
      resume['name'] = @resume_name
      resume['jobs_filename'] = @jobs_name
      resume['summary'] = (resume['summary'].is_a?(Hash) ? resume['summary'].dup : {})
      resume['summary']['file'] = @summary_name
    else
      resume = starter_resume
    end

    write_yaml(resume_path, resume)
    write_yaml(jobs_path, source ? source.fetch(:jobs) : starter_jobs)
    write_yaml(summary_path, source ? source.fetch(:summary) : starter_summary)
  end

  def starter_resume
    {
      'name' => @resume_name,
      'layout' => 'layout',
      'pdf' => {
        'filename' => "pdf/#{@resume_name}",
        'source' => "#{@resume_name}.pdf"
      },
      'contact_info' => {
        'name' => 'Your Name',
        'email' => 'you@example.com',
        'phone' => '(555) 010-0000',
        'address' => {
          'city' => 'Your City',
          'state' => 'MI',
          'postal_code' => '00000'
        }
      },
      'summary' => { 'file' => @summary_name },
      'skills' => [],
      'jobs_filename' => @jobs_name,
      'jobs' => [],
      'education' => []
    }
  end

  def starter_jobs
    []
  end

  def starter_summary
    {
      'summary' => {
        'text' => 'Add a focused summary for this resume.'
      }
    }
  end

  def add_support_entry
    manifest = File.file?(support_path) ? load_yaml_path(support_path) : {}
    manifest = {} unless manifest.is_a?(Hash)
    manifest['supported'] = [] unless manifest['supported'].is_a?(Array)
    manifest['archived'] = [] unless manifest['archived'].is_a?(Array)

    entry = { 'user' => @user, 'name' => @resume_name }
    existing = manifest['supported'].any? { |item| support_entry?(item, entry) } ||
               manifest['archived'].any? { |item| support_entry?(item, entry) }
    manifest['supported'] << entry unless existing

    write_yaml(support_path, manifest)
  end

  def support_entry?(item, entry)
    item.is_a?(Hash) && item['user'] == entry['user'] && item['name'] == entry['name']
  end

  def create_directories
    FileUtils.mkdir_p(user_dir)
    FileUtils.mkdir_p(File.join(user_dir, 'summaries'))
  end

  def ensure_writable!(path)
    return if @force || !File.exist?(path)

    raise Error, "Refusing to overwrite existing file: #{relative_path(path)}"
  end

  def normalize_slug(value)
    normalized = normalize_entry(value, 'resume name')
    normalized.sub(/\Aresume_/, '')
  end

  def normalize_resume_name(value)
    slug = normalize_slug(value)
    "resume_#{slug}"
  end

  def normalize_entry(value, label)
    raise Error, "#{label} is required" unless value.is_a?(String)

    normalized = value.strip
    raise Error, "#{label} is required" if normalized.empty?
    raise Error, "#{label} may contain only letters, numbers, underscores, and hyphens" unless normalized.match?(ENTRY_PATTERN)

    normalized
  end

  def load_yaml(relative)
    path = File.join(@project_root, relative)
    return nil unless File.file?(path)

    load_yaml_path(path)
  end

  def load_yaml_path(path)
    YAML.safe_load_file(path, aliases: true)
  rescue Psych::SyntaxError => e
    raise Error, "#{relative_path(path)} contains invalid YAML at line #{e.line}, column #{e.column}: #{e.problem}"
  end

  def load_existing_yaml(path, label)
    raise Error, "#{label} does not exist: #{relative_path(path)}" unless File.file?(path)

    load_yaml_path(path)
  end

  def write_yaml(path, value)
    File.write(path, YAML.dump(value))
  end

  def data_path(*parts)
    File.join(@project_root, 'data', *parts)
  end

  def user_dir
    data_path(@user)
  end

  def resume_path
    data_path(@user, "#{@resume_name}.yml")
  end

  def jobs_path
    data_path(@user, "#{@jobs_name}.yml")
  end

  def summary_path
    data_path(@user, 'summaries', "#{@summary_name}.yml")
  end

  def support_path
    data_path('resume_support.yml')
  end

  def relative_path(path)
    path.delete_prefix(@project_root + File::SEPARATOR)
  end
end
