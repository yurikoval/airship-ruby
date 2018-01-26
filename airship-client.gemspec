Gem::Specification.new do |s|
  s.name        = "airship-client"
  s.version     = "0.1.4"
  s.licenses    = ["MIT"]
  s.summary     = "A light Ruby SDK to access Airship"
  s.description = "Ruby SDK"
  s.authors     = ["Airship Dev Team"]
  s.email       = "hello@airshiphq.com"
  s.files       = ["lib/airship-client.rb"]
  s.homepage    = "https://airshiphq.com"
  s.metadata    = { "source_code_uri" => "https://github.com/airshiphq/airship-ruby" }
  s.add_runtime_dependency "faraday", ">= 0.9"
  s.add_runtime_dependency "json", ">= 1.7.7"
end
