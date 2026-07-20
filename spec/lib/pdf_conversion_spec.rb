require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'pdf_conversion'

RSpec.describe PdfConversion do
  def write_project_configuration(root, pdf_source: 'Resume.pdf')
    FileUtils.mkdir_p(File.join(root, 'data', 'person'))
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

    it 'requires an API key before conversion' do
      Dir.mktmpdir do |root|
        write_project_configuration(root)
        configuration = described_class.new(project_root: root, env: {})

        expect { configuration.validate! }
          .to raise_error(ArgumentError, /FREECONVERT_API_KEY is required/)
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
  end

  describe PdfConversion::Runner do
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
      runner = described_class.new(configuration)
      response = instance_double(
        Net::HTTPResponse,
        code: '201',
        body: '{"id":"job-1","links":{"self":"https://api.example.test/job/1"}}'
      )

      expect(runner).to receive(:perform_request) do |_uri, request|
        expect(request['Authorization']).to eq('Bearer secret-key')
        response
      end

      expect(runner.submit_job('tasks' => {})).to eq('https://api.example.test/job/1')
    end
  end
end
