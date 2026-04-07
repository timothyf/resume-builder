require 'net/http'
require 'json'

def wait_for_completion(job_url)
    uri = URI(job_url)

    # Create an HTTP GET request
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true # Use HTTPS
    request = Net::HTTP::Get.new(uri.request_uri)
    # Send the request and print the response
    response = http.request(request)
    if response.code == '200'
        if JSON.parse(response.body)['status'] == 'completed'
            puts "Job completed"
            #puts response.body
            # Download the file
            download_uri = URI(JSON.parse(response.body)['tasks'][2]['result']['url'])
            download_http = Net::HTTP.new(download_uri.host, download_uri.port)
            download_http.use_ssl = true # Use HTTPS
            download_request = Net::HTTP::Get.new(download_uri.request_uri)
            download_response = download_http.request(download_request)
            if download_response.code == '200'
                File.open('build/TimothyFisherResume.pdf', 'wb') do |file|
                    file.write(download_response.body)
                end
                puts "File downloaded"
            else
                puts "Download failed with code: #{download_response.code}"
                puts download_response.body
            end
        elsif JSON.parse(response.body)['status'] == 'failed'
            puts "Job failed"
            puts response.body
        else
            puts "Job pending"
            #puts response.body
            sleep(5)
            wait_for_completion(job_url)
        end
    end
end 

# Define the inputBody and headers
input_body = {
    "tasks"=> {
        "import-3"=> {
            "operation"=> "import/webpage",
            "url"=> "https://resume.timothyfisher.com/pdf.html"
        },
        "convert-1"=> {
            "operation"=> "convert",
            "input"=> "import-3",
            "input_format"=> "html",
            "output_format"=> "pdf",
            "options"=> {
                "page_size"=> "letter",
                "page_orientation"=> "portrait",
                "margin"=> "60",
                "hide_cookie"=> true,
                "use_print_stylesheet"=> true
            }
        },
        "export-1"=> {
            "operation"=> "export/url",
            "input"=> [
                "convert-1"
            ],
            "filename"=> "TimothyFisherResume.pdf"
        }
    }
}

headers = {
  'Content-Type' => 'application/json',
  'Accept' => 'application/json',
  'Authorization' => 'Bearer {access-token}'
}

uri = URI('https://api.freeconvert.com/v1/process/jobs')

# Create an HTTP POST request
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true # Use HTTPS

request = Net::HTTP::Post.new(uri.request_uri)
request.body = input_body.to_json
headers.each { |key, value| request[key] = value }

# Send the request and print the response
response = http.request(request)

if response.code == '200'
  puts JSON.parse(response.body)
elsif response.code == '201'
    puts "Request accepted"
    #puts response.body
    payload = JSON.parse(response.body)
    puts "Job ID: #{payload['id']}"
    puts "Job Status: #{payload['status']}"
    puts "Job URL: #{payload['links']['self']}"
    wait_for_completion(payload['links']['self'])
else
  puts "Request failed with code: #{response.code}"
  puts response.body
end

