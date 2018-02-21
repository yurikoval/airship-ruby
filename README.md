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

airship.enabled?("bitcoin-pay", object) # Does the object have the feature "bitcoin-pay"?
airship.variation("bitcoin-pay", object) # Get the variation associated with a multi-variate flag
airship.eligible?("bitcoin-pay", object)
# Returns true if the object can potentially receive the feature via sampling
# or is already receiving the feature.
```


## Attributes (for complex targeting)
```ruby
# Define your object with an attributes dictionary of key-value pairs.
# Values must be a string, a number, or a boolean. nil values are not accepted.
# For date or datetime string value, use iso8601 format.
object = {
  "type" => "User",
  "id" => "1234",
  "display_name" => "ironman@stark.com",
  "attributes" => {
    "t_shirt_size" => "M",
    "date_created" => "2018-02-18",
    "time_converted" => "2018-02-20T21:54:00.630815+00:00",
    "owns_property" => true,
    "age" => 39
  }
}

# Now in app.airshiphq.com, you can target this particular user using its
# attributes
```

## Group (for membership-like cascading behavior)
```ruby
# An object can be a member of a group.
# The structure of a group object is just like that of the base object.
object = {
  "type" => "User",
  "id" => "1234",
  "display_name" => "ironman@stark.com",
  "attributes" => {
    "t_shirt_size" => "M",
    "date_created" => "2018-02-18",
    "time_converted" => "2018-02-20T21:54:00.630815+00:00",
    "owns_property" => true,
    "age" => 39
  },
  "group" => {
    "type" => "Club",
    "id" => "5678",
    "display_name" => "SF Homeowners Club",
    "attributes" => {
      "founded" => "2016-01-01",
      "active" => true
    }
  }
}

# Inheritance of values `enabled?`, `variation`, and `eligible?` works as follows:
# 1. If the group is enabled, but the base object is not,
#    then the base object will inherit the values `enabled?`, `variation`, and
#    `eligible?` of the group object.
# 2. If the base object is explicitly blacklisted, then it will not inherit.
# 3. If the base object is not given a variation in rule-based variation assignment,
#    but the group is and both are enabled, then the base object will inherit
#    the variation of the group's.


# You can ask questions about the group directly (use the `is_group` flag):
object = {
  "is_group" => true,
  "type" => "Club",
  "id" => "5678",
  "display_name" => "SF Homeowners Club",
  "attributes" => {
    "founded" => "2016-01-01",
    "active" => true
  }
}

airship.enabled?("bitcoin-pay", object)
```
