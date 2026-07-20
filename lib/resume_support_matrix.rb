require 'yaml'
require_relative 'resume_data_validator'

class ResumeSupportMatrix
  MANIFEST_PATH = 'data/resume_support.yml'.freeze
  ENTRY_PATTERN = /\A[a-zA-Z0-9_-]+\z/

  attr_reader :archived, :supported

  class ValidationError < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = errors.freeze
      heading =
        "Resume support matrix validation failed with #{errors.length} " \
        "error#{errors.length == 1 ? '' : 's'}:"
      super(([heading] + errors.map { |error| "  - #{error}" }).join("\n"))
    end
  end

  def initialize(project_root:, env: ENV, validator_factory: nil)
    @project_root = File.expand_path(project_root)
    @env = env
    @validator_factory = validator_factory || lambda do |validation_env|
      ResumeDataValidator.new(project_root: @project_root, env: validation_env)
    end
    @errors = []
    @supported = []
    @archived = []
  end

  def validate!
    manifest = load_manifest
    @supported = parse_entries(manifest, 'supported', require_reason: false)
    @archived = parse_entries(manifest, 'archived', require_reason: true)

    validate_classification
    validate_supported_resumes

    raise ValidationError, @errors unless @errors.empty?

    true
  end

  private

  def load_manifest
    absolute_path = File.join(@project_root, MANIFEST_PATH)
    unless File.file?(absolute_path)
      add_error("#{MANIFEST_PATH} does not exist")
      return {}
    end

    value = YAML.safe_load_file(absolute_path, aliases: false)
    return value if value.is_a?(Hash)

    add_error("#{MANIFEST_PATH} must contain a top-level mapping")
    {}
  rescue Psych::SyntaxError => e
    add_error(
      "#{MANIFEST_PATH} contains invalid YAML at line #{e.line}, " \
      "column #{e.column}: #{e.problem}"
    )
    {}
  end

  def parse_entries(manifest, section, require_reason:)
    entries = manifest[section]
    unless entries.is_a?(Array)
      add_error("#{MANIFEST_PATH}.#{section} must be an array")
      return []
    end

    entries.each_with_index.filter_map do |entry, index|
      path = "#{MANIFEST_PATH}.#{section}[#{index}]"
      unless entry.is_a?(Hash)
        add_error("#{path} must be a mapping")
        next
      end

      user = required_string(entry, 'user', path)
      name = required_string(entry, 'name', path)
      reason = required_string(entry, 'reason', path) if require_reason
      next if user.nil? || name.nil? || (require_reason && reason.nil?)

      unless user.match?(ENTRY_PATTERN) && name.match?(ENTRY_PATTERN)
        add_error("#{path} user and name may contain only letters, numbers, underscores, and hyphens")
        next
      end

      { 'user' => user, 'name' => name, 'reason' => reason }.compact
    end
  end

  def required_string(entry, key, path)
    value = entry[key]
    if !value.is_a?(String) || value.strip.empty?
      add_error("#{path}.#{key} must be a non-empty string")
      return nil
    end

    value.strip
  end

  def validate_classification
    classifications = (@supported + @archived).group_by { |entry| resume_key(entry) }
    classifications.each do |key, entries|
      add_error("#{key} is classified #{entries.length} times in #{MANIFEST_PATH}") if entries.length > 1
    end

    declared = classifications.keys
    discovered = discovered_resume_keys

    (discovered - declared).each do |key|
      add_error("#{key} is not classified as supported or archived in #{MANIFEST_PATH}")
    end
    (declared - discovered).each do |key|
      add_error("#{key} is declared in #{MANIFEST_PATH} but data/#{key}.yml does not exist")
    end
  end

  def discovered_resume_keys
    pattern = File.join(@project_root, 'data', '*', 'resume*.yml')
    Dir.glob(pattern).sort.map do |path|
      relative = path.delete_prefix(File.join(@project_root, 'data') + File::SEPARATOR)
      relative.delete_suffix('.yml')
    end
  end

  def validate_supported_resumes
    @supported.each do |entry|
      key = resume_key(entry)
      next unless File.file?(File.join(@project_root, 'data', "#{key}.yml"))

      begin
        validation_env = @env.to_h.merge(
          'ACTIVE_RESUME_USER' => entry.fetch('user'),
          'ACTIVE_RESUME_NAME' => entry.fetch('name')
        )
        @validator_factory.call(validation_env).validate!
      rescue ResumeDataValidator::ValidationError => e
        e.errors.each { |error| add_error("#{key}: #{error}") }
      end
    end
  end

  def resume_key(entry)
    "#{entry.fetch('user')}/#{entry.fetch('name')}"
  end

  def add_error(message)
    @errors << message unless @errors.include?(message)
  end
end
