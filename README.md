# airship-ruby

## Installation
`gem install airship-client`


## Usage
```ruby
require "airship-client"

# Sets the global api_key and env_key
AirshipClient.init(<api_key>, <env_key>)

# e.g.,
# AirshipClient.init("r9b72kqdh1wbzkpkf7gntwfapqoc26bl", "nxmqp35umrd3djth")

# Create a new client
client = AirshipClient.new

# Override env_key on an instance basis (nil means do not override that particular param, in this case the api_key)
client = AirshipClient.new(nil, "vuvl5bn7btteq8vl")


# There are four methods to the client:
# 1. identify(<obj>|[<obj>, ...])
#    - For individual or bulk data ingestion
# 2. gate(<control_short_name>, <obj>|[<obj>, ...])
#    - Querying for a single object's or multiple objects' control information while ingesting at the same time
#    - If a single object is passed, then the ingestion is synchronous. When multiple objects are passed, the ingestion is asynchronous
# 3. get_value
#    - Convenience method for getting the boolean value
# 4. get_variation
#    - Convenience method for getting the variation associated with a multi-variate control/flag

object = {
  "type" => "User", # "type" starts with a capital letter "[U]ser", "[H]ome", "[C]ar"
  "id" => "1234", # "id" must be a string, so if you wish to pass an integer, simply convert via .to_s
  "display_name" => "ironman@stark.com"
}

client.identify(object)
client.identify([object])
client.gate("bitcoin-pay", object)
client.get_value("bitcoin-pay", object)
client.get_variation("bitcoin-pay", object)
```

## Graceful failure
When graceful failure mode is enabled (which is the default), if a gate call to Airship's server fails or times out, the SDK will return the following values:
```ruby
{
    ...
    "control" => {
        "value" => false,
        "variation" => nil,
        "from_server" => false
    }
    ...
}
```

You can turn off graceful failure during initialization:
```ruby
AirshipClient.init(<api_key>, <env_key>, <timeout>, <fail_gracefully>)
```

Above, `<timeout>` is the number of seconds the SDK waits for a network call before timing out and failing gracefully. The default value is 2 seconds.
