require 'faraday'
require 'json'
require 'concurrent'
require 'digest'
require 'rubygems'
require 'json-schema'


class Airship
  SCHEMA = {
    "type" => "object",
    "properties" => {
      "type" => {
        "type" => "string",
        "pattern" => "^([A-Z][a-zA-Z]*)+$",
        "maxLength" => 50,
      },
      "is_group" => {
        "type" => "boolean",
      },
      "id" => {
        "type" => "string",
        "maxLength" => 250,
        "minLength" => 1,
      },
      "display_name" => {
        "type" => "string",
        "maxLength" => 250,
        "minLength" => 1,
      },
      "attributes" => {
        "type" => "object",
        "patternProperties" => {
          "^[a-zA-Z][a-zA-Z_]{0,48}[a-zA-Z]$" => {
            "oneOf" => [
              {
                "type" => "string",
                "maxLength" => 3000,
              },
              {
                "type" => "boolean"
              },
              {
                "type" => "number"
              },
            ],
          },
        },
        "maxProperties" => 100,
        "additionalProperties" => false,
      },
      "group" => {
        "type" => ["object", "null"],
        "properties" => {
          "type" => {
            "type" => "string",
            "pattern" => "^([A-Z][a-zA-Z]*)+$",
            "maxLength" => 50,
          },
          "is_group" => {
            "type" => "boolean",
            "enum" => [true],
          },
          "id" => {
            "type" => "string",
            "maxLength" => 250,
            "minLength" => 1,
          },
          "display_name" => {
            "type" => "string",
            "maxLength" => 250,
            "minLength" => 1,
          },
          "attributes" => {
            "type" => "object",
            "patternProperties" => {
              "^[a-zA-Z][a-zA-Z_]{0,48}[a-zA-Z]$" => {
                "oneOf" => [
                  {
                    "type" => "string",
                    "maxLength" => 3000,
                  },
                  {
                    "type" => "boolean"
                  },
                  {
                    "type" => "number"
                  },
                ],
              },
            },
            "maxProperties" => 100,
            "additionalProperties" => false,
          },
        },
        "required" => ["id", "display_name"],
        "additionalProperties" => false,
      },
    },
    "required" => ["type", "id", "display_name"],
    "additionalProperties" => false,
  }

  SERVER_URL = 'http://localhost:8000'
  IDENTIFY_ENDPOINT = "#{SERVER_URL}/v1/identify"
  GATING_INFO_ENDPOINT = "#{SERVER_URL}/v1/gating-info"
  PLATFORM = 'ruby'
  VERSION = Gem::Specification::load(
    File.join(
      File.dirname(
        File.dirname(
          File.expand_path(__FILE__)
        )
      ),
      'airship-ruby.gemspec'
    )
  ).version.to_s

  SDK_VERSION = "#{PLATFORM}:#{VERSION}"

  CONTROL_TYPE_BOOLEAN = 'boolean'
  CONTROL_TYPE_MULTIVARIATE = 'multivariate'

  DISTRIBUTION_TYPE_RULE_BASED = 'R'
  DISTRIBUTION_TYPE_PERCENTAGE_BASED = 'P'

  OBJECT_ATTRIBUTE_TYPE_STRING = 'STRING'
  OBJECT_ATTRIBUTE_TYPE_INT = 'INT'
  OBJECT_ATTRIBUTE_TYPE_FLOAT = 'FLOAT'
  OBJECT_ATTRIBUTE_TYPE_BOOLEAN = 'BOOLEAN'
  OBJECT_ATTRIBUTE_TYPE_DATE = 'DATE'
  OBJECT_ATTRIBUTE_TYPE_DATETIME = 'DATETIME'

  RULE_OPERATOR_TYPE_IS = 'IS'
  RULE_OPERATOR_TYPE_IS_NOT = 'IS_NOT'
  RULE_OPERATOR_TYPE_IN = 'IN'
  RULE_OPERATOR_TYPE_NOT_IN = 'NOT_IN'
  RULE_OPERATOR_TYPE_LT = 'LT'
  RULE_OPERATOR_TYPE_LTE = 'LTE'
  RULE_OPERATOR_TYPE_GT = 'GT'
  RULE_OPERATOR_TYPE_GTE = 'GTE'
  RULE_OPERATOR_TYPE_FROM = 'FROM'
  RULE_OPERATOR_TYPE_UNTIL = 'UNTIL'
  RULE_OPERATOR_TYPE_AFTER = 'AFTER'
  RULE_OPERATOR_TYPE_BEFORE = 'BEFORE'

  class << self
    def get_hashed_value(s)
      Digest::MD5.hexdigest(s).to_i(base=16).fdiv(340282366920938463463374607431768211455)
    end
  end

  def initialize(options)

    @api_key = options[:api_key]
    @env_key = options[:env_key]

    if @api_key.nil?
      raise Exception.new('Missing api_key')
    end

    if @env_key.nil?
      raise Exception.new('Missing env_key')
    end

    @gating_info = nil
    @gating_info_downloader_task = nil

    @gating_info_map = nil

    @max_gate_stats_batch_size = 500
    @gate_stats_upload_batch_interval = 60

    @gate_stats_watcher = nil
    @gate_stats_last_task_scheduled_timestamp = Concurrent::AtomicFixnum.new(0)

    @gate_stats_uploader_tasks = []

    @gate_stats_batch = []

    @gate_stats_batch_lock = Concurrent::Semaphore.new(1)
  end

  def init
    # Not thread safe yet
    if @gating_info_downloader_task.nil?
      @gating_info_downloader_task = self._create_poller
      @gating_info_downloader_task.execute
    end

    if @gate_stats_watcher.nil?
      @gate_stats_watcher = self._create_watcher
      @gate_stats_watcher.execute
    end
    # Thread safe after this point
  end

  def _get_gating_info_map(gating_info)
    map = {}

    controls = gating_info['controls']

    controls.each do |control|
      control_info = {}

      control_info['id'] = control['id']
      control_info['is_on'] = control['is_on']
      control_info['rule_based_distribution_default_variation'] = control['rule_based_distribution_default_variation']
      control_info['rule_sets'] = control['rule_sets']
      control_info['distributions'] = control['distributions']
      control_info['type'] = control['type']
      control_info['default_variation'] = control['default_variation']

      enablements = control['enablements']
      enablements_info = {}

      enablements.each do |enablement|
        client_identities_map = enablements_info[enablement['client_object_type_name']]

        if client_identities_map.nil?
          enablements_info[enablement['client_object_type_name']] = {}
        end

        enablements_info[enablement['client_object_type_name']][enablement['client_object_identity']] = [enablement['is_enabled'], enablement['variation']]
      end

      control_info['enablements_info'] = enablements_info

      map[control['short_name']] = control_info
    end

    map
  end

  def _create_poller
    Concurrent::TimerTask.new(execution_interval: 60, timeout_interval: 10, run_now: true) do |task|
      conn = Faraday.new(url: "#{GATING_INFO_ENDPOINT}/#{@env_key}")
      response = conn.get do |req|
        req.options.timeout = 10
        req.headers['api-key'] = @api_key
      end
      if response.status == 200
        gating_info = JSON.parse(response.body)
        gating_info_map = self._get_gating_info_map(gating_info)
        @gating_info = gating_info
        @gating_info_map = gating_info_map
      end
    end
  end

  def _create_watcher
    Concurrent::TimerTask.new(execution_interval: 60, timeout_interval: 10, run_now: true) do |task|
      now = Time.now.utc.to_i
      if now - @gate_stats_last_task_scheduled_timestamp.value >= 60
        processed = self._process_batch(0)
        if processed
          @gate_stats_last_task_scheduled_timestamp.value = now
        end
      end
    end
  end

  def _create_processor(batch)
    return Concurrent::ScheduledTask.execute(0) do |task|
      # TODO: use Faraday to upload
    end
  end

  def _process_batch(limit)
    processed = false
    @gate_stats_batch_lock.acquire
    if @gate_stats_batch.size > limit
      new_gate_stats_uploader_tasks = []
      @gate_stats_uploader_tasks.each do |task|
        if !task.fulfilled?
          new_gate_stats_uploader_tasks.push(task)
        end
      end
      old_batch = @gate_stats_batch
      @gate_stats_batch = []
      new_gate_stats_uploader_tasks.push(self._create_processor(old_batch))
      @gate_stats_uploader_tasks = new_gate_stats_uploader_tasks
      processed = true
    end
    @gate_stats_batch_lock.release
    processed
  end

  def _check_batch_size_and_maybe_process
    processed = self._process_batch(@max_gate_stats_batch_size - 1)
    if processed
      now = Time.now.utc.to_i
      @gate_stats_last_task_scheduled_timestamp.value = now
    end
  end

  def _upload_stats_async(stats)
    @gate_stats_batch_lock.acquire
    @gate_stats_batch.push(stats)
    @gate_stats_batch_lock.release

    self._check_batch_size_and_maybe_process
  end

  def _clone_object(object)
    copy = object.clone

    if (!object['attributes'].nil?) {
      copy['attributes'] = object['attributes'].clone
    }

    if (!object['group'].nil?) {
      copy['group'] = object['group'].clone

      if (!object['group']['attributes'].nil?) {
        copy['group']['attributes'] = object['group']['attributes'].clone
      }
    }

    copy
  end

  def _validate_nesting(object)
    if (object['is_group'] === true && !object['group'].nil?) {
      return 'A group cannot be nested inside another group'
    }

    nil
  end

  def enabled?(control_short_name, object)
    if @gating_info_map.nil?
      return false
    end

    validation_errors = JSON::Validator.fully_validate(Airship::SCHEMA, object)
    if validation_errors.size > 0
      puts validation_errors[0]
      return false
    end

    object = self._clone_object(object)

    error = self._validate_nesting(object)

    if !error.nil?
      puts error
      return false
    end
  end

  def variation(control_short_name, object)
    if @gating_info_map.nil?
      return nil
    end

    validation_errors = JSON::Validator.fully_validate(Airship::SCHEMA, object)
    if validation_errors.size > 0
      puts validation_errors[0]
      return nil
    end

    object = self._clone_object(object)

    error = self._validate_nesting(object)

    if !error.nil?
      puts error
      return nil
    end
  end

  def eligible?(control_short_name, object)
    if @gating_info_map.nil?
      return false
    end

    validation_errors = JSON::Validator.fully_validate(Airship::SCHEMA, object)
    if validation_errors.size > 0
      puts validation_errors[0]
      return false
    end

    object = self._clone_object(object)

    error = self._validate_nesting(object)

    if !error.nil?
      puts error
      return false
    end
  end
end
