require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'pdf_conversion'

RSpec.describe PdfConversion do
  def write_project_configuration(root, pdf_source: 'Resume.pdf')
    FileUtils.mkdir_p(File.join(root, 'data', 'person'))
    FileUtils.mkdir_p(File.join(root, 'build'))
    File.write(
      File.join(root, 'data', 'active_resume.yml'),
      "user: person\nname: resume\n"
    )
    File.write(
      File.join(root, 'data', 'person', 'resume.yml'),
      <<~YAML
        pdf:
          filename: pdf/PublicResume
          source: #{pdf_source}
      YAML
    )
    File.write(File.join(root, 'build', 'pdf.html'), '<html><body>Resume</body></html>')
  end

  def http_response(code, body)
    instance_double(Net::HTTPResponse, code: code.to_s, body: body)
  end

  def json_response(code, payload)
    http_response(code, JSON.generate(payload))
  end

  describe PdfConversion::Configuration do
    it 'defaults converter output to the configured PDF source' do
      Dir.mktmpdir do |root|
        write_project_configuration(root)
        configuration = described_class.new(
          project_root: root,
          env: { 'FREECONVERT_API_KEY' => 'test-key' }
        )

        expect(configuration.output_path).to eq(File.join(root, 'Resume.pdf'))
        expect(configuration.pdf_source_path).to eq(File.join(root, 'Resume.pdf'))
        expect(configuration.output_filename).to eq('PublicResume.pdf')
      end
    end

    it 'allows conversion without an API key' do
      Dir.mktmpdir do |root|
        write_project_configuration(root)
        configuration = described_class.new(project_root: root, env: {})

        expect(configuration.api_key).to be_nil
        expect(configuration.validate!).to be(true)
      end
    end

    it 'rejects resumes without a PDF source' do
      Dir.mktmpdir do |root|
        write_project_configuration(root, pdf_source: '')

        expect do
          described_class.new(project_root: root, env: { 'FREECONVERT_API_KEY' => 'test-key' })
        end.to raise_error(ArgumentError, /pdf.source is required/)
      end
    end

    it 'reports missing resume configuration files' do
      Dir.mktmpdir do |root|
        expect { described_class.new(project_root: root, env: {}) }
          .to raise_error(ArgumentError, /Resume configuration not found/)
      end
    end

    it 'rejects invalid boolean settings' do
      Dir.mktmpdir do |root|
        write_project_configuration(root)

        %w[FREECONVERT_BUILD_BEFORE_CONVERT FREECONVERT_PACKAGE_AFTER_CONVERT].each do |name|
          expect do
            described_class.new(project_root: root, env: { name => 'sometimes' })
          end.to raise_error(ArgumentError, /Invalid #{name} value/)
        end
      end
    end

    it 'rejects nonnumeric and out-of-range numeric settings' do
      Dir.mktmpdir do |root|
        write_project_configuration(root)
        invalid_settings = {
          'FREECONVERT_POLL_INTERVAL_SECONDS' => '-1',
          'FREECONVERT_MAX_POLLS' => '0',
          'FREECONVERT_HTTP_TIMEOUT_SECONDS' => 'not-a-number',
          'FREECONVERT_HTTP_MAX_RETRIES' => '-1',
          'FREECONVERT_HTTP_RETRY_BASE_DELAY_SECONDS' => '-0.1'
        }

        invalid_settings.each do |name, value|
          expect do
            described_class.new(project_root: root, env: { name => value })
          end.to raise_error(ArgumentError, /Invalid #{name} value/)
        end
      end
    end
  end

  describe PdfConversion::Runner do
    it 'constructs a base64 import task from local PDF HTML' do
      Dir.mktmpdir do |root|
        write_project_configuration(root)
        configuration = PdfConversion::Configuration.new(project_root: root, env: {})
        runner = described_class.new(configuration)

        task = runner.build_import_task
        encoded_content = task.fetch('file').split(',', 2).last

        expect(task['operation']).to eq('import/base64')
        expect(task['filename']).to eq('pdf.html')
        expect(encoded_content.unpack1('m0')).to eq('<html><body>Resume</body></html>')
      end
    end

    it 'constructs a webpage import task when a source URL is configured' do
      Dir.mktmpdir do |root|
        write_project_configuration(root)
        configuration = PdfConversion::Configuration.new(
          project_root: root,
          env: { 'FREECONVERT_SOURCE_URL' => 'https://example.test/resume.html' }
        )
        runner = described_class.new(configuration)

        expect(runner.build_import_task).to eq(
          'operation' => 'import/webpage',
          'url' => 'https://example.test/resume.html'
        )
      end
    end

    it 'constructs the conversion and export task graph' do
      Dir.mktmpdir do |root|
        write_project_configuration(root)
        configuration = PdfConversion::Configuration.new(project_root: root, env: {})
        tasks = described_class.new(configuration).build_input_body.fetch('tasks')

        expect(tasks.fetch('convert-1')).to include(
          'operation' => 'convert',
          'input_format' => 'html',
          'output_format' => 'pdf'
        )
        expect(tasks.dig('convert-1', 'options')).to include(
          'page_size' => 'letter',
          'page_orientation' => 'portrait'
        )
        expect(tasks.fetch('export-1')).to include(
          'operation' => 'export/url',
          'filename' => 'PublicResume.pdf'
        )
      end
    end

    it 'fails clearly when local PDF HTML is missing' do
      Dir.mktmpdir do |root|
        write_project_configuration(root)
        FileUtils.rm(File.join(root, 'build', 'pdf.html'))
        configuration = PdfConversion::Configuration.new(project_root: root, env: {})

        expect { described_class.new(configuration).build_import_task }
          .to raise_error(RuntimeError, /Local source file not found/)
      end
    end

    it 'builds before reading input and packages after downloading' do
      configuration = PdfConversion::Configuration.new(
        project_root: File.expand_path('../..', __dir__),
        env: { 'FREECONVERT_API_KEY' => 'test-key' }
      )
      runner = described_class.new(configuration)

      expect(runner).to receive(:run_local_build).with(allow_missing_pdf: true).ordered
      expect(runner).to receive(:build_input_body).and_return({ 'tasks' => {} }).ordered
      expect(runner).to receive(:submit_job).and_return('https://api.example.test/job/1').ordered
      expect(runner).to receive(:wait_for_completion).ordered
      expect(runner).to receive(:synchronize_pdf_source).ordered
      expect(runner).to receive(:run_local_build).with(allow_missing_pdf: false).ordered

      runner.run
    end

    it 'allows the initial build to proceed when the configured PDF does not exist' do
      Dir.mktmpdir do |root|
        write_project_configuration(root)
        File.write(File.join(root, 'build_resume.bash'), "#!/bin/sh\n")
        configuration = PdfConversion::Configuration.new(
          project_root: root,
          env: { 'FREECONVERT_API_KEY' => 'test-key' }
        )
        captured_environment = nil
        command_runner = lambda do |environment, *_command|
          captured_environment = environment
          true
        end
        runner = described_class.new(configuration, command_runner: command_runner)

        runner.run_local_build(allow_missing_pdf: true)

        expect(captured_environment['RESUME_SKIP_PDF_COPY']).to eq('1')
      end
    end

    it 'raises when the local build command fails' do
      Dir.mktmpdir do |root|
        write_project_configuration(root)
        File.write(File.join(root, 'build_resume.bash'), "#!/bin/sh\n")
        configuration = PdfConversion::Configuration.new(project_root: root, env: {})
        runner = described_class.new(configuration, command_runner: ->(*) { false })

        expect { runner.run_local_build(allow_missing_pdf: true) }
          .to raise_error(RuntimeError, /Build failed/)
      end
    end

    it 'copies an overridden output path back to the configured PDF source' do
      Dir.mktmpdir do |root|
        write_project_configuration(root)
        output_path = File.join(root, 'tmp', 'converted.pdf')
        FileUtils.mkdir_p(File.dirname(output_path))
        File.binwrite(output_path, '%PDF-converted')
        configuration = PdfConversion::Configuration.new(
          project_root: root,
          env: {
            'FREECONVERT_API_KEY' => 'test-key',
            'FREECONVERT_OUTPUT_PATH' => output_path
          }
        )
        runner = described_class.new(configuration)

        runner.synchronize_pdf_source

        expect(File.binread(File.join(root, 'Resume.pdf'))).to eq('%PDF-converted')
      end
    end

    it 'sends the API key as a bearer token when submitting a job' do
      configuration = PdfConversion::Configuration.new(
        project_root: File.expand_path('../..', __dir__),
        env: { 'FREECONVERT_API_KEY' => 'secret-key' }
      )
      captured_request = nil
      adapter = lambda do |_uri, request|
        captured_request = request
        json_response(201, 'id' => 'job-1', 'links' => { 'self' => 'https://api.example.test/job/1' })
      end
      runner = described_class.new(configuration, http_adapter: adapter)

      expect(runner.submit_job('tasks' => {})).to eq('https://api.example.test/job/1')
      expect(captured_request['Authorization']).to eq('Bearer secret-key')
    end

    it 'omits authorization when no API key is configured' do
      configuration = PdfConversion::Configuration.new(
        project_root: File.expand_path('../..', __dir__),
        env: {}
      )
      captured_request = nil
      adapter = lambda do |_uri, request|
        captured_request = request
        json_response(201, 'id' => 'job-1', 'links' => { 'self' => 'https://api.example.test/job/1' })
      end
      runner = described_class.new(configuration, http_adapter: adapter)

      expect(runner.submit_job('tasks' => {})).to eq('https://api.example.test/job/1')
      expect(captured_request['Authorization']).to be_nil
    end

    it 'polls a pending job through completion and downloads the PDF' do
      Dir.mktmpdir do |root|
        write_project_configuration(root)
        configuration = PdfConversion::Configuration.new(
          project_root: root,
          env: { 'FREECONVERT_POLL_INTERVAL_SECONDS' => '2' }
        )
        responses = [
          json_response(200, 'status' => 'processing'),
          json_response(
            200,
            'status' => 'completed',
            'tasks' => {
              'export-1' => {
                'operation' => 'export/url',
                'result' => { 'url' => 'https://download.example.test/resume.pdf' }
              }
            }
          ),
          http_response(200, '%PDF-downloaded')
        ]
        requested_urls = []
        sleeps = []
        adapter = lambda do |uri, _request|
          requested_urls << uri.to_s
          responses.shift || raise('Unexpected HTTP request')
        end
        runner = described_class.new(
          configuration,
          http_adapter: adapter,
          sleeper: ->(seconds) { sleeps << seconds }
        )

        runner.wait_for_completion('https://api.example.test/job/1')

        expect(sleeps).to eq([2])
        expect(requested_urls).to eq([
          'https://api.example.test/job/1',
          'https://api.example.test/job/1',
          'https://download.example.test/resume.pdf'
        ])
        expect(File.binread(File.join(root, 'Resume.pdf'))).to eq('%PDF-downloaded')
      end
    end

    it 'raises when a conversion job fails' do
      configuration = PdfConversion::Configuration.new(
        project_root: File.expand_path('../..', __dir__),
        env: {}
      )
      adapter = ->(*) { json_response(200, 'status' => 'failed', 'error' => 'conversion failed') }
      runner = described_class.new(configuration, http_adapter: adapter)

      expect { runner.wait_for_completion('https://api.example.test/job/1') }
        .to raise_error(RuntimeError, /Job failed/)
    end

    it 'times out after the configured number of polls' do
      configuration = PdfConversion::Configuration.new(
        project_root: File.expand_path('../..', __dir__),
        env: {
          'FREECONVERT_MAX_POLLS' => '2',
          'FREECONVERT_POLL_INTERVAL_SECONDS' => '0'
        }
      )
      polls = 0
      sleeps = []
      adapter = lambda do |_uri, _request|
        polls += 1
        json_response(200, 'status' => 'processing')
      end
      runner = described_class.new(
        configuration,
        http_adapter: adapter,
        sleeper: ->(seconds) { sleeps << seconds }
      )

      expect { runner.wait_for_completion('https://api.example.test/job/1') }
        .to raise_error(RuntimeError, /Timed out waiting for job completion after 2 polls/)
      expect(polls).to eq(2)
      expect(sleeps).to eq([0])
    end

    it 'reports malformed JSON responses' do
      configuration = PdfConversion::Configuration.new(
        project_root: File.expand_path('../..', __dir__),
        env: {}
      )
      runner = described_class.new(
        configuration,
        http_adapter: ->(*) { http_response(200, 'not-json') }
      )

      expect { runner.submit_job('tasks' => {}) }
        .to raise_error(RuntimeError, /Invalid JSON response \(status 200\)/)
    end

    it 'reports job submission and polling HTTP errors' do
      configuration = PdfConversion::Configuration.new(
        project_root: File.expand_path('../..', __dir__),
        env: {}
      )

      submit_runner = described_class.new(
        configuration,
        http_adapter: ->(*) { json_response(422, 'error' => 'invalid job') }
      )
      expect { submit_runner.submit_job('tasks' => {}) }
        .to raise_error(RuntimeError, /Request failed with code 422/)

      poll_runner = described_class.new(
        configuration,
        http_adapter: ->(*) { http_response(503, 'unavailable') }
      )
      expect { poll_runner.wait_for_completion('https://api.example.test/job/1') }
        .to raise_error(RuntimeError, /Job polling failed with code 503/)
    end

    it 'retries transient HTTP failures and then succeeds' do
      configuration = PdfConversion::Configuration.new(
        project_root: File.expand_path('../..', __dir__),
        env: {
          'FREECONVERT_HTTP_MAX_RETRIES' => '2',
          'FREECONVERT_HTTP_RETRY_BASE_DELAY_SECONDS' => '0.5'
        }
      )
      attempts = 0
      sleeps = []
      adapter = lambda do |_uri, _request|
        attempts += 1
        raise SocketError, 'temporary failure' if attempts < 3

        json_response(201, 'links' => { 'self' => 'https://api.example.test/job/1' })
      end
      runner = described_class.new(
        configuration,
        http_adapter: adapter,
        sleeper: ->(seconds) { sleeps << seconds }
      )

      expect(runner.submit_job('tasks' => {})).to eq('https://api.example.test/job/1')
      expect(attempts).to eq(3)
      expect(sleeps).to eq([0.5, 1.0])
    end

    it 'raises after transient HTTP retries are exhausted' do
      configuration = PdfConversion::Configuration.new(
        project_root: File.expand_path('../..', __dir__),
        env: {
          'FREECONVERT_HTTP_MAX_RETRIES' => '2',
          'FREECONVERT_HTTP_RETRY_BASE_DELAY_SECONDS' => '0'
        }
      )
      attempts = 0
      adapter = lambda do |_uri, _request|
        attempts += 1
        raise SocketError, 'still unavailable'
      end
      runner = described_class.new(configuration, http_adapter: adapter, sleeper: ->(_seconds) {})

      expect { runner.submit_job('tasks' => {}) }
        .to raise_error(RuntimeError, /HTTP request failed after 3 attempts: SocketError still unavailable/)
      expect(attempts).to eq(3)
    end

    it 'raises when a completed job has no export URL' do
      configuration = PdfConversion::Configuration.new(
        project_root: File.expand_path('../..', __dir__),
        env: {}
      )
      adapter = lambda do |_uri, _request|
        json_response(200, 'status' => 'completed', 'tasks' => [{ 'operation' => 'convert' }])
      end
      runner = described_class.new(configuration, http_adapter: adapter)

      expect { runner.wait_for_completion('https://api.example.test/job/1') }
        .to raise_error(RuntimeError, /Could not locate export URL/)
    end

    it 'raises when the exported PDF download fails' do
      configuration = PdfConversion::Configuration.new(
        project_root: File.expand_path('../..', __dir__),
        env: {}
      )
      responses = [
        json_response(
          200,
          'status' => 'completed',
          'tasks' => [{ 'operation' => 'export/url', 'result' => { 'url' => 'https://download.example.test/resume.pdf' } }]
        ),
        http_response(502, 'bad gateway')
      ]
      runner = described_class.new(configuration, http_adapter: ->(*) { responses.shift })

      expect { runner.wait_for_completion('https://api.example.test/job/1') }
        .to raise_error(RuntimeError, /Download failed with code 502/)
    end
  end
end
