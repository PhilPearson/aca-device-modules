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

    # node stucture
    # https://backend.senzodata.com/api/node/structure/4923?apikey=363497c3-7089-433a-9b20-671f57088cb7

    # live sensor status
    # https://backend.senzodata.com/api/sensor/live/4923?apikey=363497c3-7089-433a-9b20-671f57088cb7
    default_settings({
        api_key: '363497c3-7089-433a-9b20-671f57088cb7',
    })

    def on_load
        on_update
    end

    def on_update
        stop
        @url = "http://backend.senzodata.com/api/senzor/live/4923?apikey=#{setting(:api_key)}"
        logger.debug { "url is #{@url}" }
    end

    # Return true when detected and false when not
    def in_use?
        ret = Net::HTTP.get(URI.parse(@url)) # get sensor information in JSON format from api
        parsed = JSON.parse(ret) # parse the JSON string into a usable hash table
        logger.debug { "#{parsed.keys}" }
        presence = parsed['inuse']
    end

    # check for all bookings now and schedule the check for every future 7am
    def start

    end

    def stop
    end
end
