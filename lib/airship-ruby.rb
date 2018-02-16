require 'faraday'
require 'json'
require 'concurrent'
require 'digest'


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
        "required" => ["id", "displayName"],
        "additionalProperties" => false,
      },
    },
    "required" => ["type", "id", "displayName"],
    "additionalProperties" => false,
  }

  class << self
    def get_hashed_value(s)
      Digest::MD5.hexdigest(s).to_i(base=16).fdiv(340282366920938463463374607431768211455)
    end
  end

  def initialize(options)
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

  def _create_poller
    Concurrent::TimerTask.new(execution_interval: 60, timeout_interval: 10, run_now: true) do |task|
      # TODO: use Faraday to pull info
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

  def enabled?(control_short_name, object)
    false
  end

  def variation(control_short_name, object)
    nil
  end

  def eligible?(control_short_name, object)
    false
  end
end
