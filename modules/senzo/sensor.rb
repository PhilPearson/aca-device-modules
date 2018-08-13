require 'net/http'
require 'rubygems'
require 'json'
require 'uv-rays'
require 'libuv'

module Senzo; end

class Senzo::Sensor
    include ::Orchestrator::Constants

    descriptive_name 'Senzo Occupancy Sensor'
    generic_name :Sensor
    implements :logic

    # get root node id
    # https://backend.senzodata.com/api/user/me?apikey=363497c3-7089-433a-9b20-671f57088cb7

    # node stucture of root node
    # https://backend.senzodata.com/api/node/structure/4993?apikey=363497c3-7089-433a-9b20-671f57088cb7

    # live sensor status
    # https://backend.senzodata.com/api/sensor/live/4991?apikey=363497c3-7089-433a-9b20-671f57088cb7
    # https://backend.senzodata.com/api/node/status/4993?apikey=363497c3-7089-433a-9b20-671f57088cb7
    default_settings({
        api_key: '363497c3-7089-433a-9b20-671f57088cb7',
    })

    def on_load
        on_update
    end

    def on_update
        @url = "https://backend.senzodata.com/api/sensor/live/4991?apikey=#{setting(:api_key)}"
    end

    # Return true when detected and false when not
    def in_use?
        logger.debug { @url }
        ret = Net::HTTP.get(URI.parse(@url))
        parsed = JSON.parse(ret) # parse the JSON string into a usable hash table
        presence = parsed[0]['inuse']
    end
=begin
    def get_csv(start_date, end_date)
        url =   "https://backend.senzodata.com/api/csv/sensor/raw/4991?apikey=#{setting(:api_key)}
                &startdate=#{start_date}&enddate=#{end_date}"
    end
=end
end
