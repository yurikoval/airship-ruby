Gem::Specification.new do |s|
  s.name        = "airship"
  s.version     = "0.1.0"
  s.licenses    = ["MIT"]
  s.summary     = "A light Ruby SDK to access Airship"
  s.description = "Ruby SDK 0.1.0"
  s.authors     = ["Airship Dev Team"]
  s.email       = "hello@airshiphq.com"
  s.files       = ["lib/airship.rb"]
  s.homepage    = "https://rubygems.org/gems/example"
  s.metadata    = { "source_code_uri" => "https://github.com/airshiphq/airship-ruby" }
  s.add_runtime_dependency "faraday", ">= 0.14.0"
end
