require 'fileutils'
require 'json'
require 'net/http'
require 'yaml'

module PdfConversion
  class Configuration
    attr_reader :api_base, :api_key, :build_before_convert, :http_max_retries,
                :http_retry_base_delay_seconds, :http_timeout_seconds, :max_polls,
                :output_filename, :output_path, :package_after_convert,
                :pdf_source_path, :poll_interval_seconds, :project_root,
                :resume_name, :resume_user, :source_path, :source_url

    def initialize(project_root:, env: ENV)
      @project_root = File.expand_path(project_root)
      @env = env

      active_resume = load_yaml(File.join(@project_root, 'data', 'active_resume.yml'))
      @resume_user = env_value('ACTIVE_RESUME_USER') || active_resume.fetch('user')
      @resume_name = env_value('ACTIVE_RESUME_NAME') || active_resume.fetch('name')
      resume = load_yaml(File.join(@project_root, 'data', @resume_user, "#{@resume_name}.yml"))
      pdf = resume.fetch('pdf')
      pdf_source = pdf.fetch('source').to_s.strip
      raise ArgumentError, "pdf.source is required for #{@resume_user}/#{@resume_name}" if pdf_source.empty?

      @pdf_source_path = expand_project_path(pdf_source)
      @output_path = expand_project_path(env_value('FREECONVERT_OUTPUT_PATH') || pdf_source)
      public_pdf_filename = "#{pdf.fetch('filename')}.pdf"
      @output_filename = env_value('FREECONVERT_OUTPUT_FILENAME') || File.basename(public_pdf_filename)
      @source_path = expand_project_path(env_value('FREECONVERT_SOURCE_PATH') || 'build/pdf.html')
      @source_url = env_value('FREECONVERT_SOURCE_URL')
      @api_base = env_value('FREECONVERT_API_BASE') || 'https://api.freeconvert.com'
      @api_key = env_value('FREECONVERT_API_KEY')
      @build_before_convert = boolean_value('FREECONVERT_BUILD_BEFORE_CONVERT', true)
      @package_after_convert = boolean_value('FREECONVERT_PACKAGE_AFTER_CONVERT', true)
      @poll_interval_seconds = integer_value('FREECONVERT_POLL_INTERVAL_SECONDS', 5)
      @max_polls = integer_value('FREECONVERT_MAX_POLLS', 120)
      @http_timeout_seconds = integer_value('FREECONVERT_HTTP_TIMEOUT_SECONDS', 30)
      @http_max_retries = integer_value('FREECONVERT_HTTP_MAX_RETRIES', 3)
      @http_retry_base_delay_seconds = float_value('FREECONVERT_HTTP_RETRY_BASE_DELAY_SECONDS', 1.0)
    end

    def validate!
      return unless @api_key.nil? || @api_key.empty?

      raise ArgumentError, 'FREECONVERT_API_KEY is required'
    end

    private

    def load_yaml(path)
      YAML.safe_load_file(path, aliases: true) || {}
    rescue Errno::ENOENT
      raise ArgumentError, "Resume configuration not found: #{path}"
    end

    def env_value(name)
      value = @env.fetch(name, '').to_s.strip
      value.empty? ? nil : value
    end

    def expand_project_path(path)
      File.expand_path(path, @project_root)
    end

    def boolean_value(name, default)
      value = env_value(name)
      return default if value.nil?
      return true if %w[1 true yes y on].include?(value.downcase)
      return false if %w[0 false no n off].include?(value.downcase)

      raise ArgumentError, "Invalid #{name} value: '#{value}'. Use true/false."
    end

    def integer_value(name, default)
      Integer(env_value(name) || default)
    end

    def float_value(name, default)
      Float(env_value(name) || default)
    end
  end

  class Runner
    def initialize(configuration, command_runner: nil, sleeper: nil)
      @configuration = configuration
      @command_runner = command_runner || lambda { |environment, *command| system(environment, *command) }
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
    end

    def run
      @configuration.validate!
      run_local_build(allow_missing_pdf: true) if @configuration.build_before_convert
      job_url = submit_job(build_input_body)
      wait_for_completion(job_url)
      synchronize_pdf_source
      run_local_build(allow_missing_pdf: false) if @configuration.package_after_convert
    end

    def build_import_task
      if @configuration.source_url
        puts "Using source URL: #{@configuration.source_url}"
        return {
          'operation' => 'import/webpage',
          'url' => @configuration.source_url
        }
      end

      source_path = @configuration.source_path
      raise "Local source file not found: #{source_path}" unless File.file?(source_path)

      puts "Using local source file: #{source_path}"
      html_content = File.binread(source_path)
      {
        'operation' => 'import/base64',
        'file' => "data:text/html;base64,#{[html_content].pack('m0')}",
        'filename' => File.basename(source_path)
      }
    end

    def build_input_body
      {
        'tasks' => {
          'import-3' => build_import_task,
          'convert-1' => {
            'operation' => 'convert',
            'input' => 'import-3',
            'input_format' => 'html',
            'output_format' => 'pdf',
            'options' => {
              'page_size' => 'letter',
              'page_orientation' => 'portrait',
              'margin' => '60',
              'hide_cookie' => true,
              'use_print_stylesheet' => true
            }
          },
          'export-1' => {
            'operation' => 'export/url',
            'input' => ['convert-1'],
            'filename' => @configuration.output_filename
          }
        }
      }
    end

    def submit_job(input_body)
      uri = URI("#{@configuration.api_base}/v1/process/jobs")
      request = authorized_request(Net::HTTP::Post, uri)
      request['Content-Type'] = 'application/json'
      request['Accept'] = 'application/json'
      request.body = input_body.to_json

      response = perform_request(uri, request)
      payload = parse_json_response(response)
      unless %w[200 201].include?(response.code)
        raise "Request failed with code #{response.code}: #{response.body}"
      end

      puts 'Request accepted'
      puts "Job ID: #{payload['id']}" if payload['id']
      puts "Job Status: #{payload['status']}" if payload['status']
      payload.dig('links', 'self') || raise('Job URL not found in API response')
    end

    def wait_for_completion(job_url)
      job_uri = URI(job_url)

      (1..@configuration.max_polls).each do |attempt|
        response = perform_request(job_uri, authorized_request(Net::HTTP::Get, job_uri))
        raise "Job polling failed with code #{response.code}: #{response.body}" unless response.code == '200'

        payload = parse_json_response(response)
        case payload['status']
        when 'completed'
          puts 'Job completed'
          export_url = find_export_url(payload['tasks'])
          raise 'Could not locate export URL in completed job payload' unless export_url

          download_file(export_url)
          return
        when 'failed'
          raise "Job failed: #{response.body}"
        else
          puts "Job pending (attempt #{attempt}/#{@configuration.max_polls})"
          @sleeper.call(@configuration.poll_interval_seconds)
        end
      end

      raise "Timed out waiting for job completion after #{@configuration.max_polls} polls"
    end

    def run_local_build(allow_missing_pdf:)
      build_script = File.join(@configuration.project_root, 'build_resume.bash')
      raise "Build script not found: #{build_script}" unless File.file?(build_script)

      environment = {
        'ACTIVE_RESUME_USER' => @configuration.resume_user,
        'ACTIVE_RESUME_NAME' => @configuration.resume_name
      }
      if allow_missing_pdf && !File.file?(@configuration.pdf_source_path)
        environment['RESUME_SKIP_PDF_COPY'] = '1'
      end

      puts allow_missing_pdf ? 'Building PDF source HTML...' : 'Packaging generated PDF...'
      success = @command_runner.call(
        environment,
        build_script,
        '--resume-user',
        @configuration.resume_user,
        '--resume-name',
        @configuration.resume_name
      )
      raise 'Build failed. Fix build errors and run again.' unless success
    end

    def synchronize_pdf_source
      return if @configuration.output_path == @configuration.pdf_source_path

      FileUtils.mkdir_p(File.dirname(@configuration.pdf_source_path))
      FileUtils.cp(@configuration.output_path, @configuration.pdf_source_path)
      puts "Updated configured PDF source: #{@configuration.pdf_source_path}"
    end

    private

    def authorized_request(request_class, uri)
      request_class.new(uri.request_uri).tap do |request|
        request['Authorization'] = "Bearer #{@configuration.api_key}"
      end
    end

    def parse_json_response(response)
      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise "Invalid JSON response (status #{response.code}): #{e.message}"
    end

    def perform_request(uri, request)
      attempts = 0

      begin
        attempts += 1
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.open_timeout = @configuration.http_timeout_seconds
        http.read_timeout = @configuration.http_timeout_seconds
        http.request(request)
      rescue Timeout::Error, Errno::ECONNRESET, Errno::ETIMEDOUT, EOFError, SocketError => e
        if attempts <= @configuration.http_max_retries
          delay = @configuration.http_retry_base_delay_seconds * (2**(attempts - 1))
          warn "HTTP attempt #{attempts} failed: #{e.class} #{e.message}. Retrying in #{delay.round(2)}s..."
          @sleeper.call(delay)
          retry
        end

        raise "HTTP request failed after #{attempts} attempts: #{e.class} #{e.message}"
      end
    end

    def find_export_url(tasks)
      normalized = tasks.is_a?(Hash) ? tasks.values : Array(tasks)
      export_task = normalized.find { |task| task['operation'] == 'export/url' && task.dig('result', 'url') }
      export_task ||= normalized.find { |task| task.dig('result', 'url') }
      export_task&.dig('result', 'url')
    end

    def download_file(download_url)
      download_uri = URI(download_url)
      response = perform_request(download_uri, Net::HTTP::Get.new(download_uri.request_uri))
      unless response.code == '200'
        raise "Download failed with code #{response.code}: #{response.body}"
      end

      FileUtils.mkdir_p(File.dirname(@configuration.output_path))
      File.binwrite(@configuration.output_path, response.body)
      puts "File downloaded to #{@configuration.output_path}"
    end
  end
end
