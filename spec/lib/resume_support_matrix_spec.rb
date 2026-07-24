require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'yaml'
require 'resume_support_matrix'

RSpec.describe ResumeSupportMatrix do
  def write_yaml(root, relative_path, value)
    path = File.join(root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, YAML.dump(value))
  end

  def write_resume(root, user, name)
    write_yaml(root, "data/#{user}/#{name}.yml", { 'placeholder' => true })
  end

  def passing_validator_factory
    lambda do |_env|
      instance_double(ResumeDataValidator, validate!: true)
    end
  end

  it 'validates every supported repository resume' do
    matrix = described_class.new(project_root: File.expand_path('../..', __dir__))

    expect(matrix.validate!).to be(true)
    # expect(matrix.supported.length).to eq(11)
    # expect(matrix.archived.length).to eq(2)
  end

  it 'rejects resume definitions that are not classified' do
    Dir.mktmpdir do |root|
      write_resume(root, 'person', 'resume_current')
      write_resume(root, 'person', 'resume_unclassified')
      write_yaml(root, 'data/resume_support.yml', {
        'supported' => [{ 'user' => 'person', 'name' => 'resume_current' }],
        'archived' => []
      })

      expect do
        described_class.new(
          project_root: root,
          validator_factory: passing_validator_factory
        ).validate!
      end.to raise_error(
        described_class::ValidationError,
        %r{person/resume_unclassified is not classified}
      )
    end
  end

  it 'does not require Git-ignored local resumes to be classified' do
    Dir.mktmpdir do |root|
      write_resume(root, 'johndoe', 'resume_sample')
      write_resume(root, 'privateperson', 'resume_private')
      write_yaml(root, 'data/resume_support.yml', {
        'supported' => [{ 'user' => 'johndoe', 'name' => 'resume_sample' }],
        'archived' => []
      })
      File.write(File.join(root, '.gitignore'), "/data/privateperson/\n")
      system('git', 'init', '--quiet', root, exception: true)

      matrix = described_class.new(
        project_root: root,
        validator_factory: passing_validator_factory
      )

      expect(matrix.validate!).to be(true)
    end
  end

  it 'allows Git-ignored local resumes to be explicitly classified' do
    Dir.mktmpdir do |root|
      write_resume(root, 'johndoe', 'resume_sample')
      write_resume(root, 'privateperson', 'resume_private')
      write_yaml(root, 'data/resume_support.yml', {
        'supported' => [{ 'user' => 'johndoe', 'name' => 'resume_sample' }],
        'archived' => [{
          'user' => 'privateperson',
          'name' => 'resume_private',
          'reason' => 'Local private resume.'
        }]
      })
      File.write(File.join(root, '.gitignore'), "/data/privateperson/\n")
      system('git', 'init', '--quiet', root, exception: true)

      matrix = described_class.new(
        project_root: root,
        validator_factory: passing_validator_factory
      )

      expect(matrix.validate!).to be(true)
    end
  end

  it 'accepts public classifications from the example manifest' do
    Dir.mktmpdir do |root|
      write_resume(root, 'johndoe', 'resume_sample')
      write_resume(root, 'privateperson', 'resume_private')
      write_yaml(root, 'data/resume_support.yml', {
        'supported' => [{ 'user' => 'privateperson', 'name' => 'resume_private' }],
        'archived' => []
      })
      write_yaml(root, 'data/resume_support.yml.example', {
        'supported' => [{ 'user' => 'johndoe', 'name' => 'resume_sample' }],
        'archived' => []
      })

      matrix = described_class.new(
        project_root: root,
        validator_factory: passing_validator_factory
      )

      expect(matrix.validate!).to be(true)
    end
  end

  it 'rejects stale and duplicate classifications' do
    Dir.mktmpdir do |root|
      write_resume(root, 'person', 'resume_current')
      write_yaml(root, 'data/resume_support.yml', {
        'supported' => [{ 'user' => 'person', 'name' => 'resume_current' }],
        'archived' => [
          {
            'user' => 'person',
            'name' => 'resume_current',
            'reason' => 'Superseded.'
          },
          {
            'user' => 'person',
            'name' => 'resume_missing',
            'reason' => 'Removed.'
          }
        ]
      })

      expect do
        described_class.new(
          project_root: root,
          validator_factory: passing_validator_factory
        ).validate!
      end.to raise_error(described_class::ValidationError) { |error|
        expect(error.message).to include('person/resume_current is classified 2 times')
        expect(error.message).to include('person/resume_missing is declared')
      }
    end
  end

  it 'requires archived resumes to include a reason' do
    Dir.mktmpdir do |root|
      write_resume(root, 'person', 'resume_legacy')
      write_yaml(root, 'data/resume_support.yml', {
        'supported' => [],
        'archived' => [{ 'user' => 'person', 'name' => 'resume_legacy' }]
      })

      expect do
        described_class.new(
          project_root: root,
          validator_factory: passing_validator_factory
        ).validate!
      end.to raise_error(described_class::ValidationError, /reason must be a non-empty string/)
    end
  end

  it 'validates supported resumes, skips archived resumes, and aggregates failures' do
    Dir.mktmpdir do |root|
      write_resume(root, 'person', 'resume_current')
      write_resume(root, 'person', 'resume_legacy')
      write_yaml(root, 'data/resume_support.yml', {
        'supported' => [{ 'user' => 'person', 'name' => 'resume_current' }],
        'archived' => [{
          'user' => 'person',
          'name' => 'resume_legacy',
          'reason' => 'Legacy schema.'
        }]
      })
      validated = []
      factory = lambda do |env|
        validated << "#{env.fetch('ACTIVE_RESUME_USER')}/#{env.fetch('ACTIVE_RESUME_NAME')}"
        instance_double(ResumeDataValidator).tap do |validator|
          allow(validator).to receive(:validate!).and_raise(
            ResumeDataValidator::ValidationError.new(
              user: 'person',
              resume: 'resume_current',
              errors: ['missing required value']
            )
          )
        end
      end

      expect do
        described_class.new(project_root: root, validator_factory: factory).validate!
      end.to raise_error(described_class::ValidationError, /resume_current: missing required value/)
      expect(validated).to eq(['person/resume_current'])
    end
  end
end
