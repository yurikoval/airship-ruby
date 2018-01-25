Gem::Specification.new do |s|
  s.name        = "airship-client"
  s.version     = "0.1.1"
  s.licenses    = ["MIT"]
  s.summary     = "A light Ruby SDK to access Airship"
  s.description = "Ruby SDK"
  s.authors     = ["Airship Dev Team"]
  s.email       = "hello@airshiphq.com"
  s.files       = ["lib/airship.rb"]
  s.homepage    = "https://airshiphq.com"
  s.metadata    = { "source_code_uri" => "https://github.com/airshiphq/airship-ruby" }
  s.add_runtime_dependency "faraday", ">= 0.14.0"
  s.add_runtime_dependency "json", ">= 2.1.0"
end
