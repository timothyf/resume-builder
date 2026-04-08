require 'fileutils'
require 'json'
require 'net/http'
require 'shellwords'

API_BASE = ENV.fetch('FREECONVERT_API_BASE', 'https://api.freeconvert.com')
SOURCE_PATH = ENV.fetch('FREECONVERT_SOURCE_PATH', 'build/pdf.html')
SOURCE_URL = ENV.fetch('FREECONVERT_SOURCE_URL', '').strip
OUTPUT_PATH = ENV.fetch('FREECONVERT_OUTPUT_PATH', 'build/TimothyFisherResume.pdf')
OUTPUT_FILENAME = ENV.fetch('FREECONVERT_OUTPUT_FILENAME', File.basename(OUTPUT_PATH))
POLL_INTERVAL_SECONDS = Integer(ENV.fetch('FREECONVERT_POLL_INTERVAL_SECONDS', '5'))
MAX_POLLS = Integer(ENV.fetch('FREECONVERT_MAX_POLLS', '120'))
HTTP_TIMEOUT_SECONDS = Integer(ENV.fetch('FREECONVERT_HTTP_TIMEOUT_SECONDS', '30'))
HTTP_MAX_RETRIES = Integer(ENV.fetch('FREECONVERT_HTTP_MAX_RETRIES', '3'))
HTTP_RETRY_BASE_DELAY_SECONDS = Float(ENV.fetch('FREECONVERT_HTTP_RETRY_BASE_DELAY_SECONDS', '1.0'))
BUILD_BEFORE_CONVERT = ENV.fetch('FREECONVERT_BUILD_BEFORE_CONVERT', 'true').strip.downcase != 'false'

def run_local_build_if_needed
    return unless BUILD_BEFORE_CONVERT

    build_script = File.expand_path('build_resume.bash', __dir__)
    unless File.exist?(build_script)
        raise "Build script not found: #{build_script}"
    end

    puts 'Building resume artifacts before PDF conversion...'
    success = system(build_script)
    raise 'Build failed. Fix build errors and run again.' unless success
end

def build_import_task
    unless SOURCE_URL.empty?
        puts "Using source URL: #{SOURCE_URL}"
        return {
            'operation' => 'import/webpage',
            'url' => SOURCE_URL
        }
    end

    source_path = SOURCE_PATH.strip.empty? ? 'build/pdf.html' : SOURCE_PATH
    absolute_source_path = File.expand_path(source_path, __dir__)

    raise "Local source file not found: #{absolute_source_path}" unless File.exist?(absolute_source_path)

    puts "Using local source file: #{absolute_source_path}"
    html_content = File.read(absolute_source_path)

    {
        'operation' => 'import/base64',
        'file' => "data:text/html;base64,#{[html_content].pack('m0')}",
        'filename' => File.basename(source_path)
    }
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
        http.open_timeout = HTTP_TIMEOUT_SECONDS
        http.read_timeout = HTTP_TIMEOUT_SECONDS
        http.request(request)
    rescue Timeout::Error, Errno::ECONNRESET, Errno::ETIMEDOUT, EOFError, SocketError => e
        if attempts <= HTTP_MAX_RETRIES
            sleep_seconds = HTTP_RETRY_BASE_DELAY_SECONDS * (2**(attempts - 1))
            warn "HTTP attempt #{attempts} failed: #{e.class} #{e.message}. Retrying in #{sleep_seconds.round(2)}s..."
            sleep(sleep_seconds)
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
    download_request = Net::HTTP::Get.new(download_uri.request_uri)
    response = perform_request(download_uri, download_request)

    unless response.code == '200'
        raise "Download failed with code #{response.code}: #{response.body}"
    end

    FileUtils.mkdir_p(File.dirname(OUTPUT_PATH))
    File.open(OUTPUT_PATH, 'wb') { |file| file.write(response.body) }
    puts "File downloaded to #{OUTPUT_PATH}"
end

def wait_for_completion(job_url)
    job_uri = URI(job_url)

    (1..MAX_POLLS).each do |attempt|
        response = perform_request(job_uri, Net::HTTP::Get.new(job_uri.request_uri))
        raise "Job polling failed with code #{response.code}: #{response.body}" unless response.code == '200'

        payload = parse_json_response(response)
        status = payload['status']

        case status
        when 'completed'
            puts 'Job completed'
            export_url = find_export_url(payload['tasks'])
            raise 'Could not locate export URL in completed job payload' unless export_url

            download_file(export_url)
            return
        when 'failed'
            raise "Job failed: #{response.body}"
        else
            puts "Job pending (attempt #{attempt}/#{MAX_POLLS})"
            sleep(POLL_INTERVAL_SECONDS)
        end
    end

    raise "Timed out waiting for job completion after #{MAX_POLLS} polls"
end


input_body = {
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
            'filename' => OUTPUT_FILENAME
        }
    }
}

run_local_build_if_needed

headers = {
    'Content-Type' => 'application/json',
    'Accept' => 'application/json',
}

uri = URI("#{API_BASE}/v1/process/jobs")
request = Net::HTTP::Post.new(uri.request_uri)
request.body = input_body.to_json
headers.each { |key, value| request[key] = value }

response = perform_request(uri, request)
payload = parse_json_response(response)

if response.code == '201' || response.code == '200'
    puts 'Request accepted'
    puts "Job ID: #{payload['id']}" if payload['id']
    puts "Job Status: #{payload['status']}" if payload['status']

    job_url = payload.dig('links', 'self')
    raise 'Job URL not found in API response' unless job_url

    wait_for_completion(job_url)
else
    raise "Request failed with code #{response.code}: #{response.body}"
end

