module ResumeSelection
  module_function

  def truthy_string?(value)
    %w[1 true yes y on].include?(value.to_s.strip.downcase)
  end

  def falsey_string?(value)
    %w[0 false no n off].include?(value.to_s.strip.downcase)
  end

  def brief_override_value
    raw = ENV.fetch('ACTIVE_RESUME_GENERATE_BRIEF', '').strip
    return nil if raw.empty?

    return true if truthy_string?(raw)
    return false if falsey_string?(raw)

    raise ArgumentError, "Invalid ACTIVE_RESUME_GENERATE_BRIEF value: '#{raw}'. Use true/false."
  end

  def active_resume_identifiers(active_resume)
    env_user = ENV.fetch('ACTIVE_RESUME_USER', '').strip
    env_name = ENV.fetch('ACTIVE_RESUME_NAME', '').strip

    {
      user: env_user.empty? ? active_resume.user : env_user,
      name: env_name.empty? ? active_resume.name : env_name
    }
  end

  def selection_context(active_resume, data_root)
    identifiers = active_resume_identifiers(active_resume)
    user_data = data_root.public_send(identifiers[:user])
    resume = user_data.public_send(identifiers[:name])
    brief_override = brief_override_value
    generate_brief = if brief_override.nil?
      active_resume.generate_brief != false
    else
      brief_override
    end

    {
      user: identifiers[:user],
      name: identifiers[:name],
      user_data: user_data,
      resume: resume,
      generate_brief: generate_brief
    }
  end
end
