require 'faraday'
require 'json'
require 'concurrent'

class Airship
  def initialize(options)
    @gatingInfo = nil
    @gatingInfoTask = nil

    @gatingInfoMap = nil

    @maxGateStatsBatchSize = 500
    @gateStatsUploadBatchInterval = 60

    @gateStatsUploadTask = nil
    @gateStatsBatch = []

    @semaphore = Concurrent::Semaphore.new(1)
  end

  def init()
    @gateInfoTask = Concurrent::TimerTask.new(execution_interval: 60, timeout_interval: 10, run_now: true) do |task|

    end
    @gateInfoTask.execute
  end
end
