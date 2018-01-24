require "rest-client"
=begin
AirshipClient.init('r9b72kqdh1wbzkpkf7gntwfapqoc26bl', 'nxmqp35umrd3djth')
AirshipClient.set_env_key('c1087mh6a3hjxiaz')
client = AirshipClient.new
client = AirshipClient.new('nxmqp35umrd3djth')
client = AirshipClient.new('c1087mh6a3hjxiaz')

1. Error checking for the keys
2. identify and gate endpoint
client.get_value('<control_name>', <obj>)     -> [false, true]
client.get_variation('<control_name>', <obj>) -> [nil, '<variation1>', '<variation2'>, ...]
client.identify([<obj>, ...])                 -> dictionary
client.gate(<obj>)                            -> dictionary
=end

V1_IDENTIFY_ENDPOINT = 'https://api.airshiphq.com/v1/identify'
V1_GATE_ENDPOINT = 'https://api.airshiphq.com/v1/gate'

DEFAULT_TIMEOUT = 2


class AirshipClient
  @@api_key = nil
  @@env_key = nil
  @@timeout = nil
  @@fail_gracefully = nil

  @api_key = nil
  @env_key = nil

  class << self
    def init(api_key, env_key = nil, timeout = DEFAULT_TIMEOUT, fail_gracefully = true)
      if api_key.nil?
        raise ArgumentError.new("api_key cannot be nil")
      end

      if !api_key.nil?
        self._validate_api_key(api_key)
      end

      if !env_key.nil?
        self._validate_env_key(env_key)
      end

      self._validate_timeout(timeout)
      self._validate_fail_gracefully(fail_gracefully)

      @@api_key = api_key
      @@env_key = env_key
      @@timeout = timeout
      @@fail_gracefully = fail_gracefully
      nil
    end

    def set_env_key(env_key)
      if env_key.nil?
        raise ArgumentError.new("env_key cannot be nil")
      end
      self._validate_env_key(env_key)
      @@env_key = env_key
    end

    def _validate_api_key(api_key)
      if !api_key.instance_of?(String)
        raise ArgumentError.new("api_key must be a string")
      end
    end

    def _validate_env_key(env_key)
      if !env_key.instance_of?(String)
        raise ArgumentError.new("env_key must be a string")
      end
    end

    def _validate_timeout(timeout)
      if !timeout.is_a?(Integer)
        raise ArgumentError.new("timeout must be an integer")
      end
    end

    def _validate_fail_gracefully(fail_gracefully)
      if !(fail_gracefully == true || fail_gracefully == false)
        raise ArgumentError.new("fail_gracefully must be true or false")
      end
    end
  end

  def initialize(api_key = nil, env_key = nil)
    if !api_key.nil?
      self.class._validate_api_key(api_key)
    end

    if !env_key.nil?
      self.class._validate_env_key(env_key)
    end

    @api_key = api_key
    @env_key = env_key
    nil
  end

  def identify(control_name, obj)

  end

  def gate(control_name, obj)

  end

  def get_value(control_name, obj)

  end

  def get_variation(control_name, obj)

  end
end
