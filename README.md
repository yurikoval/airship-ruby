# airship-ruby

## Installation
`gem install airship-ruby`


## Usage
```ruby
require "airship-ruby"

# Create an instance with api_key and env_key
airship = Airship.new({api_key: <api_key>, env_key: <env_key>})

# e.g.,
# airship = Airship.new({api_key: "r9b72kqdh1wbzkpkf7gntwfapqoc26bl", env_key: "nxmqp35umrd3djth"})

# Initialize the instance. After init, the instance becomes thread-safe
airship.init()

# Define your object
object = {
  "type" => "User", # "type" starts with a capital letter "[U]ser", "[H]ome", "[C]ar"
  "id" => "1234", # "id" must be a string, so if you wish to pass an integer, simply convert via .to_s
  "display_name" => "ironman@stark.com" # must also be a string
}

airship.enabled?("bitcoin-pay", object)
airship.variation("bitcoin-pay", object) # For multi-variate flags
airship.eligible?("bitcoin-pay", object)
# Returns true if the object can potentially receive the feature via sampling
# or is already receiving the feature.
```
