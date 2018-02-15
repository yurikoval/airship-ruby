require 'faraday'
require 'json'
require 'concurrent'

class Airship
  def initialize(options)
    @gatingInfo = nil
    @gatingInfoThread = nil

    @gatingInfoMap = nil

    @maxGateStatsBatchSize = 500
    @gateStatsUploadBatchInterval = 60

    @gateStatsUploadThread = nil
    @gateStatsBatch = []

    @semaphore = Concurrent::Semaphore.new(1)
  end

  def init()

  end
end
