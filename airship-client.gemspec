Gem::Specification.new do |s|
  s.name        = "airship-ruby"
  s.version     = "1.0.0"
  s.licenses    = ["MIT"]
  s.summary     = "Airship Ruby SDK"
  s.description = "Ruby SDK"
  s.authors     = ["Airship Dev Team"]
  s.email       = "support@airshiphq.com"
  s.files       = ["lib/airship-ruby.rb"]
  s.homepage    = "https://airshiphq.com"
  s.metadata    = { "source_code_uri" => "https://github.com/airshiphq/airship-ruby" }
  s.add_runtime_dependency "faraday", ">= 0.9.0"
  s.add_runtime_dependency "json", ">= 1.7.7"
end
