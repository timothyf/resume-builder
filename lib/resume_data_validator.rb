require 'date'
require 'pathname'
require 'yaml'

class ResumeDataValidator
  attr_reader :resume_name, :user

  class ValidationError < StandardError
    attr_reader :errors

    def initialize(user:, resume:, errors:)
      @errors = errors.freeze
      super(
        "Resume data validation failed for #{user}/#{resume} " \
        "with #{errors.length} error#{errors.length == 1 ? '' : 's'}:\n" \
        "#{errors.map { |error| "  - #{error}" }.join("\n")}"
      )
    end
  end

  def initialize(project_root:, env: ENV)
    @project_root = File.expand_path(project_root)
    @env = env
    @errors = []
    @loaded_files = {}
  end

  def validate!
    active_path = 'data/active_resume.yml'
    active_resume = load_mapping(active_path)
    @user = env_value('ACTIVE_RESUME_USER') || required_value(active_resume, 'user', active_path)
    @resume_name = env_value('ACTIVE_RESUME_NAME') || required_value(active_resume, 'name', active_path)

    if blank?(@user) || blank?(@resume_name)
      raise_validation_error
    end

    resume_path = "data/#{@user}/#{@resume_name}.yml"
    resume = load_mapping(resume_path)
    validate_resume(resume, resume_path)
    raise_validation_error unless @errors.empty?

    true
  end

  private

  def validate_resume(resume, resume_path)
    layout_name = required_value(resume, 'layout', resume_path)
    jobs_filename = required_value(resume, 'jobs_filename', resume_path)
    pdf = required_mapping(resume, 'pdf', resume_path)
    required_value(pdf, 'filename', "#{resume_path}: pdf")
    # validate_pdf_source(pdf, resume_path)

    layout_path = "data/#{@user}/layouts/#{layout_name}.yml" unless blank?(layout_name)
    templates = layout_path ? validate_layout(load_mapping(layout_path), layout_path) : []

    validate_profile(resume, resume_path) if templates.include?('profile')
    validate_contact(resume, resume_path) if templates.include?('contact')
    validate_summary(resume, resume_path) if templates.include?('summary')
    validate_skills(resume, resume_path) if templates.include?('skills')
    validate_jobs(resume, resume_path, jobs_filename) if templates.any? { |name| experience_template?(name) }
    validate_education(resume, resume_path) if templates.include?('education')
  end

  def validate_layout(layout, layout_path)
    content = required_mapping(layout, 'content', layout_path)
    templates = []

    %w[center right].each do |column|
      sections = required_array(content, column, "#{layout_path}: content")
      sections.each_with_index do |section, index|
        section_path = "#{layout_path}: content.#{column}[#{index}]"
        unless section.is_a?(Hash)
          add_error("#{section_path} must be a mapping")
          next
        end

        template = required_value(section, 'template', section_path)
        next if blank?(template)

        templates << template.to_s
        validate_template_file(template.to_s, section_path)
      end
    end

    templates
  end

  def validate_template_file(template, section_path)
    unless template.match?(%r{\A[a-zA-Z0-9_/-]+\z})
      add_error("#{section_path}.template contains an invalid template path '#{template}'")
      return
    end

    relative_path = "source/templates/_#{template}.erb"
    add_error("#{section_path}.template references missing template '#{relative_path}'") unless project_file?(relative_path)
  end

  def validate_pdf_source(pdf, resume_path)
    return unless pdf.key?('source')

    source = required_value(pdf, 'source', "#{resume_path}: pdf")
    return if blank?(source)
    return if truthy_env?('RESUME_SKIP_PDF_COPY')

    add_error("#{resume_path}: pdf.source references missing file '#{source}'") unless project_file?(source.to_s)
  end

  def validate_profile(resume, resume_path)
    contact = required_mapping(resume, 'contact_info', resume_path)
    required_value(contact, 'name', "#{resume_path}: contact_info")
  end

  def validate_contact(resume, resume_path)
    contact = required_mapping(resume, 'contact_info', resume_path)
    contact_path = "#{resume_path}: contact_info"
    required_value(contact, 'email', contact_path)
    address = required_mapping(contact, 'address', contact_path)
    %w[city state postal_code].each do |key|
      required_value(address, key, "#{contact_path}.address")
    end
    validate_links(resume, resume_path) if resume.key?('links')
  end

  def validate_links(resume, resume_path)
    references = required_array(resume, 'links', resume_path)
    links_path = "data/#{@user}/links.yml"
    links_data = load_mapping(links_path)
    catalog = required_array(links_data, 'links', links_path)
    names = catalog.filter_map do |link|
      link['name'].to_s if link.is_a?(Hash) && !blank?(link['name'])
    end

    catalog.each_with_index do |link, index|
      path = "#{links_path}: links[#{index}]"
      unless link.is_a?(Hash)
        add_error("#{path} must be a mapping")
        next
      end
      required_value(link, 'name', path)
      required_value(link, 'url', path)
    end

    references.each_with_index do |reference, index|
      path = "#{resume_path}: links[#{index}]"
      unless reference.is_a?(Hash)
        add_error("#{path} must be a mapping")
        next
      end
      name = required_value(reference, 'name', path)
      if !blank?(name) && !names.include?(name.to_s)
        add_error("#{path}.name references missing link '#{name}' in #{links_path}")
      end
    end
  end

  def validate_summary(resume, resume_path)
    summary = required_mapping(resume, 'summary', resume_path)
    summary_name = required_value(summary, 'file', "#{resume_path}: summary")
    return if blank?(summary_name)

    summary_path = "data/#{@user}/summaries/#{summary_name}.yml"
    summary_data = load_mapping(summary_path)
    summary_content = required_mapping(summary_data, 'summary', summary_path)
    required_value(summary_content, 'text', "#{summary_path}: summary")
  end

  def validate_skills(resume, resume_path)
    categories = required_array(resume, 'skills', resume_path)
    skills_path = "data/#{@user}/skills.yml"
    catalog = load_array(skills_path)
    skill_ids = catalog.filter_map do |skill|
      skill['id'].to_s if skill.is_a?(Hash) && !blank?(skill['id'])
    end
    validate_catalog(catalog, skills_path, required_keys: %w[id label])
    validate_duplicate_ids(skill_ids, skills_path)

    categories.each_with_index do |category, category_index|
      category_path = "#{resume_path}: skills[#{category_index}]"
      unless category.is_a?(Hash)
        add_error("#{category_path} must be a mapping")
        next
      end

      required_value(category, 'name', category_path)
      references = required_array(category, 'skills', category_path)
      references.each_with_index do |skill_id, skill_index|
        if blank?(skill_id)
          add_error("#{category_path}.skills[#{skill_index}] is required")
        elsif !skill_ids.include?(skill_id.to_s)
          add_error("#{category_path}.skills[#{skill_index}] references missing skill '#{skill_id}' in #{skills_path}")
        end
      end
    end
  end

  def validate_jobs(resume, resume_path, jobs_filename)
    references = required_array(resume, 'jobs', resume_path)
    return if blank?(jobs_filename)

    jobs_path = "data/#{@user}/#{jobs_filename}.yml"
    catalog = load_array(jobs_path)
    job_ids = catalog.filter_map do |job|
      job['id'].to_s if job.is_a?(Hash) && !blank?(job['id'])
    end
    validate_catalog(catalog, jobs_path, required_keys: ['id'])
    validate_duplicate_ids(job_ids, jobs_path)
    jobs_by_id = catalog.each_with_object({}) do |job, index|
      index[job['id'].to_s] = job if job.is_a?(Hash) && !blank?(job['id'])
    end

    references.each_with_index do |reference, index|
      reference_path = "#{resume_path}: jobs[#{index}]"
      unless reference.is_a?(Hash)
        add_error("#{reference_path} must be a mapping")
        next
      end

      job_id = required_value(reference, 'id', reference_path)
      section = required_value(reference, 'section', reference_path)
      unless blank?(section) || %w[experiences experience_other].include?(section.to_s)
        add_error("#{reference_path}.section has unsupported value '#{section}'")
      end
      next if blank?(job_id)

      job = jobs_by_id[job_id.to_s]
      unless job
        add_error("#{reference_path}.id references missing job '#{job_id}' in #{jobs_path}")
        next
      end

      validate_selected_job(job, jobs_path, job_id, section)
    end
  end

  def validate_selected_job(job, jobs_path, job_id, section)
    job_path = "#{jobs_path}: job '#{job_id}'"
    required_value(job, 'company', job_path)
    required_value(job, 'title', job_path)
    location = required_mapping(job, 'location', job_path)
    #required_value(location, 'state', "#{job_path}.location")
    dates = required_mapping(job, 'dates', job_path)
    required_value(dates, 'start', "#{job_path}.dates")
    required_value(dates, 'end', "#{job_path}.dates")
    required_value(job, 'desc', job_path) if section.to_s == 'experiences'
  end

  def validate_education(resume, resume_path)
    education = required_array(resume, 'education', resume_path)
    education.each_with_index do |entry, index|
      path = "#{resume_path}: education[#{index}]"
      unless entry.is_a?(Hash)
        add_error("#{path} must be a mapping")
        next
      end

      required_value(entry, 'name', path)
      required_value(entry, 'degree', path)
      next unless blank?(entry['status'])

      dates = required_mapping(entry, 'dates', path)
      required_value(dates, 'start', "#{path}.dates")
      required_value(dates, 'end', "#{path}.dates")
    end
  end

  def validate_catalog(catalog, path, required_keys:)
    catalog.each_with_index do |entry, index|
      entry_path = "#{path}: [#{index}]"
      unless entry.is_a?(Hash)
        add_error("#{entry_path} must be a mapping")
        next
      end
      required_keys.each { |key| required_value(entry, key, entry_path) }
    end
  end

  def validate_duplicate_ids(ids, path)
    ids.tally.each do |id, count|
      add_error("#{path} contains duplicate id '#{id}'") if count > 1
    end
  end

  def experience_template?(name)
    %w[experiences experience_highlights experience_other].include?(name)
  end

  def load_mapping(relative_path)
    value = load_yaml(relative_path)
    return {} if value.nil?
    return value if value.is_a?(Hash)

    add_error("#{relative_path} must contain a top-level mapping")
    {}
  end

  def load_array(relative_path)
    value = load_yaml(relative_path)
    return [] if value.nil?
    return value if value.is_a?(Array)

    add_error("#{relative_path} must contain a top-level array")
    []
  end

  def load_yaml(relative_path)
    return @loaded_files[relative_path] if @loaded_files.key?(relative_path)

    absolute_path = project_path(relative_path)
    unless File.file?(absolute_path)
      add_error("#{relative_path} does not exist")
      return @loaded_files[relative_path] = nil
    end

    @loaded_files[relative_path] = YAML.safe_load_file(
      absolute_path,
      permitted_classes: [Date],
      aliases: true
    )
  rescue Psych::SyntaxError => e
    add_error("#{relative_path} contains invalid YAML at line #{e.line}, column #{e.column}: #{e.problem}")
    @loaded_files[relative_path] = nil
  end

  def required_mapping(container, key, path)
    value = container[key] if container.is_a?(Hash)
    return value if value.is_a?(Hash)

    add_error("#{path}.#{key} must be a mapping")
    {}
  end

  def required_array(container, key, path)
    value = container[key] if container.is_a?(Hash)
    return value if value.is_a?(Array)

    add_error("#{path}.#{key} must be an array")
    []
  end

  def required_value(container, key, path)
    value = container[key] if container.is_a?(Hash)
    add_error("#{path}.#{key} is required") if blank?(value)
    value
  end

  def project_file?(relative_path)
    absolute_path = project_path(relative_path)
    root_with_separator = "#{@project_root}#{File::SEPARATOR}"
    absolute_path.start_with?(root_with_separator) && File.file?(absolute_path)
  end

  def project_path(relative_path)
    File.expand_path(relative_path, @project_root)
  end

  def env_value(name)
    value = @env.fetch(name, '').to_s.strip
    value.empty? ? nil : value
  end

  def truthy_env?(name)
    %w[1 true yes y on].include?(@env.fetch(name, '').to_s.strip.downcase)
  end

  def blank?(value)
    value.nil? || (value.respond_to?(:empty?) && value.empty?)
  end

  def add_error(message)
    @errors << message unless @errors.include?(message)
  end

  def raise_validation_error
    raise ValidationError.new(user: @user || '(missing)', resume: @resume_name || '(missing)', errors: @errors)
  end
end
