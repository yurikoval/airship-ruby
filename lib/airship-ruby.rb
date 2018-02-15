require 'faraday'
require 'json'

class Airship
  def initialize(options)
    @gatingInfo = nil
    @gatingInfoThread = nil

    @gatingInfoMap = nil

    @maxGateStatsBatchSize = 500
    @gateStatsUploadBatchInterval = 60

    @gateStatsUploadThread = nil
    @gateStatsBatch = []
  end
end
